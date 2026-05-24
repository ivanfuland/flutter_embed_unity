import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:flutter_embed_unity_platform_interface/flutter_embed_unity_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    EmbedUnity.debugResetSingleInstanceGuard();
    FlutterEmbedUnityPlatform.instance = _RecordingPlatform();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
  });

  tearDown(() {
    EmbedUnity.debugResetSingleInstanceGuard();
    FlutterEmbedUnityPlatform.instance = _RecordingPlatform();
  });

  testWidgets('single EmbedUnity instance mounts successfully', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_wrap(const EmbedUnity()));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('second active EmbedUnity instance fails fast', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      _wrap(const Column(children: [EmbedUnity(), EmbedUnity()])),
    );

    final error = tester.takeException();
    expect(error, isA<StateError>());
    expect(error.toString(), contains('Only one EmbedUnity allowed in P0'));
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('disposing first EmbedUnity releases the guard', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_wrap(const EmbedUnity()));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump();

    await tester.pumpWidget(_wrap(const EmbedUnity()));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dispose sends best-effort unmountUnity', (tester) async {
    final platform = _RecordingPlatform();
    FlutterEmbedUnityPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const EmbedUnity()));
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump();

    expect(platform.unmountCalls, 1);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dispose swallows native unmountUnity failure', (tester) async {
    final platform = _ThrowingUnmountPlatform();
    FlutterEmbedUnityPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const EmbedUnity()));
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump();

    expect(platform.unmountCalls, 1);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

class _RecordingPlatform extends FlutterEmbedUnityPlatform {
  int unmountCalls = 0;

  @override
  Future<void> unmountUnity() async {
    unmountCalls += 1;
  }
}

class _ThrowingUnmountPlatform extends FlutterEmbedUnityPlatform {
  int unmountCalls = 0;

  @override
  Future<void> unmountUnity() async {
    unmountCalls += 1;
    throw Exception('native unmount failed');
  }
}
