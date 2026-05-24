import 'package:flutter/services.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_unity_platform_interface.dart';

import 'src/bridge_contract.dart';
import 'src/unity_message_listeners.dart';

export 'src/bridge_contract.dart'
    show BridgeEnvelope, BridgeError, BridgeContractDecodeException;
export 'src/embed_unity.dart' show EmbedUnity;
export 'src/lifecycle_state_machine.dart'
    show EmbedUnityLifecycle, EmbedUnityLifecycleEvent, EmbedUnityState;
export 'src/embed_unity_preferences.dart'
    show EmbedUnityPreferences, MessageFromUnityListeningBehaviour;
export 'package:flutter_embed_unity/flutter_embed_unity.dart'
    show sendToUnity, sendToUnityRequest, pauseUnity, resumeUnity;

FlutterEmbedUnityPlatform get _platform => FlutterEmbedUnityPlatform.instance;

/// Send [data] to a public MonoBehaviour method named [methodName] attached to a
/// Unity game object named [gameObjectName] in the active scene.
///
/// The Unity method must be public and accept a single [String] parameter.
Future<void> sendToUnity(
  String gameObjectName,
  String methodName,
  String data,
) {
  return _sendDataToUnity(gameObjectName, methodName, data);
}

/// Send a BridgeContract request envelope to Unity and wait for a matching
/// `resp` or `err` envelope whose `corrId` equals the request `msgId`.
///
/// This keeps the existing native string channel intact while adding Dart-side
/// request/response semantics for M7 H1.
Future<dynamic> sendToUnityRequest(
  String gameObjectName,
  String methodName, {
  Object? payload,
  Duration timeout = const Duration(seconds: 5),
  String? traceId,
}) {
  final request = BridgeEnvelope.request(
    method: methodName,
    payload: payload,
    traceId: traceId,
  );

  return UnityMessageListeners.instance.sendRequest(
    request,
    timeout: timeout,
    dispatch: (envelopeJson) {
      return _sendDataToUnity(gameObjectName, methodName, envelopeJson);
    },
  );
}

Future<void> _sendDataToUnity(
  String gameObjectName,
  String methodName,
  String data,
) async {
  try {
    await _platform.sendToUnity(gameObjectName, methodName, data);
  } on PlatformException catch (error) {
    throw BridgeError(
      error.code,
      error.message ?? 'sendToUnity failed.',
      details: error.details,
    );
  }
}

/// Pause time in Unity.
///
/// Unity will remain loaded in memory and still be able to accept messages.
void pauseUnity() {
  _platform.pauseUnity();
}

/// Resume time in Unity.
void resumeUnity() {
  _platform.resumeUnity();
}
