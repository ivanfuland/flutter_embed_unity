import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_embed_unity/src/bridge_contract.dart';
import 'package:flutter_embed_unity/src/embed_unity_preferences.dart';
import 'package:flutter_embed_unity/src/lifecycle_state_machine.dart';
import 'package:flutter_embed_unity/src/unity_message_listener.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_constants.dart';

/// Registers listeners ([EmbedUnity] widgets) who want to receive messages from Unity.
class UnityMessageListeners {
  UnityMessageListeners._internal({
    bool registerChannelHandler = true,
    EmbedUnityLifecycle? lifecycle,
  }) : _lifecycle = lifecycle ?? EmbedUnityLifecycle.instance {
    if (registerChannelHandler) {
      _channel.setMethodCallHandler(_methodCallHandler);
    }
  }

  static final instance = UnityMessageListeners._internal();

  @visibleForTesting
  factory UnityMessageListeners.createForTest({
    EmbedUnityLifecycle? lifecycle,
  }) {
    return UnityMessageListeners._internal(
      registerChannelHandler: false,
      lifecycle: lifecycle,
    );
  }

  final MethodChannel _channel = const MethodChannel(
    FlutterEmbedConstants.uniqueIdentifier,
  );
  final EmbedUnityLifecycle _lifecycle;
  final List<UnityMessageListener> _listeners = [];
  final Map<String, _PendingBridgeRequest> _pendingRequests = {};

  void addListener(UnityMessageListener listener) {
    _listeners.add(listener);
  }

  void removeListener(UnityMessageListener listener) {
    _listeners.remove(listener);
  }

  Future<dynamic> sendRequest(
    BridgeEnvelope request, {
    required Duration timeout,
    required FutureOr<void> Function(String envelopeJson) dispatch,
  }) {
    if (request.type != BridgeEnvelope.requestType) {
      throw ArgumentError.value(
        request.type,
        'request.type',
        'sendRequest requires a req envelope.',
      );
    }
    if (_pendingRequests.containsKey(request.msgId)) {
      throw StateError('Duplicate BridgeEnvelope msgId: ${request.msgId}');
    }

    final completer = Completer<dynamic>();
    final timer = Timer(timeout, () {
      final pending = _pendingRequests.remove(request.msgId);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          BridgeError(
            BridgeError.timeoutCode,
            'Timed out waiting for Unity response to ${request.method}.',
          ),
        );
      }
    });
    _pendingRequests[request.msgId] = _PendingBridgeRequest(completer, timer);

    Future<void>.sync(() => dispatch(request.encodeString())).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      final pending = _pendingRequests.remove(request.msgId);
      pending?.timer.cancel();
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<void> handleUnityMessage(String data) async {
    final BridgeEnvelope envelope;
    try {
      envelope = BridgeEnvelope.decodeString(data);
    } on BridgeContractDecodeException catch (error) {
      debugPrint('BridgeContract decode error: $error');
      _notifyLegacyListeners(data);
      return;
    }

    switch (envelope.type) {
      case BridgeEnvelope.responseType:
        _lifecycle.markBridgeReady();
        _completePendingResponse(envelope);
        return;
      case BridgeEnvelope.errorType:
        _completePendingError(envelope);
        return;
      case BridgeEnvelope.eventType:
        _lifecycle.markBridgeReady();
        final consumed = _lifecycle.handleEvent(
          envelope.method,
          payload: envelope.payload,
        );
        if (!consumed) {
          _notifyLegacyListeners(_payloadToLegacyString(envelope.payload));
        }
        return;
      case BridgeEnvelope.requestType:
        _notifyLegacyListeners(_payloadToLegacyString(envelope.payload));
        return;
    }
  }

  // Platform code send messages from Unity to Flutter via the method channel
  Future<dynamic> _methodCallHandler(MethodCall call) async {
    if (call.method == FlutterEmbedConstants.methodNameSendToFlutter) {
      final data = call.arguments.toString();
      await handleUnityMessage(data);
    }
  }

  void _completePendingResponse(BridgeEnvelope envelope) {
    final corrId = envelope.corrId;
    if (corrId == null) {
      debugPrint(
        'BridgeContract ignored resp without corrId: ${envelope.msgId}',
      );
      return;
    }
    final pending = _pendingRequests.remove(corrId);
    if (pending == null) {
      debugPrint('BridgeContract ignored resp with unknown corrId: $corrId');
      return;
    }
    pending.timer.cancel();
    if (!pending.completer.isCompleted) {
      pending.completer.complete(envelope.payload);
    }
  }

  void _completePendingError(BridgeEnvelope envelope) {
    final corrId = envelope.corrId;
    if (corrId == null) {
      debugPrint(
        'BridgeContract ignored err without corrId: ${envelope.msgId}',
      );
      return;
    }
    final pending = _pendingRequests.remove(corrId);
    if (pending == null) {
      debugPrint('BridgeContract ignored err with unknown corrId: $corrId');
      return;
    }
    pending.timer.cancel();
    if (!pending.completer.isCompleted) {
      pending.completer.completeError(
        envelope.err ??
            const BridgeError(
              'BRIDGE_ERROR',
              'Unity returned an empty bridge error.',
            ),
      );
    }
  }

  void _notifyLegacyListeners(String data) {
    switch (EmbedUnityPreferences.messageFromUnityListeningBehaviour) {
      case MessageFromUnityListeningBehaviour.allWidgetsReceiveMessages:
        {
          for (var listener in _listeners) {
            listener.onMessageFromUnity(data);
          }
          break;
        }
      case MessageFromUnityListeningBehaviour
          .onlyMostRecentlyCreatedWidgetReceivesMessages:
        {
          if (_listeners.isNotEmpty) {
            _listeners.last.onMessageFromUnity(data);
          }
          break;
        }
    }
  }
}

class _PendingBridgeRequest {
  const _PendingBridgeRequest(this.completer, this.timer);

  final Completer<dynamic> completer;
  final Timer timer;
}

String _payloadToLegacyString(Object? payload) {
  if (payload == null) {
    return '';
  }
  if (payload is String) {
    return payload;
  }
  return jsonEncode(payload);
}
