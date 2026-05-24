import 'dart:async';

import 'package:flutter_embed_unity/src/lifecycle_state_machine.dart';
import 'package:flutter_embed_unity/src/observability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trace event JSON round-trips all H10 fields', () {
    final event = EmbedUnityTraceEvent(
      engineVersion: 'Flutter 3.44.0',
      unityVersion: '2022.3.62f3',
      compositionMode: 'UiKitView',
      deviceModel: 'iPhone16,2',
      osVersion: 'iOS 26.5',
      gpuRenderer: 'Apple GPU',
      eventType: EmbedUnityTraceEventType.firstFrame,
      ts: 1716265200000,
      traceId: 'trace-1',
      details: {'viewId': 7, 'source': 'lifecycle'},
    );

    final decoded = EmbedUnityTraceEvent.fromJson(event.toJson());

    expect(decoded, event);
  });

  test('trace event rejects unsupported event types', () {
    expect(
      () => EmbedUnityTraceEvent(
        eventType: 'not_real',
        ts: 1716265200000,
        traceId: 'trace-1',
      ),
      throwsArgumentError,
    );
  });

  test('sink failure does not escape caller', () async {
    final sink = _ThrowingSink();
    final observability = EmbedUnityObservability.createForTest(sink: sink);

    await observability.emit(
      EmbedUnityTraceEvent(
        eventType: EmbedUnityTraceEventType.error,
        ts: 1716265200000,
        traceId: 'trace-1',
      ),
    );

    expect(sink.calls, 1);
  });

  test('lifecycle emits basic readiness trace events', () {
    final sink = _RecordingSink();
    final observability = EmbedUnityObservability.createForTest(sink: sink);
    final lifecycle = EmbedUnityLifecycle.createForTest(
      observability: observability,
    );

    lifecycle.markViewAttached(true);
    lifecycle.markFirstFrameSeen();
    lifecycle.markBridgeReady();
    lifecycle.markViewAttached(false);

    expect(sink.eventTypes, [
      EmbedUnityTraceEventType.attach,
      EmbedUnityTraceEventType.firstFrame,
      EmbedUnityTraceEventType.bridgeReady,
      EmbedUnityTraceEventType.detach,
    ]);
  });
}

class _RecordingSink implements ObservabilitySink {
  final events = <EmbedUnityTraceEvent>[];

  List<String> get eventTypes => [
    for (final event in events) event.eventType,
  ];

  @override
  FutureOr<void> emit(EmbedUnityTraceEvent event) {
    events.add(event);
  }
}

class _ThrowingSink implements ObservabilitySink {
  int calls = 0;

  @override
  FutureOr<void> emit(EmbedUnityTraceEvent event) {
    calls += 1;
    throw StateError('sink failed');
  }
}
