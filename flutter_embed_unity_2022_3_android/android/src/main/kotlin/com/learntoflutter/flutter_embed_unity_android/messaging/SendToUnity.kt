package com.learntoflutter.flutter_embed_unity_android.messaging

import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.logTag
import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.methodNamePauseUnity
import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.methodNameResumeUnity
import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.methodNameSendToUnity
import com.learntoflutter.flutter_embed_unity_android.unity.UnityPlayerSingleton
import com.unity3d.player.UnityPlayer
import io.flutter.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SendToUnity : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            methodNameSendToUnity -> handleSendToUnity(call, result)
            methodNamePauseUnity -> handlePauseOrResume(pause = true, result = result)
            methodNameResumeUnity -> handlePauseOrResume(pause = false, result = result)
            else -> {
                // [portola] H7 memory-policy guard: the Android method channel exposes only
                // sendToUnity / pauseUnity / resumeUnity. There is deliberately NO quitApplication /
                // unloadApplication / destroy / memoryTrim handler — any such (or otherwise unknown)
                // method is rejected with notImplemented rather than silently invoking a dangerous
                // Unity teardown API. Memory-trim / unload stays a deferred path this round (no C#
                // MemoryTrim handler added).
                result.notImplemented()
            }
        }
    }

    // [portola] H2/H3 — defensive parsing + explicit result semantics. The legacy upstream code did
    // `(call.arguments as List<*>).filterIsInstance<String>()[0..2]` (crashes on nil / non-list / wrong
    // count / non-string) and NEVER completed the result, so the awaited Dart `sendToUnity` Future hung.
    private fun handleSendToUnity(call: MethodCall, result: MethodChannel.Result) {
        when (val outcome = SendToUnityArguments.resolve(call.arguments, UnityPlayerSingleton.getInstance() != null)) {
            is SendToUnityOutcome.Send -> {
                // M6B compatibility: `data` is forwarded raw / byte-identical. The Android native layer
                // never inspects or requires the H1 envelope (v/type/msgId/corrId) — building the envelope
                // is the Dart sendToUnityRequest path's responsibility.
                UnityPlayer.UnitySendMessage(outcome.gameObjectName, outcome.methodName, outcome.data)
                result.success(null)
            }
            SendToUnityOutcome.InvalidArguments -> {
                Log.w(logTag, "sendToUnity called with invalid arguments")
                result.error(
                    errorCodeInvalidArguments,
                    "sendToUnity expects [gameObjectName, methodName, data] string arguments " +
                        "with non-empty gameObjectName and methodName.",
                    null)
            }
            SendToUnityOutcome.UnityNotLoaded -> {
                Log.w(logTag, "Dropped message to Unity: Unity is not loaded yet")
                result.error(errorCodeUnityNotLoaded, "Unity is not loaded yet.", null)
            }
        }
    }

    // Pause/resume are fire-and-forget on the Dart side, but completing them explicitly closes the
    // same "silently non-completing future" gap (H2) and matches the iOS handler's behaviour.
    private fun handlePauseOrResume(pause: Boolean, result: MethodChannel.Result) {
        val instance = UnityPlayerSingleton.getInstance()
        if (instance == null) {
            Log.w(logTag, "Didn't ${if (pause) "pause" else "resume"} Unity: Unity is not loaded yet")
            result.error(errorCodeUnityNotLoaded, "Unity is not loaded yet.", null)
            return
        }
        if (pause) {
            instance.pause()
        } else {
            instance.resume()
        }
        result.success(null)
    }

    companion object {
        const val errorCodeInvalidArguments = "INVALID_ARGUMENTS"
        const val errorCodeUnityNotLoaded = "UNITY_NOT_LOADED"
    }
}
