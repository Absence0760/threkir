import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/walk_run_graduation.dart';
import '../lib/widgets/walk_run_graduation_card.dart';

/// The couch-to-5K graduation card (decisions § 2204): which rows earn it,
/// what it says for the 5K and for an older plan, and that its next step
/// opens a 10K plan.
PlanWorkoutRow _wo(String id, DateTime date, String kind,
        {bool done = false, Object? structure}) =>
    PlanWorkoutRow(
      id: id,
      weekId: 'w0',
      scheduledDate: date,
      kind: kind,
      manuallyCompleted: done,
      structure: structure,
    );

const _fiveK = {
  'warmup': {'duration_s': 300, 'pace': 'easy'},
  'repeats': {'count': 1, 'distance_m': 5000, 'recovery_pace': 'walk'},
  'cooldown': {'duration_s': 300, 'pace': 'easy'},
};

Future<AppLocalizations> _pump(
    WidgetTester tester, WalkRunGraduation g, VoidCallback onTenK) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: WalkRunGraduationCard(graduation: g, onTrainForTenK: onTenK),
    ),
  ));
  return AppLocalizations.delegate.load(const Locale('en'));
}

void main() {
  test('fromRows graduates on the 5K done, and not before', () {
    final rows = [
      _wo('a', DateTime(2026, 3, 2), 'walk_run', done: true),
      _wo('r', DateTime(2026, 3, 3), 'rest'),
      _wo('b', DateTime(2026, 3, 6), 'walk_run', done: true, structure: _fiveK),
    ];
    expect(
        WalkRunGraduationCard.fromRows(rows),
        const WalkRunGraduation(
            workoutId: 'b', date: '2026-03-06', ranFiveK: true));
    expect(
      WalkRunGraduationCard.fromRows([
        rows[0],
        rows[1],
        _wo('b', DateTime(2026, 3, 6), 'walk_run', structure: _fiveK),
      ]),
      isNull,
    );
  });

  testWidgets('the 5K done celebrates it and offers a 10K plan',
      (tester) async {
    var tenK = 0;
    final l10n = await _pump(
        tester,
        const WalkRunGraduation(
            workoutId: 'b', date: '2026-03-06', ranFiveK: true),
        () => tenK++);
    expect(find.text('You did it: couch to 5K'), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('walkRunGraduationBody'))).data,
        l10n.walkRunGraduationBodyFiveK);
    expect(find.text(l10n.walkRunGraduationKeepRunning), findsOneWidget);
    await tester.tap(find.byKey(const Key('walkRunGraduationTenK')));
    expect(tenK, 1);
  });

  testWidgets('an older plan that ended on a timed run is told it finished',
      (tester) async {
    final l10n = await _pump(
        tester,
        const WalkRunGraduation(
            workoutId: 'b', date: '2026-03-06', ranFiveK: false),
        () {});
    expect(
        tester.widget<Text>(find.byKey(const Key('walkRunGraduationBody'))).data,
        l10n.walkRunGraduationBodyFinished);
  });

  testWidgets('at 320 px and twice the text size the card does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 900), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: WalkRunGraduationCard(
              graduation: const WalkRunGraduation(
                  workoutId: 'b', date: '2026-03-06', ranFiveK: true),
              onTrainForTenK: () {},
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
