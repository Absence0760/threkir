import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_routine_store.dart';
import '../lib/widgets/routine_builder_sheet.dart';

void main() {
  testWidgets('routine builder text fields expose semantics labels',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('field_a11y');
    final store = LocalRoutineStore();
    await store.init(overrideDirectory: dir);
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RoutineBuilderSheet(store: store)),
      ));
      await tester.pump();

      // What a screen reader reads for each edit box: the label of every
      // text-field node in the semantics tree, after any enclosing Semantics
      // label has merged in. Reading the tree rather than the Semantics
      // widgets is what lets a field name itself through its decoration.
      final handle = tester.ensureSemantics();
      final named = <String>[];
      void visit(SemanticsNode node) {
        if (node.flagsCollection.isTextField) named.add(node.label);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      handle.dispose();

      // The exercise-name field names itself through its hint, so a screen
      // reader announces a named edit box, not "edit box".
      expect(named, contains('Exercise name'));
      // The notes field shows no label or hint, so its section label names it.
      expect(named, contains('Notes (optional)'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
