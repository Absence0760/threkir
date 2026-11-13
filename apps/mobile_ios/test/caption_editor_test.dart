import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/caption_editor.dart';
import 'three_button_nav_bar.dart';

// Issue #1374 FS-11: the run, route and club photo galleries closed the editor
// before the write and lost the typed caption when it failed.
void main() {
  Future<({List<String?> saved, List<int> closed})> pump(
    WidgetTester tester, {
    required Future<bool> Function() answer,
  }) async {
    final saved = <String?>[];
    final closed = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CaptionEditor(
          initial: 'Old caption',
          hint: 'Add a caption',
          cancelLabel: 'Cancel',
          saveLabel: 'Save',
          onSave: (v) {
            saved.add(v);
            return answer();
          },
          onClose: () => closed.add(1),
        ),
      ),
    ));
    return (saved: saved, closed: closed);
  }

  testWidgets('a failed save keeps the editor open with the typed text',
      (tester) async {
    final r = await pump(tester, answer: () async => false);
    await tester.enterText(find.byType(TextField), 'Sunrise over the ridge');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(r.saved, ['Sunrise over the ridge']);
    expect(r.closed, isEmpty);
    expect(find.text('Sunrise over the ridge'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
  });

  testWidgets('while the write is in flight the field and buttons hold still',
      (tester) async {
    final gate = Completer<bool>();
    final r = await pump(tester, answer: () => gate.future);
    await tester.enterText(find.byType(TextField), 'New');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(r.closed, isEmpty, reason: 'Cancel is off while saving');

    gate.complete(true);
    await tester.pump();
    expect(r.closed, [1]);
  });

  testWidgets('a cleared caption saves as null', (tester) async {
    final r = await pump(tester, answer: () async => true);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(r.saved, [null]);
  });

  testWidgets('fits 320 dp at 2x text over a 3-button bar', (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding =
        const FakeViewPadding(bottom: kThreeButtonNavBar);
    tester.view.padding = const FakeViewPadding(bottom: kThreeButtonNavBar);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: 2,
        maxScaleFactor: 2,
        child: Scaffold(
          body: SizedBox(
            width: 150,
            child: CaptionEditor(
              initial: null,
              hint: 'Add a caption',
              cancelLabel: 'Cancel',
              saveLabel: 'Save',
              onSave: (_) async => true,
              onClose: () {},
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
