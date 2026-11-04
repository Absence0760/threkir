import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/activity_heatmap.dart';

/// Issue #666 round 10 S7. The activity heatmap (on the weekly summary since
/// decisions § 2284) was the fifth dashboard chart
/// and the only one with no header at all, and its four-level scale was
/// `colorScheme.primary` at 35 % / 65 % / 100 % over
/// `surfaceContainerHighest`. Composited and measured against the card that
/// scale reads:
///
///   light  empty 1.164  L1 1.952  L2 4.038  L3 11.005
///   dark   empty 1.316  L1 2.102  L2 4.063  L3  7.766
///
/// so the zero tile and the one-run tile were both under WCAG 1.4.11's 3:1 —
/// and because the zero tiles ARE the calendar frame that tells a reader WHICH
/// day a filled tile is, an invisible frame costs the filled tiles their
/// meaning too. The levels now come from `ChartPalette.ramp` (3.897 / 7.228 /
/// 13.386 light, 3.859 / 7.126 / 13.149 dark) and the frame is a hairline in
/// the line token §487 already holds at 3:1.
Run _run(String id, DateTime startedAt) => Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      source: RunSource.app,
    );

Future<void> _pump(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ActivityHeatmap(
              // Inside the 20-week window so the run lands on a painted cell.
              runs: [
                _run('r1', DateTime.now().subtract(const Duration(days: 3))),
              ],
              weekStartDay: 'monday',
              onWeekTap: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Fill colours of the four 10x10 legend swatches, in render order.
List<Color> _legendSwatches(WidgetTester tester) => tester
    .widgetList<Container>(find.byType(Container))
    .where((c) =>
        c.constraints == BoxConstraints.tightFor(width: 10, height: 10))
    .map((c) => c.decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.color!)
    .toList();

void main() {
  // The card's label used to be a titleMedium `_SectionHeader` ABOVE it — a
  // fourth header mechanism on a screen whose other four charts each carry an
  // eyebrow inside the card. The window qualifier moves into the header's note
  // slot, so this card is now structurally the intensity card.
  testWidgets('the heatmap card carries the shared chart header',
      (tester) async {
    await _pump(tester, AppTheme.light);
    expect(
      find.ancestor(
        of: find.text('Activity'),
        matching: find.byType(ChartCardHeader),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Last 20 Weeks'),
        matching: find.byType(ChartCardHeader),
      ),
      findsOneWidget,
    );
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    final palette = ChartPalette.ofTheme(theme);

    testWidgets('the $name legend walks the chart ramp', (tester) async {
      await _pump(tester, theme);
      final swatches = _legendSwatches(tester);
      expect(swatches, hasLength(4));
      expect(swatches.sublist(1), palette.ramp);
      // The zero swatch is a track, not a level: it keeps its faint fill and
      // takes the visible hairline instead.
      expect(swatches.first, isNot(palette.ramp.first));
      expect(swatches, isNot(contains(theme.colorScheme.primary)));
    });

    testWidgets('the $name grid paints the ramp and a visible frame',
        (tester) async {
      await _pump(tester, theme);
      final painter = find.byKey(const Key('dashboardHeatmapPainter'));
      // Paint.color round-trips through 32-bit ARGB, so compare there rather
      // than on Color's floating-point channels.
      for (final (what, token) in [
        ('a level-1 tile', palette.ramp.first),
        ('the zero-tile frame', theme.dividerColor),
      ]) {
        expect(
          painter,
          paints
            ..something((symbol, args) =>
                symbol == #drawRRect &&
                (args.last as Paint).color.toARGB32() == token.toARGB32()),
          reason: 'no $what drawn in $name',
        );
      }
      expect(
        painter,
        isNot(paints
          ..something((symbol, args) =>
              symbol == #drawRRect &&
              (args.last as Paint).color.toARGB32() ==
                  theme.colorScheme.primary.toARGB32())),
        reason: 'the $name grid still paints in the brand accent',
      );
    });
  }
}
