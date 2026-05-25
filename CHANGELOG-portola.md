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

## [portola] H7 - Unity runtime memory policy

- Documented the fork memory policy: single Unity runtime per app session, attach/show on entry, pause + detach on exit, unload only for memory pressure or long idle, and quit is not a normal return path.
- Verified the Dart public surface does not expose `quitApplication` or `unloadApplication`.
- Added iOS source guidance that normal route exits must not call Unity quit/unload; the current iOS policy is pause + detach only.
- Unity 2022.3 iOS UnityFramework stub headers expose `unloadApplication` and `quitApplication`, but this fork does not call them until a same-session recovery path is validated.
- iOS memory profiler validation remains pending until `portola-p0` bumps to this fork SHA; Android H7 remains HOLD for the Android execution environment.

## [portola] H10 - Observability trace foundation

- Added Dart `EmbedUnityTraceEvent` schema with H10 fields, supported event-type validation, JSON serialization, and a sink interface.
- Added debugPrint sink plus file/remote placeholder sinks; sink failures are caught so observability cannot break Unity host flows.
- Wired lifecycle traces for attach, detach, first frame, bridge ready, foreground changes, pause, and resume.
- iOS now calls `UnityFramework.setExecuteHeader(&_mh_execute_header)` before `runEmbedded(...)` when loading Unity, matching the Unity CrashReporter hook exposed by the Unity 2022.3 framework headers.
- iOS induced-crash CrashReporter validation and Android crash collection remain HOLD until `portola-p0` bumps to this fork SHA / Android execution resumes.

## [portola] H8 - Android exporter reproducibility (no hidden Unity Editor state)

Source-level reproducibility hardening of the Unity -> Flutter Android export under
`example_unity_2022_3_project/Assets/FlutterEmbed/Editor/`. Unity target: 2022.3 LTS (`2022.3.62f3`).
Scope: Android only — iOS exporter behaviour and `example_unity_6000_0_project` were not changed.

What changed:

- New `A1BatchPresets.cs` is the single source of truth for the Android batch preset. In batch mode it
  explicitly SETS (not just checks) the reproducibility-critical state before PreCheck:
  `EditorUserBuildSettings.activeBuildTarget = Android`, `exportAsGoogleAndroidProject = true`
  (the M6A hidden-state bug, previously only checked), IL2CPP scripting backend, and target
  architectures `ARMv7 | ARM64`. A fresh checkout with a clean `Library/` no longer depends on a human
  having configured the Editor GUI first.
- `ProjectExporterBatchmode.ExportProjectAndroid` applies the preset before
  `ProjectExportChecker.PreCheckAndroid`, which is kept as a defence-in-depth verifier: if the preset
  ever fails to set a value, the checker still hard-fails the build.
- `ProjectExporterAndroid.cs`: AndroidManifest `<activity>` removal is now an XML DOM edit
  (`System.Xml.Linq.XDocument`) instead of a multiline regex (audit P0-6: regex breaks silently on
  Unity version churn). build.gradle `namespace` injection is a bounded, idempotent
  `// PORTOLA-MARKER-START/END` block; `ndkPath` removal comments out matching lines with a marker;
  `gradle.properties` is read via line scan. No regex-based rewriting remains.
- Mixed line-ending fix (concrete instance of the churn break H8 targets): Unity 2022.3.62f3 emits
  its `unityLibrary/build.gradle` with MIXED endings — CRLF from the gradle template plus bare LF in
  the appended IL2CPP `android {}` block. The line-based gradle edits now normalize all EOL styles
  before splitting (`SplitLines`); without this, Unity's own `namespace`/`ndkPath` lines were merged
  into one blob, so the exporter silently skipped the `ndkPath` removal (NDK-conflict fix) and inserted
  a redundant `namespace` into the wrong block. Verified fixed on real export output (see Validation).
  Unity 2022.3.62f3's `mainTemplate.gradle` already declares `namespace "com.unity3d.player"`, so the
  fork's injection now correctly no-ops on this version and remains only as a fallback for older patches.
- `ProjectExportHelpers.AssertSafeExportDirectory` fail-fasts on dangerous deletion targets
  (filesystem root, Unity project root, `Assets`/`Packages`/`ProjectSettings`/`Library`, or an ancestor
  of any). Wired into both the batch and GUI `Directory.Delete(..., true)` sites.
- `ProjectExportChecker` batch path fail-fasts when `EditorBuildSettings` has no enabled scenes. Scene
  source is the committed `EditorBuildSettings.asset` (currently
  `Assets/Example/Scenes/FlutterEmbedExampleScene.unity` + `...AR.unity`).
- Architecture口径: ARM64 is the primary Portola target; ARMv7 is retained because the committed
  `ProjectSettings.asset` (`AndroidTargetArchitectures: 3`) and the existing checker both require
  ARMv7 + ARM64. Dropping ARMv7 would also require relaxing the checker, which is out of H8 scope.

Shared-state pollution note: in batch mode the preset mutates user/Library `EditorUserBuildSettings`
state (`activeBuildTarget`, `exportAsGoogleAndroidProject`) — these are not committed project files.
The PlayerSettings it sets (IL2CPP, ARMv7+ARM64) already match the committed `ProjectSettings.asset`,
so re-affirming them produces no repo churn; the preset never calls `AssetDatabase.SaveAssets`.

Validation (Unity 2022.3.62f3, Windows 11, Android module + SDK `F:\AndroidEnv\SDK-4.X` + JDK 17):

- New `ProjectExportReproducibilityCheck.RunAll` — a batch-invokable golden-snapshot / idempotency /
  path-guard self-check that exercises every hardened path without a full IL2CPP/Gradle build.
  Command:
  `Unity.exe -batchmode -nographics -projectPath example_unity_2022_3_project -buildTarget Android
   -executeMethod ProjectExportReproducibilityCheck.RunAll -exportPath <tmp>/android/unityLibrary -quit -logFile <log>`
  Result from a fresh/clean `Library/`: **PASS** — all 7 checks green (preset state, manifest XML DOM
  removal + node preservation, gradle namespace marker-block idempotency, ndkPath idempotency,
  gradle.properties read, path-safety guard accept/reject, and `PreCheckAndroid` passing after preset).
- Full BuildPipeline IL2CPP Android export (`ProjectExporterBatchmode.ExportProject`) from clean
  `Library/` (Library/Temp/obj deleted first):
  `Unity.exe -batchmode -nographics -projectPath example_unity_2022_3_project -buildTarget Android
   -executeMethod ProjectExporterBatchmode.ExportProject -exportPath <tmp>/android/unityLibrary -quit -logFile <log>`
  Result: **PASS** — "Building project for Flutter succeeded". The exported `unityLibrary/build.gradle`
  is clean: exactly one (Unity-native) `namespace "com.unity3d.player"`, zero live `ndkPath` lines (the
  ndkPath is commented with a PORTOLA marker), zero redundant injected namespaces; `AndroidManifest.xml`
  has its `<activity>` removed via XML DOM with all other nodes and both `xmlns` declarations preserved;
  `launcher`/`gradle` modules promoted away as expected. Two consecutive clean-Library runs produced the
  same transform outcome (reproducible).

Still HOLD (Android real-device build/run; unchanged by this source work):
- On-device APK build / install / run on the Pixel + Samsung + Xiaomi matrix (M7 plan §Validation Gates).
- Android native H2/H3/H6/H7/H10 ports remain out of this task's scope.
