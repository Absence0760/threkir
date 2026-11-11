// Grisnir's milestone moment (#1364): one milestone per run, most notable
// first, in lockstep with web `pickMilestone`; the post-run summary scores
// it from the phone's own runs and drops him on a failed sync; the art is
// hidden from assistive tech and the line wraps at the largest text.

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/mascot.dart';
import '../lib/pr_card.dart' show PrCardKind;
import '../lib/screens/run_screen.dart';
import '../lib/widgets/grisnir_moments.dart';

Run _run(String id, double metres) => Run(
      id: id,
      startedAt: DateTime(2026, 4, 10, 8),
      duration: const Duration(minutes: 30),
      distanceMetres: metres,
      track: const [],
      source: RunSource.app,
    );

MilestoneKind? _pick({
  int totalRuns = 12,
  double runDistanceM = 6000,
  double longestRunM = 21100,
  List<(String, PrCardKind)> records = const [],
  bool badgeEarned = false,
}) =>
    pickMilestone(
      totalRuns: totalRuns,
      runDistanceM: runDistanceM,
      longestRunM: longestRunM,
      records: records,
      badgeEarned: badgeEarned,
    );

Widget _summary({String? syncError, MilestoneKind? milestone}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: FinishedSummary(
            distanceValue: '5.03',
            distanceUnit: 'km',
            timeValue: '28:41',
            movingValue: '27:12',
            primaryLabel: 'Avg pace',
            primaryValue: '5:42',
            primaryUnit: '/km',
            synced: syncError == null,
            syncError: syncError,
            onDone: () {},
            milestone: milestone,
          ),
        ),
      ),
    );

void main() {
  group('pickMilestone (parity with web mascot.test.ts)', () {
    test('a plain run earns none', () => expect(_pick(), isNull));
    test('the first run outranks everything it also is', () {
      expect(
        _pick(
          totalRuns: 1,
          runDistanceM: 5000,
          longestRunM: 5000,
          records: const [('5k', PrCardKind.first)],
          badgeEarned: true,
        ),
        MilestoneKind.firstRun,
      );
    });
    test('the first 5K is a 5k record of kind first, ahead of a badge', () {
      expect(
        _pick(records: const [('5k', PrCardKind.first)], badgeEarned: true),
        MilestoneKind.first5k,
      );
      expect(_pick(records: const [('10k', PrCardKind.first)]), isNull);
    });
    test('a badge, then a new best, then the longest run', () {
      expect(
        _pick(badgeEarned: true, records: const [('10k', PrCardKind.improved)]),
        MilestoneKind.badge,
      );
      expect(_pick(records: const [('10k', PrCardKind.improved)]),
          MilestoneKind.best);
      expect(_pick(records: const [('10k', PrCardKind.held)]), isNull);
      expect(_pick(runDistanceM: 21100), MilestoneKind.longest);
      expect(_pick(runDistanceM: 0, longestRunM: 0), isNull);
    });
  });

  group('localMilestone, from the phone store', () {
    test('the only run is the first run, in the store or not', () {
      final r = _run('a', 3000);
      expect(localMilestone(r, [r]), MilestoneKind.firstRun);
      expect(localMilestone(r, const []), MilestoneKind.firstRun);
    });
    test('the first run past 5 km is the first 5K', () {
      expect(localMilestone(_run('b', 5100), [_run('a', 3000)]),
          MilestoneKind.first5k);
      expect(localMilestone(_run('b', 5100), [_run('a', 8000)]), isNull);
    });
    test('the longest yet, never on a shorter run', () {
      expect(localMilestone(_run('c', 9000), [_run('a', 6000), _run('b', 8000)]),
          MilestoneKind.longest);
      expect(localMilestone(_run('c', 4000), [_run('a', 6000)]), isNull);
    });
  });

  testWidgets('the summary shows his hop and line on a clean finish',
      (tester) async {
    await tester.pumpWidget(_summary(milestone: MilestoneKind.firstRun));
    expect(find.byKey(const Key('run-milestone-grisnir')), findsOneWidget);
    final art = tester.widget<Image>(find.descendant(
        of: find.byKey(const Key('run-milestone-grisnir')),
        matching: find.byType(Image)));
    expect((art.image as AssetImage).assetName, kGrisnirProudAsset);
    expect(art.excludeFromSemantics, isTrue);
    expect(find.text("First run in. That's the hard one."), findsOneWidget);
  });

  testWidgets('a failed sync takes him off the summary', (tester) async {
    await tester.pumpWidget(_summary(
        milestone: MilestoneKind.firstRun, syncError: 'Could not sync'));
    expect(find.byKey(const Key('run-milestone-grisnir')), findsNothing);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('every line fits a 320 px card at 2x text in $locale',
        (tester) async {
      for (final kind in MilestoneKind.values) {
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(width: 320, child: GrisnirMilestone(kind: kind)),
          ),
        ));
        expect(tester.takeException(), isNull, reason: '$kind');
      }
    });
  }
}
