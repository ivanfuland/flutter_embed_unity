import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/src/lifecycle_state_machine.dart';
import 'package:flutter_embed_unity/src/unity_message_listener.dart';
import 'package:flutter_embed_unity/src/unity_message_listeners.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_constants.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_unity_platform_interface.dart';

/// Embed Unity into your Flutter app and listen for messages from your Unity scripts.
///
/// Unity will be rendered within the bounds of the widget.
/// Only 1 instance of the widget should be shown on a screen.
class EmbedUnity extends StatefulWidget {
  /// Listen to messages sent from Unity via `SendToFlutter.cs`.
  final Function(String)? onMessageFromUnity;

  const EmbedUnity({this.onMessageFromUnity, super.key});

  static const singleInstanceErrorMessage = 'Only one EmbedUnity allowed in P0';

  static int _activeInstanceCount = 0;

  @visibleForTesting
  static void debugResetSingleInstanceGuard() {
    _activeInstanceCount = 0;
  }

  static ValueListenable<EmbedUnityState> get lifecycleState =>
      EmbedUnityLifecycle.instance.state;

  static Future<void> waitForReady({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return EmbedUnityLifecycle.instance.waitForReady(timeout: timeout);
  }

  @override
  State<EmbedUnity> createState() => _EmbedUnityState();
}

class _EmbedUnityState extends State<EmbedUnity>
    implements UnityMessageListener {
  bool _guardAcquired = false;
  bool _listenerRegistered = false;

  @override
  void initState() {
    super.initState();
    if (EmbedUnity._activeInstanceCount > 0) {
      throw StateError(EmbedUnity.singleInstanceErrorMessage);
    }
    EmbedUnity._activeInstanceCount += 1;
    _guardAcquired = true;
    UnityMessageListeners.instance.addListener(this);
    _listenerRegistered = true;
  }

  @override
  void dispose() {
    if (_listenerRegistered) {
      UnityMessageListeners.instance.removeListener(this);
      _listenerRegistered = false;
    }
    if (_guardAcquired) {
      EmbedUnity._activeInstanceCount -= 1;
      _guardAcquired = false;
    }
    EmbedUnityLifecycle.instance.markViewAttached(false);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(_unmountUnityBestEffort());
    }
    super.dispose();
  }

  Future<void> _unmountUnityBestEffort() async {
    try {
      await FlutterEmbedUnityPlatform.instance.unmountUnity();
    } catch (error) {
      debugPrint('FlutterEmbed: unmountUnity failed during dispose: $error');
    }
  }

  @override
  void onMessageFromUnity(String data) {
    widget.onMessageFromUnity?.call(data);
  }

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: FlutterEmbedConstants.uniqueIdentifier,
          onPlatformViewCreated: (int id) {
            debugPrint('FlutterEmbed: onPlatformViewCreated($id)');
            EmbedUnityLifecycle.instance.markViewAttached(true);
          },
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: FlutterEmbedConstants.uniqueIdentifier,
          onPlatformViewCreated: (int id) {
            debugPrint('FlutterEmbed: onPlatformViewCreated($id)');
            EmbedUnityLifecycle.instance.markViewAttached(true);
          },
        );
      default:
        throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
    }
  }
}
