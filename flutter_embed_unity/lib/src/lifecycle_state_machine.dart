import 'dart:async';

import 'package:flutter/foundation.dart';

class EmbedUnityLifecycleEvent {
  static const runtimeLoaded = 'runtimeLoaded';
  static const firstFrameSeen = 'firstFrameSeen';
  static const foregroundActive = 'foregroundActive';
}

@immutable
class EmbedUnityState {
  const EmbedUnityState({
    this.runtimeLoaded = false,
    this.viewAttached = false,
    this.firstFrameSeen = false,
    this.bridgeReady = false,
    this.foregroundActive = false,
  });

  final bool runtimeLoaded;
  final bool viewAttached;
  final bool firstFrameSeen;
  final bool bridgeReady;
  final bool foregroundActive;

  bool get isReady => viewAttached && bridgeReady && firstFrameSeen;

  EmbedUnityState copyWith({
    bool? runtimeLoaded,
    bool? viewAttached,
    bool? firstFrameSeen,
    bool? bridgeReady,
    bool? foregroundActive,
  }) {
    return EmbedUnityState(
      runtimeLoaded: runtimeLoaded ?? this.runtimeLoaded,
      viewAttached: viewAttached ?? this.viewAttached,
      firstFrameSeen: firstFrameSeen ?? this.firstFrameSeen,
      bridgeReady: bridgeReady ?? this.bridgeReady,
      foregroundActive: foregroundActive ?? this.foregroundActive,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EmbedUnityState &&
        other.runtimeLoaded == runtimeLoaded &&
        other.viewAttached == viewAttached &&
        other.firstFrameSeen == firstFrameSeen &&
        other.bridgeReady == bridgeReady &&
        other.foregroundActive == foregroundActive;
  }

  @override
  int get hashCode => Object.hash(
    runtimeLoaded,
    viewAttached,
    firstFrameSeen,
    bridgeReady,
    foregroundActive,
  );

  @override
  String toString() {
    return 'EmbedUnityState('
        'runtimeLoaded: $runtimeLoaded, '
        'viewAttached: $viewAttached, '
        'firstFrameSeen: $firstFrameSeen, '
        'bridgeReady: $bridgeReady, '
        'foregroundActive: $foregroundActive, '
        'isReady: $isReady)';
  }
}

class EmbedUnityLifecycle {
  EmbedUnityLifecycle._();

  static final instance = EmbedUnityLifecycle._();

  @visibleForTesting
  factory EmbedUnityLifecycle.createForTest() {
    return EmbedUnityLifecycle._();
  }

  final ValueNotifier<EmbedUnityState> _state = ValueNotifier(
    const EmbedUnityState(),
  );

  ValueListenable<EmbedUnityState> get state => _state;

  Future<void> waitForReady({required Duration timeout}) {
    if (_state.value.isReady) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    Timer? timer;

    void listener() {
      if (_state.value.isReady && !completer.isCompleted) {
        timer?.cancel();
        _state.removeListener(listener);
        completer.complete();
      }
    }

    timer = Timer(timeout, () {
      _state.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'Timed out waiting for EmbedUnity readiness.',
            timeout,
          ),
        );
      }
    });

    _state.addListener(listener);
    listener();
    return completer.future;
  }

  void markRuntimeLoaded() {
    _update(_state.value.copyWith(runtimeLoaded: true));
  }

  void markViewAttached(bool attached) {
    _update(_state.value.copyWith(viewAttached: attached));
  }

  void markFirstFrameSeen() {
    _update(_state.value.copyWith(firstFrameSeen: true));
  }

  void markBridgeReady() {
    _update(_state.value.copyWith(bridgeReady: true));
  }

  void markForegroundActive(bool active) {
    _update(_state.value.copyWith(foregroundActive: active));
  }

  bool handleEvent(String method, {Object? payload}) {
    switch (method) {
      case EmbedUnityLifecycleEvent.runtimeLoaded:
        markRuntimeLoaded();
        return true;
      case EmbedUnityLifecycleEvent.firstFrameSeen:
        markFirstFrameSeen();
        return true;
      case EmbedUnityLifecycleEvent.foregroundActive:
        markForegroundActive(_activeFromPayload(payload));
        return true;
    }
    return false;
  }

  @visibleForTesting
  void reset() {
    _state.value = const EmbedUnityState();
  }

  void _update(EmbedUnityState next) {
    if (_state.value != next) {
      _state.value = next;
    }
  }
}

bool _activeFromPayload(Object? payload) {
  if (payload is bool) {
    return payload;
  }
  if (payload is Map) {
    final active = payload['active'];
    if (active is bool) {
      return active;
    }
  }
  return true;
}
