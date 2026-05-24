import 'dart:async';

import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:flutter_embed_unity/src/unity_message_listener.dart';
import 'package:flutter_embed_unity/src/unity_message_listeners.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EmbedUnityLifecycle lifecycle;

  setUp(() {
    lifecycle = EmbedUnityLifecycle.createForTest();
  });

  test('state transitions preserve order and expose aggregate readiness', () {
    final observed = <EmbedUnityState>[];
    lifecycle.state.addListener(() {
      observed.add(lifecycle.state.value);
    });

    lifecycle.markRuntimeLoaded();
    lifecycle.markViewAttached(true);
    lifecycle.markFirstFrameSeen();
    lifecycle.markBridgeReady();
    lifecycle.markForegroundActive(true);

    expect(observed.map((state) => state.runtimeLoaded), [
      true,
      true,
      true,
      true,
      true,
    ]);
    expect(observed.map((state) => state.isReady), [
      false,
      false,
      false,
      true,
      true,
    ]);
    expect(lifecycle.state.value.foregroundActive, isTrue);
  });

  test(
    'isReady only flips after viewAttached bridgeReady and firstFrameSeen',
    () {
      lifecycle.markRuntimeLoaded();
      lifecycle.markForegroundActive(true);
      lifecycle.markViewAttached(true);
      lifecycle.markBridgeReady();

      expect(lifecycle.state.value.isReady, isFalse);

      lifecycle.markFirstFrameSeen();

      expect(lifecycle.state.value.isReady, isTrue);
    },
  );

  test('detaching resets current-view readiness without clearing bridge', () {
    lifecycle.markRuntimeLoaded();
    lifecycle.markViewAttached(true);
    lifecycle.markBridgeReady();
    lifecycle.markFirstFrameSeen();
    lifecycle.markForegroundActive(true);

    expect(lifecycle.state.value.isReady, isTrue);

    lifecycle.markViewAttached(false);

    expect(lifecycle.state.value.isReady, isFalse);
    expect(lifecycle.state.value.firstFrameSeen, isFalse);
    expect(lifecycle.state.value.foregroundActive, isFalse);
    expect(lifecycle.state.value.bridgeReady, isTrue);
    expect(lifecycle.state.value.runtimeLoaded, isTrue);

    lifecycle.markViewAttached(true);

    expect(lifecycle.state.value.isReady, isFalse);
    expect(lifecycle.state.value.firstFrameSeen, isFalse);

    lifecycle.markFirstFrameSeen();

    expect(lifecycle.state.value.isReady, isTrue);
  });

  test(
    'waitForReady completes when aggregate readiness becomes true',
    () async {
      final ready = lifecycle.waitForReady(timeout: const Duration(seconds: 1));

      lifecycle.markViewAttached(true);
      lifecycle.markBridgeReady();
      lifecycle.markFirstFrameSeen();

      await expectLater(ready, completes);
    },
  );

  test(
    'waitForReady times out when aggregate readiness never becomes true',
    () {
      expect(
        lifecycle.waitForReady(timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('legacy non-envelope message does not trigger bridgeReady', () async {
    final listeners = UnityMessageListeners.createForTest(lifecycle: lifecycle);

    await listeners.handleUnityMessage('{"protocolVersion":"0.1.0"}');

    expect(lifecycle.state.value.bridgeReady, isFalse);
  });

  test(
    'valid H1 evt triggers bridgeReady and mapped lifecycle state',
    () async {
      final listeners = UnityMessageListeners.createForTest(
        lifecycle: lifecycle,
      );

      await listeners.handleUnityMessage(
        BridgeEnvelope.event(
          msgId: 'evt-1',
          method: EmbedUnityLifecycleEvent.firstFrameSeen,
          ts: 1,
        ).encodeString(),
      );

      expect(lifecycle.state.value.bridgeReady, isTrue);
      expect(lifecycle.state.value.firstFrameSeen, isTrue);
    },
  );

  test('known lifecycle evt is not forwarded as a legacy message', () async {
    final listener = _RecordingListener();
    final listeners = UnityMessageListeners.createForTest(lifecycle: lifecycle);
    listeners.addListener(listener);

    await listeners.handleUnityMessage(
      BridgeEnvelope.event(
        msgId: 'evt-1',
        method: EmbedUnityLifecycleEvent.runtimeLoaded,
        ts: 1,
      ).encodeString(),
    );

    expect(listener.messages, isEmpty);
  });
}

class _RecordingListener implements UnityMessageListener {
  final messages = <String>[];

  @override
  void onMessageFromUnity(String data) {
    messages.add(data);
  }
}
