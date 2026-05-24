import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:flutter_embed_unity/src/unity_message_listeners.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_unity_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BridgeEnvelope codec', () {
    test('round-trips req resp evt and err envelopes', () {
      final envelopes = <BridgeEnvelope>[
        BridgeEnvelope.request(
          msgId: 'req-1',
          method: 'loadScene',
          payload: {'scene': 'Mini'},
          ts: 1,
          traceId: 'trace-a',
        ),
        BridgeEnvelope.response(
          msgId: 'resp-1',
          corrId: 'req-1',
          method: 'loadScene',
          payload: {'ok': true},
          ts: 2,
          traceId: 'trace-a',
        ),
        BridgeEnvelope.event(
          msgId: 'evt-1',
          method: 'firstFrame',
          payload: {'frame': 1},
          ts: 3,
        ),
        BridgeEnvelope.error(
          msgId: 'err-1',
          corrId: 'req-2',
          method: 'loadScene',
          err: const BridgeError('UNITY_FAIL', 'Unity failed'),
          ts: 4,
        ),
      ];

      for (final envelope in envelopes) {
        expect(BridgeEnvelope.decodeString(envelope.encodeString()), envelope);
      }
    });

    test('throws a decode error for bad JSON', () {
      expect(
        () => BridgeEnvelope.decodeString('{not json'),
        throwsA(isA<BridgeContractDecodeException>()),
      );
    });

    test('throws a decode error for missing required fields', () {
      expect(
        () => BridgeEnvelope.decodeJson({'v': 1, 'type': 'req'}),
        throwsA(isA<BridgeContractDecodeException>()),
      );
    });
  });

  group('corrId router', () {
    late UnityMessageListeners listeners;

    setUp(() {
      listeners = UnityMessageListeners.createForTest();
    });

    test('completes a pending request with response payload', () async {
      final future = listeners.sendRequest(
        BridgeEnvelope.request(
          msgId: 'req-1',
          method: 'loadScene',
          payload: {'scene': 'Mini'},
          ts: 1,
        ),
        timeout: const Duration(seconds: 1),
        dispatch: (_) {},
      );

      await listeners.handleUnityMessage(
        BridgeEnvelope.response(
          msgId: 'resp-1',
          corrId: 'req-1',
          method: 'loadScene',
          payload: {'ok': true},
          ts: 2,
        ).encodeString(),
      );

      await expectLater(future, completion({'ok': true}));
    });

    test('times out a pending request with BridgeError', () async {
      final future = listeners.sendRequest(
        BridgeEnvelope.request(
          msgId: 'req-timeout',
          method: 'loadScene',
          payload: const {},
          ts: 1,
        ),
        timeout: const Duration(milliseconds: 1),
        dispatch: (_) {},
      );

      await expectLater(
        future,
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            'code',
            BridgeError.timeoutCode,
          ),
        ),
      );
    });

    test('completes a pending request with BridgeError on err reply', () async {
      final future = listeners.sendRequest(
        BridgeEnvelope.request(
          msgId: 'req-error',
          method: 'loadScene',
          payload: const {},
          ts: 1,
        ),
        timeout: const Duration(seconds: 1),
        dispatch: (_) {},
      );

      final expectation = expectLater(
        future,
        throwsA(
          isA<BridgeError>()
              .having((error) => error.code, 'code', 'UNITY_FAIL')
              .having((error) => error.message, 'message', 'Unity failed'),
        ),
      );

      await listeners.handleUnityMessage(
        BridgeEnvelope.error(
          msgId: 'err-1',
          corrId: 'req-error',
          method: 'loadScene',
          err: const BridgeError('UNITY_FAIL', 'Unity failed'),
          ts: 2,
        ).encodeString(),
      );

      await expectation;
    });

    test('ignores an unknown corrId without crashing', () async {
      await listeners.handleUnityMessage(
        BridgeEnvelope.response(
          msgId: 'resp-unknown',
          corrId: 'missing',
          method: 'loadScene',
          payload: {'ok': true},
          ts: 1,
        ).encodeString(),
      );
    });
  });

  group('public Future API', () {
    setUp(() {
      FlutterEmbedUnityPlatform.instance = _FakePlatform();
    });

    test(
      'sendToUnityRequest dispatches envelope JSON over legacy channel',
      () async {
        final fakePlatform = _FakePlatform();
        FlutterEmbedUnityPlatform.instance = fakePlatform;

        unawaited(
          Future<void>(() async {
            while (fakePlatform.sentData == null) {
              await Future<void>.delayed(Duration.zero);
            }
            final request = BridgeEnvelope.decodeString(fakePlatform.sentData!);
            await UnityMessageListeners.instance.handleUnityMessage(
              BridgeEnvelope.response(
                msgId: 'resp-1',
                corrId: request.msgId,
                method: request.method,
                payload: {'ok': true},
                ts: request.ts + 1,
              ).encodeString(),
            );
          }),
        );

        final result = await sendToUnityRequest(
          'Bridge',
          'LoadScene',
          payload: {'scene': 'Mini'},
          timeout: const Duration(seconds: 1),
        );

        expect(result, {'ok': true});
        expect(fakePlatform.gameObjectName, 'Bridge');
        expect(fakePlatform.methodName, 'LoadScene');
        expect(jsonDecode(fakePlatform.sentData!)['type'], 'req');
      },
    );

    test(
      'sendToUnity awaits native success and preserves raw legacy data',
      () async {
        final fakePlatform = _FakePlatform();
        FlutterEmbedUnityPlatform.instance = fakePlatform;
        const rawBridgeContractJson = '{"protocolVersion":"0.1.0"}';

        await sendToUnity(
          'GameBridge',
          'OnNativeMessage',
          rawBridgeContractJson,
        );

        expect(fakePlatform.gameObjectName, 'GameBridge');
        expect(fakePlatform.methodName, 'OnNativeMessage');
        expect(fakePlatform.sentData, rawBridgeContractJson);
      },
    );

    test('sendToUnity maps PlatformException to BridgeError', () async {
      FlutterEmbedUnityPlatform.instance = _ThrowingPlatform();

      await expectLater(
        sendToUnity('Bridge', 'LoadScene', 'Mini'),
        throwsA(
          isA<BridgeError>()
              .having((error) => error.code, 'code', 'INVALID_ENVELOPE')
              .having((error) => error.message, 'message', 'Bad envelope')
              .having((error) => error.details, 'details', {'field': 'v'}),
        ),
      );
    });
  });
}

class _FakePlatform extends FlutterEmbedUnityPlatform {
  String? gameObjectName;
  String? methodName;
  String? sentData;

  @override
  Future<void> sendToUnity(
    String gameObjectName,
    String methodName,
    String data,
  ) async {
    this.gameObjectName = gameObjectName;
    this.methodName = methodName;
    sentData = data;
  }
}

class _ThrowingPlatform extends FlutterEmbedUnityPlatform {
  @override
  Future<void> sendToUnity(
    String gameObjectName,
    String methodName,
    String data,
  ) async {
    throw PlatformException(
      code: 'INVALID_ENVELOPE',
      message: 'Bad envelope',
      details: {'field': 'v'},
    );
  }
}
