package com.learntoflutter.flutter_embed_unity_android.messaging

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * [portola] H2/H3 — JVM unit tests for the defensive sendToUnity argument parsing + readiness gate.
 *
 * These run on a plain JVM (no Robolectric / Unity / Flutter classes needed) because the logic under
 * test, [SendToUnityArguments.resolve], is dependency-free. Run with `./gradlew testDebugUnitTest`
 * from `example/android/` (the standard Flutter plugin unit-test path).
 */
internal class SendToUnityArgumentsTest {

    @Test
    fun nullArguments_areInvalid() {
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(null, unityLoaded = true))
    }

    @Test
    fun nonListArguments_areInvalid() {
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve("not a list", unityLoaded = true))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(42, unityLoaded = true))
    }

    @Test
    fun wrongArgumentCount_isInvalid() {
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("go", "method"), unityLoaded = true))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("go", "method", "data", "extra"), unityLoaded = true))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(emptyList<Any?>(), unityLoaded = true))
    }

    @Test
    fun nonStringArguments_areInvalid() {
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("go", 1, "data"), unityLoaded = true))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("go", "method", null), unityLoaded = true))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf(listOf("nested"), "method", "data"), unityLoaded = true))
    }

    @Test
    fun emptyGameObjectOrMethodName_isInvalid() {
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("", "method", "data"), unityLoaded = true))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("go", "", "data"), unityLoaded = true))
    }

    @Test
    fun validArgumentsButUnityNotLoaded_isUnityNotLoaded() {
        assertEquals(SendToUnityOutcome.UnityNotLoaded, SendToUnityArguments.resolve(listOf("go", "method", "data"), unityLoaded = false))
    }

    @Test
    fun invalidArgumentsTakePrecedenceOverNotLoaded() {
        // Malformed input must report INVALID_ARGUMENTS even when Unity is not loaded (iOS parity).
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(null, unityLoaded = false))
        assertEquals(SendToUnityOutcome.InvalidArguments, SendToUnityArguments.resolve(listOf("go", "method"), unityLoaded = false))
    }

    @Test
    fun happyPath_returnsSend_withByteIdenticalRawData() {
        // `data` may be an H1-envelope-shaped string, but the native layer must pass it through raw.
        val data = "{\"v\":1,\"type\":\"req\",\"method\":\"ping\"}"
        val outcome = SendToUnityArguments.resolve(listOf("GameController", "OnFlutterMessage", data), unityLoaded = true)
        assertTrue(outcome is SendToUnityOutcome.Send)
        outcome as SendToUnityOutcome.Send
        assertEquals("GameController", outcome.gameObjectName)
        assertEquals("OnFlutterMessage", outcome.methodName)
        assertEquals(data, outcome.data)
    }

    @Test
    fun emptyData_isAllowed() {
        // Only gameObjectName + methodName must be non-empty; empty data is a valid raw payload.
        val outcome = SendToUnityArguments.resolve(listOf("go", "method", ""), unityLoaded = true)
        assertTrue(outcome is SendToUnityOutcome.Send)
        assertEquals("", (outcome as SendToUnityOutcome.Send).data)
    }
}
