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
