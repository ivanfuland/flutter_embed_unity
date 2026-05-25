package com.learntoflutter.flutter_embed_unity_android.messaging

import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.logTag
import io.flutter.Log
import java.util.UUID

// [portola] H6 — emits Android lifecycle events to Dart as H1 `evt` envelopes, matching the iOS
// LifecycleEventEmitter.swift so the Dart EmbedUnityLifecycle state machine consumes them identically.
//
// Dart's EmbedUnityLifecycle.handleEvent only recognises method == runtimeLoaded | firstFrameSeen |
// foregroundActive; any other method falls through to legacy message listeners. So ONLY these three
// methods are emitted (no invented event shapes). `viewAttached` is owned by the Dart EmbedUnity widget
// and is deliberately not emitted here.
//
// The envelope JSON is produced by a small, hand-rolled serializer (buildEventEnvelopeJson) rather than
// org.json.JSONObject, because android.jar ships org.json as a stub that throws under plain JVM unit
// tests — this keeps the builder unit-testable without Robolectric. All values are controlled (fixed
// method names, a UUID msgId, bool payloads) and strings are still escaped defensively.
internal object LifecycleEventEmitter {
    const val methodRuntimeLoaded = "runtimeLoaded"
    const val methodFirstFrameSeen = "firstFrameSeen"
    const val methodForegroundActive = "foregroundActive"

    // Unity runtime has been loaded into memory for the first time.
    fun runtimeLoaded() = emit(methodRuntimeLoaded, null)

    // Closest reliable Android proxy for "Unity rendered a frame" (no true first-frame callback exists).
    fun firstFrameSeen() = emit(methodFirstFrameSeen, null)

    // App/activity entered (true) or left (false) the foreground.
    fun foregroundActive(active: Boolean) = emit(methodForegroundActive, mapOf("active" to active))

    private fun emit(method: String, payload: Map<String, Any?>?) {
        try {
            val json = buildEventEnvelopeJson(
                method = method,
                payload = payload,
                ts = System.currentTimeMillis(),
                msgId = "android-${UUID.randomUUID()}",
            )
            // SendToFlutter posts on the main thread and is null-channel-safe (skip + log if the channel
            // is not registered). We do NOT cache and replay — matching iOS. An event emitted before the
            // channel is ready is dropped; readiness stays re-derivable (foregroundActive re-fires on the
            // next resume/pause, bridgeReady is set by any resp/evt, firstFrameSeen re-fires on the next
            // window-visible transition). In the normal flow the channel is registered in
            // onAttachedToActivity, before Unity is created, so these emits land.
            SendToFlutter.sendToFlutter(json)
        } catch (t: Throwable) {
            // Best-effort: a lifecycle emit must never crash Unity / Android lifecycle code.
            Log.w(logTag, "Failed to emit lifecycle event $method: ${t.message}")
        }
    }

    // Pure, dependency-free H1 `evt` envelope builder (JVM-testable). The required fields match
    // flutter_embed_unity bridge_contract.dart decodeJson: v(int)=1, type="evt", msgId(string),
    // method(string), ts(int). payload is optional. ts is written as an integer literal (no decimal)
    // so the Dart `_required<int>(json, 'ts')` decode succeeds.
    internal fun buildEventEnvelopeJson(
        method: String,
        payload: Map<String, Any?>?,
        ts: Long,
        msgId: String,
    ): String {
        val sb = StringBuilder()
        sb.append("{")
        sb.append("\"v\":1,")
        sb.append("\"type\":\"evt\",")
        sb.append("\"msgId\":").append(jsonString(msgId)).append(",")
        sb.append("\"method\":").append(jsonString(method)).append(",")
        sb.append("\"ts\":").append(ts)
        if (payload != null) {
            sb.append(",\"payload\":").append(jsonObject(payload))
        }
        sb.append("}")
        return sb.toString()
    }

    private fun jsonObject(map: Map<String, Any?>): String {
        val sb = StringBuilder("{")
        var first = true
        for ((key, value) in map) {
            if (!first) {
                sb.append(",")
            }
            first = false
            sb.append(jsonString(key)).append(":").append(jsonValue(value))
        }
        sb.append("}")
        return sb.toString()
    }

    private fun jsonValue(value: Any?): String = when (value) {
        null -> "null"
        is Boolean -> value.toString()
        is Int, is Long -> value.toString()
        is Map<*, *> -> jsonObject(value.entries.associate { (k, v) -> k.toString() to v })
        is String -> jsonString(value)
        else -> jsonString(value.toString())
    }

    private fun jsonString(value: String): String {
        val sb = StringBuilder("\"")
        for (c in value) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> sb.append(c)
            }
        }
        sb.append("\"")
        return sb.toString()
    }
}
