# Portola Change Log

## [portola] M7 Task 1 - Fork preflight

- Branch: `portola/m7`, based on `32d6b2d28c15616a274853631942dcff4dcffed2`.
- M7 Unity target: Unity 2022.3 LTS.
- Captured Unity Editor patch version: `2022.3.62f3`.
- Captured Flutter version: `3.44.0 stable` (`559ffa3f75`), Dart `3.12.0`, DevTools `2.57.0`.
- Captured Android SDK target: not available on this Mac preflight host (`ANDROID_HOME`/`ANDROID_SDK_ROOT` unset; `flutter doctor -v` reports Android SDK not found).
- Captured JDK version: not available on this Mac preflight host (`java -version` reports no Java Runtime located).
- Scope guard: `flutter_embed_unity_6000_0_*` packages are out of M7 scope and were not modified.

## [portola] H1 - BridgeContract envelope Dart foundation

- Added Dart BridgeContract envelope codec for `req` / `resp` / `evt` / `err` JSON messages on the existing single method channel.
- Added defensive decode errors for malformed JSON, missing required fields, unsupported versions, invalid message types, and invalid `resp` / `err` correlation.
- Added Dart-side `corrId` request router with timeout, `BridgeError` propagation, and unknown-`corrId` logging without crashing.
- Added `sendToUnityRequest(...) -> Future<dynamic>` while preserving the legacy `sendToUnity(...)` compatibility path used by the M6B host shell.
- Android native and iOS native ports remain deferred to later H2/H3/H6 work; they should consume this Dart envelope API when those tasks start.

## [portola] H5 - Dart single-instance Unity guard

- Added a Dart-side fail-fast guard so only one active `EmbedUnity` instance can be mounted in the process at a time.
- A second active instance now throws `StateError('Only one EmbedUnity allowed in P0')` during `initState`.
- Disposing the active `EmbedUnity` releases the guard so the host shell can recreate Unity after detach/dispose.
- Android and iOS native factory guards remain deferred to the later H5 native port.

## [portola] H2-H3 - Dart and iOS sendToUnity result hardening

- Changed Dart `sendToUnity(...)` to return `Future<void>` and map native `PlatformException` failures to H1 `BridgeError`, while keeping the legacy method name and parameters.
- Preserved legacy `sendToUnity(...)` raw `data` passthrough so M6B host shell BridgeContract v0.1.0 JSON stays byte-identical.
- `sendToUnityRequest(...)` remains the H1 envelope request path; legacy `sendToUnity(...)` does not wrap payloads.
- Hardened iOS `SendToUnity.swift` argument parsing by removing `as! [String]`, returning `FlutterError` for malformed method-call arguments, and calling `result(nil)` on the happy path.
- Android native H2/H3 remains HOLD for the Android execution environment.

## [portola] H6 - Dart and iOS lifecycle readiness state

- Added Dart `EmbedUnityLifecycle` / `EmbedUnityState` with explicit `runtimeLoaded`, `viewAttached`, `firstFrameSeen`, `bridgeReady`, and `foregroundActive` flags plus aggregate `isReady = viewAttached && bridgeReady && firstFrameSeen`.
- Exposed `EmbedUnity.lifecycleState` as a `ValueListenable<EmbedUnityState>` and `EmbedUnity.waitForReady(...)` for business-facing readiness.
- `UnityMessageListeners` now marks `bridgeReady` only after valid H1 `resp` / `evt` envelopes; legacy non-envelope messages do not set bridge readiness.
- iOS emits H1 `evt` lifecycle messages for `runtimeLoaded`, `firstFrameSeen`, and `foregroundActive`; `firstFrameSeen` currently uses the existing `UnityViewStack.viewDidAppear` hook as the best available render-readiness proxy in this fork structure.
- Android H6 native event emit remains HOLD for the Android execution environment.

## [portola] H4 - Explicit iOS unmount signal

- Added platform-interface `unmountUnity()` and a MethodChannel `unmountUnity` method for Dart-driven Unity view detach.
- `EmbedUnity.dispose()` now sends best-effort iOS `unmountUnity` after releasing Dart readiness state; native failures are logged and do not escape widget disposal.
- iOS handles `unmountUnity` by popping the current `UnityViewStack` view idempotently; an empty stack completes successfully.
- `UnityViewStack.viewDidDisappear` is now diagnostic-only because UIKit disappear can be caused by modal, keyboard, navigation overlay, or another route covering the view.
- iOS source change is done in the fork; push/pop/modal/TabBar/keyboard scenario validation remains pending until `portola-p0` bumps to this fork SHA.
