package com.learntoflutter.flutter_embed_unity_android.messaging

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * [portola] H6 — JVM unit tests for the lifecycle H1 `evt` envelope builder.
 *
 * Runs on a plain JVM (no Robolectric / Unity / Flutter) because
 * [LifecycleEventEmitter.buildEventEnvelopeJson] is dependency-free. The asserted field set matches
 * what flutter_embed_unity `bridge_contract.dart` `decodeJson` requires (v:int=1, type="evt",
 * msgId:string, method:string, ts:int) and what the iOS LifecycleEventEmitter produces.
 */
internal class LifecycleEventEmitterTest {

    @Test
    fun runtimeLoaded_isExactEnvelopeWithoutPayload() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson(
            method = LifecycleEventEmitter.methodRuntimeLoaded,
            payload = null,
            ts = 1716265200000L,
            msgId = "android-abc",
        )
        assertEquals(
            "{\"v\":1,\"type\":\"evt\",\"msgId\":\"android-abc\",\"method\":\"runtimeLoaded\",\"ts\":1716265200000}",
            json,
        )
    }

    @Test
    fun firstFrameSeen_hasNoPayload() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson(
            method = LifecycleEventEmitter.methodFirstFrameSeen,
            payload = null,
            ts = 1L,
            msgId = "android-x",
        )
        assertTrue(json.contains("\"method\":\"firstFrameSeen\""))
        assertFalse(json.contains("payload"))
    }

    @Test
    fun foregroundActive_true_carriesActivePayload() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson(
            method = LifecycleEventEmitter.methodForegroundActive,
            payload = mapOf("active" to true),
            ts = 2L,
            msgId = "android-y",
        )
        assertEquals(
            "{\"v\":1,\"type\":\"evt\",\"msgId\":\"android-y\",\"method\":\"foregroundActive\",\"ts\":2,\"payload\":{\"active\":true}}",
            json,
        )
    }

    @Test
    fun foregroundActive_false_carriesActivePayload() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson(
            method = LifecycleEventEmitter.methodForegroundActive,
            payload = mapOf("active" to false),
            ts = 3L,
            msgId = "android-z",
        )
        assertTrue(json.contains("\"payload\":{\"active\":false}"))
    }

    @Test
    fun version_isIntegerOne() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson("runtimeLoaded", null, 1L, "id")
        assertTrue(json.contains("\"v\":1"))
        assertTrue(json.contains("\"type\":\"evt\""))
    }

    @Test
    fun timestamp_isIntegerLiteralNotFloat() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson("runtimeLoaded", null, 1716265200000L, "id")
        assertTrue(json.contains("\"ts\":1716265200000"))
        assertFalse(json.contains(".0"))
    }

    @Test
    fun strings_areEscapedDefensively() {
        val json = LifecycleEventEmitter.buildEventEnvelopeJson(
            method = "m",
            payload = mapOf("k" to "a\"b\\c"),
            ts = 1L,
            msgId = "id\"x",
        )
        assertTrue(json.contains("\"msgId\":\"id\\\"x\""))
        assertTrue(json.contains("\"k\":\"a\\\"b\\\\c\""))
    }
}
