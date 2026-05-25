package com.learntoflutter.flutter_embed_unity_android.unity

import android.content.Context
import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.logTag
import io.flutter.Log
import java.io.File

// [portola] H10 — Android crash collector source foundation. Installs a chained
// UncaughtExceptionHandler (idempotent) on a stable, Activity-independent init path (plugin attach) and
// writes best-effort crash records to an app-private directory. It never adds a permission, never blocks
// on the network, does not depend on an Activity, and never throws a secondary exception.
//
// Real-device induced-crash validation, remote upload / sink, and device-metadata channels are deferred
// (HOLD). This round does not emit any H6 lifecycle/observability trace (no double-emit).
internal object CrashCollector {
    private const val crashDirName = "flutter_embed_unity_crashes"
    private const val maxLogcatLines = 500
    private const val maxStoredCrashFiles = 20

    @Volatile
    private var installed = false

    // Idempotent: only the first call installs the handler; later calls (e.g. re-attach to a new engine)
    // are no-ops, so handlers are never stacked.
    fun install(context: Context) {
        if (installed) {
            return
        }
        synchronized(this) {
            if (installed) {
                return
            }
            try {
                val appContext = context.applicationContext
                val crashDir = File(appContext.filesDir, crashDirName)
                val previous = Thread.getDefaultUncaughtExceptionHandler()
                val sink = AndroidCrashSink(crashDir, maxLogcatLines, maxStoredCrashFiles)
                Thread.setDefaultUncaughtExceptionHandler(CrashCollectorHandler(previous, sink))
                installed = true
                Log.i(logTag, "CrashCollector installed (crashDir=${crashDir.absolutePath})")
            } catch (t: Throwable) {
                // Installation must never break plugin attach.
                Log.w(logTag, "CrashCollector install failed (continuing without it): ${t.message}")
            }
        }
    }
}

private class AndroidCrashSink(
    private val crashDir: File,
    private val maxLogcatLines: Int,
    private val maxStoredCrashFiles: Int,
) : CrashSink {

    // Runs inside the uncaught-exception handler: everything is best-effort and guarded so a failure
    // never produces a secondary crash.
    override fun record(thread: Thread, throwable: Throwable) {
        val now = System.currentTimeMillis()
        val content = CrashReport.format(
            threadName = thread.name,
            throwable = throwable,
            timestampMillis = now,
            logcatTail = collectLogcatTail(),
            tombstoneInfo = tombstoneHint(),
        )
        writeCrashFile(now, content)
    }

    private fun writeCrashFile(timestampMillis: Long, content: String) {
        try {
            if (!crashDir.exists()) {
                crashDir.mkdirs()
            }
            pruneOldFiles()
            File(crashDir, CrashReport.fileName(timestampMillis)).writeText(content)
        } catch (t: Throwable) {
            // best-effort: never throw from the crash path.
        }
    }

    // Cap the number of retained crash files so the directory cannot grow unbounded.
    private fun pruneOldFiles() {
        try {
            val files = crashDir.listFiles()?.filter { it.isFile } ?: return
            if (files.size < maxStoredCrashFiles) {
                return
            }
            files.sortedBy { it.lastModified() }
                .take(files.size - maxStoredCrashFiles + 1)
                .forEach { file -> runCatching { file.delete() } }
        } catch (t: Throwable) {
            // best-effort
        }
    }

    // Reads THIS app's own logcat buffer (own-process logs need no READ_LOGS permission), bounded to the
    // last [maxLogcatLines] lines. Best-effort: returns empty on any failure.
    private fun collectLogcatTail(): List<String> {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-v", "threadtime"))
            val lines = process.inputStream.bufferedReader().use { reader -> reader.readLines() }
            runCatching { process.destroy() }
            CrashReport.tail(lines, maxLogcatLines)
        } catch (t: Throwable) {
            emptyList()
        }
    }

    // Native tombstones live in /data/tombstones, which is not app-readable without root. Record the
    // conventional location as an auditable hint rather than attempting a privileged read.
    private fun tombstoneHint(): String = "/data/tombstones (not app-readable without root)"
}
