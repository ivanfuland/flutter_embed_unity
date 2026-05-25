package com.learntoflutter.flutter_embed_unity_android.messaging

// [portola] H2/H3 — pure, dependency-free resolution of `sendToUnity` MethodChannel arguments plus
// the Unity-loaded readiness gate. Kept free of Flutter / Unity / Android imports so the defensive
// parsing can be unit-tested on a plain JVM (the existing example test harness needs no Robolectric
// for this). The thin SendToUnity handler turns these outcomes into result.success/error + the actual
// UnityPlayer call.
//
// Behaviour mirrors the already-hardened iOS SendToUnity.swift for cross-platform parity:
// arguments must be a list of exactly three Strings; gameObjectName + methodName must be non-empty;
// `data` may be any String (including empty) and is forwarded raw — no H1 envelope is required or
// inspected on the native side (M6B byte-identical passthrough).

internal sealed class SendToUnityOutcome {
    data class Send(
        val gameObjectName: String,
        val methodName: String,
        val data: String,
    ) : SendToUnityOutcome()

    object InvalidArguments : SendToUnityOutcome()

    object UnityNotLoaded : SendToUnityOutcome()
}

internal object SendToUnityArguments {
    // Validates arguments FIRST (so malformed input is INVALID_ARGUMENTS regardless of Unity state,
    // matching iOS ordering), then checks readiness. `data` is returned untouched.
    fun resolve(arguments: Any?, unityLoaded: Boolean): SendToUnityOutcome {
        val values = arguments as? List<*> ?: return SendToUnityOutcome.InvalidArguments
        if (values.size != 3) {
            return SendToUnityOutcome.InvalidArguments
        }
        val gameObjectName = values[0] as? String ?: return SendToUnityOutcome.InvalidArguments
        val methodName = values[1] as? String ?: return SendToUnityOutcome.InvalidArguments
        val data = values[2] as? String ?: return SendToUnityOutcome.InvalidArguments
        if (gameObjectName.isEmpty() || methodName.isEmpty()) {
            return SendToUnityOutcome.InvalidArguments
        }
        if (!unityLoaded) {
            return SendToUnityOutcome.UnityNotLoaded
        }
        return SendToUnityOutcome.Send(gameObjectName, methodName, data)
    }
}
