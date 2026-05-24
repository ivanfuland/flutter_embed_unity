import 'package:flutter/services.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_constants.dart';

import 'flutter_embed_unity_platform_interface.dart';

const MethodChannel _channel = MethodChannel(
  FlutterEmbedConstants.uniqueIdentifier,
);

/// An implementation of [FlutterEmbedUnityPlatform] that uses method channels.
class MethodChannelFlutterEmbedUnity extends FlutterEmbedUnityPlatform {
  @override
  Future<void> sendToUnity(
    String gameObjectName,
    String methodName,
    String data,
  ) async {
    await _channel.invokeMethod<void>(
      FlutterEmbedConstants.methodNameSendToUnity,
      [gameObjectName, methodName, data],
    );
  }

  @override
  void pauseUnity() {
    _channel.invokeMethod(FlutterEmbedConstants.methodNamePauseUnity);
  }

  @override
  void resumeUnity() {
    _channel.invokeMethod(FlutterEmbedConstants.methodNameResumeUnity);
  }

  @override
  Future<void> unmountUnity() async {
    await _channel.invokeMethod<void>(
      FlutterEmbedConstants.methodNameUnmountUnity,
    );
  }
}
