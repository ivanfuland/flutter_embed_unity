package com.learntoflutter.flutter_embed_unity_android.unity

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * [portola] H10 — JVM unit tests for the pure crash-reporting core. Runs on a plain JVM (no Android /
 * Flutter / Unity), covering crash record formatting, file naming, logcat-tail bounding, and the
 * UncaughtExceptionHandler chaining / best-effort guarantees.
 */
internal class CrashReportTest {

    @Test
    fun fileName_isDeterministicAndSortable() {
        assertEquals("crash-1716265200000.txt", CrashReport.fileName(1716265200000L))
    }

    @Test
    fun tail_keepsLastNLines() {
        val lines = (1..10).map { "line$it" }
        assertEquals(listOf("line8", "line9", "line10"), CrashReport.tail(lines, 3))
    }

    @Test
    fun tail_returnsAllWhenUnderLimit() {
        val lines = listOf("a", "b")
        assertEquals(lines, CrashReport.tail(lines, 5))
    }

    @Test
    fun tail_nonPositiveLimit_isEmpty() {
        assertEquals(emptyList(), CrashReport.tail(listOf("a", "b"), 0))
        assertEquals(emptyList(), CrashReport.tail(listOf("a", "b"), -1))
    }

    @Test
    fun format_containsCoreFields() {
        val throwable = IllegalStateException("boom")
        val out = CrashReport.format(
            threadName = "main",
            throwable = throwable,
            timestampMillis = 123L,
            logcatTail = listOf("L1", "L2"),
            tombstoneInfo = "/data/tombstones",
        )
        assertTrue(out.contains("timestampMillis: 123"))
        assertTrue(out.contains("thread: main"))
        assertTrue(out.contains("java.lang.IllegalStateException: boom"))
        assertTrue(out.contains("stackTrace:"))
        assertTrue(out.contains("logcatTail (2 lines):"))
        assertTrue(out.contains("tombstone: /data/tombstones"))
    }

    @Test
    fun format_omitsLogcatAndTombstoneWhenAbsent() {
        val out = CrashReport.format("worker", RuntimeException(), 1L)
        assertFalse(out.contains("logcatTail"))
        assertFalse(out.contains("tombstone:"))
    }

    @Test
    fun handler_recordsThenChainsToPrevious() {
        val events = mutableListOf<String>()
        val previous = Thread.UncaughtExceptionHandler { _, _ -> events.add("previous") }
        val sink = object : CrashSink {
            override fun record(thread: Thread, throwable: Throwable) {
                events.add("sink")
            }
        }
        CrashCollectorHandler(previous, sink)
            .uncaughtException(Thread.currentThread(), RuntimeException("x"))
        // Sink runs first (best-effort collection), then the crash is chained to the previous handler.
        assertEquals(listOf("sink", "previous"), events)
    }

    @Test
    fun handler_sinkFailure_doesNotBreakChain() {
        val events = mutableListOf<String>()
        val previous = Thread.UncaughtExceptionHandler { _, _ -> events.add("previous") }
        val sink = object : CrashSink {
            override fun record(thread: Thread, throwable: Throwable) {
                throw RuntimeException("sink failure")
            }
        }
        CrashCollectorHandler(previous, sink)
            .uncaughtException(Thread.currentThread(), RuntimeException("x"))
        // The sink failure is swallowed but the previous handler is still invoked (crash not lost).
        assertEquals(listOf("previous"), events)
    }

    @Test
    fun handler_nullPrevious_doesNotThrowAndStillRecords() {
        var recorded = false
        val sink = object : CrashSink {
            override fun record(thread: Thread, throwable: Throwable) {
                recorded = true
            }
        }
        // Must not throw (prints to System.err as the last-resort default when there is no previous).
        CrashCollectorHandler(null, sink)
            .uncaughtException(Thread.currentThread(), RuntimeException("x"))
        assertTrue(recorded)
    }
}
