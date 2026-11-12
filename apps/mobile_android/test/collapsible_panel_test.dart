import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/fab_clearance.dart';
import '../lib/widgets/collapsible_panel.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool initiallyExpanded = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: CollapsiblePanel(
                initiallyExpanded: initiallyExpanded,
                expandedChild: const Text('expanded content'),
                collapsedChild: const Text('collapsed content'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom edge of the panel's content, with the panel pinned to the bottom of
/// the body as the run screen pins it, optionally under a docked FAB.
Future<double> _contentBottom(WidgetTester tester, {double? fabInset}) async {
  Widget panel = const Align(
    alignment: Alignment.bottomCenter,
    child: CollapsiblePanel(
      expandedChild: Text('expanded content'),
      collapsedChild: Text('collapsed content'),
    ),
  );
  if (fabInset != null) panel = DockedFabInset(height: fabInset, child: panel);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: panel),
  ));
  await tester.pumpAndSettle();
  return tester.getBottomLeft(find.text('expanded content')).dy;
}

void main() {
  group('CollapsiblePanel under a docked FAB', () {
    testWidgets('lifts its content clear of the FAB overhang', (tester) async {
      final bare = await _contentBottom(tester);
      final docked =
          await _contentBottom(tester, fabInset: kDockedFabOverhang);
      expect(bare - docked, kDockedFabOverhang,
          reason: 'the bottom row (the recorder\'s Stop + "Hold to stop") '
              'must sit above the docked Log FAB, not under it');
    });
  });

  group('CollapsiblePanel', () {
    testWidgets('shows expandedChild when initiallyExpanded is true',
        (tester) async {
      await _pump(tester, initiallyExpanded: true);
      await tester.pumpAndSettle();
      expect(find.text('expanded content'), findsOneWidget);
    });

    testWidgets('shows collapsedChild when initiallyExpanded is false',
        (tester) async {
      await _pump(tester, initiallyExpanded: false);
      await tester.pumpAndSettle();
      expect(find.text('collapsed content'), findsOneWidget);
    });

    testWidgets('tapping the drag handle toggles from expanded to collapsed',
        (tester) async {
      await _pump(tester, initiallyExpanded: true);
      await tester.pumpAndSettle();

      // The Semantics node for the handle has a label we can find.
      final handleFinder = find.bySemanticsLabel('Collapse stats panel');
      expect(handleFinder, findsOneWidget);
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Expand stats panel'), findsOneWidget);
    });

    testWidgets('tapping the drag handle toggles from collapsed to expanded',
        (tester) async {
      await _pump(tester, initiallyExpanded: false);
      await tester.pumpAndSettle();

      final handleFinder = find.bySemanticsLabel('Expand stats panel');
      expect(handleFinder, findsOneWidget);
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Collapse stats panel'), findsOneWidget);
    });

    testWidgets('drag handle has button semantics for accessibility',
        (tester) async {
      await _pump(tester, initiallyExpanded: true);
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.bySemanticsLabel('Collapse stats panel'),
      );
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    });
  });
}
