import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    EmbedUnity.debugResetSingleInstanceGuard();
  });

  tearDown(() {
    EmbedUnity.debugResetSingleInstanceGuard();
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
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}
