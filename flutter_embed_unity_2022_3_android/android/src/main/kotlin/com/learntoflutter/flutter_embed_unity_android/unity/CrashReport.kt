package com.learntoflutter.flutter_embed_unity_android.unity

// [portola] H10 — pure, dependency-free crash-reporting core (JVM-testable; no Android / Flutter / Unity
// imports). The Android wiring (file writing, logcat capture, handler install) lives in CrashCollector.kt.

internal interface CrashSink {
    fun record(thread: Thread, throwable: Throwable)
}

// UncaughtExceptionHandler that runs a best-effort [sink], then ALWAYS hands control back to the
// previously-installed default handler so the system crash flow (on Android: the RuntimeInit
// KillApplicationHandler that kills the process) is preserved. It never swallows the crash and never
// throws a secondary exception.
internal class CrashCollectorHandler(
    private val previous: Thread.UncaughtExceptionHandler?,
    private val sink: CrashSink,
) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        // 1) best-effort collection — a failure here must not cause a secondary crash or block the chain.
        try {
            sink.record(thread, throwable)
        } catch (secondary: Throwable) {
            // swallow the secondary failure only; the original crash is still propagated below.
        }

        // 2) always hand back to the previous/default handler so the crash is NOT swallowed.
        val prev = previous
        if (prev != null) {
            prev.uncaughtException(thread, throwable)
        } else {
            // No previous handler — effectively never on Android (RuntimeInit installs one). Surface to
            // System.err as the last-resort default rather than swallowing. (Re-throwing from inside an
            // uncaughtException handler would be ignored by the VM, i.e. silently swallowed.)
            throwable.printStackTrace()
        }
    }
}

internal object CrashReport {
    const val fileNamePrefix = "crash-"
    const val fileNameSuffix = ".txt"

    // Deterministic, lexically-sortable crash file name.
    fun fileName(timestampMillis: Long): String = "$fileNamePrefix$timestampMillis$fileNameSuffix"

    // Keep only the last [maxLines] lines (the tail), bounding logcat size.
    fun tail(lines: List<String>, maxLines: Int): List<String> {
        if (maxLines <= 0) return emptyList()
        if (lines.size <= maxLines) return lines
        return lines.subList(lines.size - maxLines, lines.size)
    }

    // Build an auditable crash record (pure). [logcatTail] / [tombstoneInfo] are optional best-effort
    // context supplied by the Android sink.
    fun format(
        threadName: String,
        throwable: Throwable,
        timestampMillis: Long,
        logcatTail: List<String> = emptyList(),
        tombstoneInfo: String? = null,
    ): String {
        val sb = StringBuilder()
        sb.append("flutter_embed_unity crash report\n")
        sb.append("timestampMillis: ").append(timestampMillis).append('\n')
        sb.append("thread: ").append(threadName).append('\n')
        sb.append("exception: ").append(throwable.javaClass.name)
        val message = throwable.message
        if (message != null) {
            sb.append(": ").append(message)
        }
        sb.append('\n')
        sb.append("stackTrace:\n").append(throwable.stackTraceToString())
        if (tombstoneInfo != null) {
            sb.append("tombstone: ").append(tombstoneInfo).append('\n')
        }
        if (logcatTail.isNotEmpty()) {
            sb.append("logcatTail (").append(logcatTail.size).append(" lines):\n")
            for (line in logcatTail) {
                sb.append(line).append('\n')
            }
        }
        return sb.toString()
    }
}
