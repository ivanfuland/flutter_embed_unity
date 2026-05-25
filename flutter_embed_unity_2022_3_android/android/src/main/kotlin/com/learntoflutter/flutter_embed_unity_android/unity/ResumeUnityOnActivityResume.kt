package com.learntoflutter.flutter_embed_unity_android.unity

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.learntoflutter.flutter_embed_unity_android.constants.FlutterEmbedConstants.Companion.logTag
import com.learntoflutter.flutter_embed_unity_android.messaging.LifecycleEventEmitter
import io.flutter.Log


// Sometimes (not always) when the Activity is resumed, Unity appears to be frozen.
// There must be something internal in UnityPlayer which does this?
// So, add a lifecycle observer so we can resume Unity.
//
// [portola] H6 — this activity-lifecycle observer is also the foreground signal: it emits
// foregroundActive(true) on ON_RESUME and foregroundActive(false) on ON_PAUSE, matching the iOS
// foregroundActive(true/false) emits from view appear/disappear.
class ResumeUnityOnActivityResume : LifecycleEventObserver {
    override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
        //Log.d(logTag, "Detected lifecycle change $event")

        when (event) {
            Lifecycle.Event.ON_RESUME -> {
                Log.d(logTag, "Activity resumed, resuming Unity")
                // For some reason, we need to pause first, and then resume. Not sure why.
                UnityPlayerSingleton.getInstance()?.pause()
                UnityPlayerSingleton.getInstance()?.resume()
                LifecycleEventEmitter.foregroundActive(true)
            }
            Lifecycle.Event.ON_PAUSE -> {
                LifecycleEventEmitter.foregroundActive(false)
            }
            else -> {
                // Other lifecycle events are not part of the H6 foreground signal.
            }
        }
    }
}
