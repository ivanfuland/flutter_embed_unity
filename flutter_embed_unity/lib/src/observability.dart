import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

class EmbedUnityTraceEventType {
  static const pageEnter = 'page_enter';
  static const pageExit = 'page_exit';
  static const foregroundChange = 'foreground_change';
  static const attach = 'attach';
  static const detach = 'detach';
  static const firstFrame = 'first_frame';
  static const bridgeReady = 'bridge_ready';
  static const pause = 'pause';
  static const resume = 'resume';
  static const error = 'error';

  static const values = <String>{
    pageEnter,
    pageExit,
    foregroundChange,
    attach,
    detach,
    firstFrame,
    bridgeReady,
    pause,
    resume,
    error,
  };
}

@immutable
class EmbedUnityTraceEvent {
  EmbedUnityTraceEvent({
    this.engineVersion,
    this.unityVersion,
    this.compositionMode,
    this.deviceModel,
    this.osVersion,
    this.gpuRenderer,
    required this.eventType,
    required this.ts,
    required this.traceId,
    Map<String, Object?>? details,
  }) : details = Map.unmodifiable(details ?? const {}) {
    if (!EmbedUnityTraceEventType.values.contains(eventType)) {
      throw ArgumentError.value(eventType, 'eventType', 'Unsupported trace event type.');
    }
  }

  factory EmbedUnityTraceEvent.now({
    required String eventType,
    String? traceId,
    Map<String, Object?>? details,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return EmbedUnityTraceEvent(
      eventType: eventType,
      ts: now,
      traceId: traceId ?? 'trace-$now',
      details: details,
    );
  }

  factory EmbedUnityTraceEvent.fromJson(Map<String, Object?> json) {
    final eventType = json['event_type'];
    final ts = json['ts'];
    final traceId = json['trace_id'];
    if (eventType is! String) {
      throw ArgumentError.value(eventType, 'event_type', 'Trace event type must be a string.');
    }
    if (ts is! int) {
      throw ArgumentError.value(ts, 'ts', 'Trace timestamp must be an int.');
    }
    if (traceId is! String || traceId.isEmpty) {
      throw ArgumentError.value(traceId, 'trace_id', 'Trace id must be a non-empty string.');
    }

    return EmbedUnityTraceEvent(
      engineVersion: _optionalString(json['engine_version']),
      unityVersion: _optionalString(json['unity_version']),
      compositionMode: _optionalString(json['composition_mode']),
      deviceModel: _optionalString(json['device_model']),
      osVersion: _optionalString(json['os_version']),
      gpuRenderer: _optionalString(json['gpu_renderer']),
      eventType: eventType,
      ts: ts,
      traceId: traceId,
      details: _optionalMap(json['details'] ?? json['payload']),
    );
  }

  final String? engineVersion;
  final String? unityVersion;
  final String? compositionMode;
  final String? deviceModel;
  final String? osVersion;
  final String? gpuRenderer;
  final String eventType;
  final int ts;
  final String traceId;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (engineVersion != null) 'engine_version': engineVersion,
      if (unityVersion != null) 'unity_version': unityVersion,
      if (compositionMode != null) 'composition_mode': compositionMode,
      if (deviceModel != null) 'device_model': deviceModel,
      if (osVersion != null) 'os_version': osVersion,
      if (gpuRenderer != null) 'gpu_renderer': gpuRenderer,
      'event_type': eventType,
      'ts': ts,
      'trace_id': traceId,
      'details': details,
    };
  }

  String encodeString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) {
    return other is EmbedUnityTraceEvent &&
        other.engineVersion == engineVersion &&
        other.unityVersion == unityVersion &&
        other.compositionMode == compositionMode &&
        other.deviceModel == deviceModel &&
        other.osVersion == osVersion &&
        other.gpuRenderer == gpuRenderer &&
        other.eventType == eventType &&
        other.ts == ts &&
        other.traceId == traceId &&
        mapEquals(other.details, details);
  }

  @override
  int get hashCode => Object.hash(
    engineVersion,
    unityVersion,
    compositionMode,
    deviceModel,
    osVersion,
    gpuRenderer,
      eventType,
      ts,
      traceId,
      Object.hashAll(
        details.entries.map((entry) => Object.hash(entry.key, entry.value)),
      ),
    );
}

abstract class ObservabilitySink {
  FutureOr<void> emit(EmbedUnityTraceEvent event);
}

class DebugPrintObservabilitySink implements ObservabilitySink {
  const DebugPrintObservabilitySink();

  @override
  void emit(EmbedUnityTraceEvent event) {
    debugPrint('FlutterEmbedTrace ${event.encodeString()}');
  }
}

class FileObservabilitySinkPlaceholder implements ObservabilitySink {
  const FileObservabilitySinkPlaceholder();

  @override
  void emit(EmbedUnityTraceEvent event) {}
}

class RemoteObservabilitySinkPlaceholder implements ObservabilitySink {
  const RemoteObservabilitySinkPlaceholder();

  @override
  void emit(EmbedUnityTraceEvent event) {}
}

class EmbedUnityObservability {
  EmbedUnityObservability._({required ObservabilitySink sink}) : _sink = sink;

  static final instance = EmbedUnityObservability._(
    sink: const DebugPrintObservabilitySink(),
  );

  @visibleForTesting
  factory EmbedUnityObservability.createForTest({
    required ObservabilitySink sink,
  }) {
    return EmbedUnityObservability._(sink: sink);
  }

  ObservabilitySink _sink;

  void setSink(ObservabilitySink sink) {
    _sink = sink;
  }

  Future<void> emit(EmbedUnityTraceEvent event) async {
    try {
      await Future<void>.sync(() => _sink.emit(event));
    } catch (error) {
      debugPrint('FlutterEmbedTrace sink failed: $error');
    }
  }

  void trace(String eventType, {Map<String, Object?>? details}) {
    unawaited(
      emit(EmbedUnityTraceEvent.now(eventType: eventType, details: details)),
    );
  }
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw ArgumentError.value(value, 'trace field', 'Expected a string.');
}

Map<String, Object?> _optionalMap(Object? value) {
  if (value == null) {
    return const {};
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw ArgumentError.value(value, 'details', 'Expected an object.');
}
