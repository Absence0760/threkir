import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_service.dart';
import '../lib/widgets/next_race_card.dart';

ActivePlanOverview _plan(DateTime start, DateTime end) => ActivePlanOverview(
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: 'u1',
        name: 'Spring Half',
        goalEvent: 'distance_half',
        goalDistanceM: 21097,
        startDate: start,
        endDate: end,
        daysPerWeek: 4,
        status: 'active',
        source: 'app',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: const [],
      workouts: const [],
      todayWorkout: null,
      completionPct: 0,
      currentWeekIndex: 0,
    );

Future<void> _pump(WidgetTester tester, ActivePlanOverview o, DateTime now,
    {VoidCallback? onTap}) {
  return tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: NextRaceCard(overview: o, now: now, onTap: onTap)),
  ));
}

String _countdown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('nextRaceCountdown'))).data!;

void main() {
  final start = DateTime(2026, 6, 1);
  final race = DateTime(2026, 8, 30);

  testWidgets('counts down to race day with the plan name', (tester) async {
    await _pump(tester, _plan(start, race), DateTime(2026, 8, 1, 9));
    expect(find.text('Spring Half'), findsOneWidget);
    expect(_countdown(tester), 'Race in 29 days');
  });

  testWidgets('the day before reads as tomorrow', (tester) async {
    await _pump(tester, _plan(start, race), DateTime(2026, 8, 29, 23, 30));
    expect(_countdown(tester), 'Race tomorrow');
  });

  testWidgets('race day itself', (tester) async {
    await _pump(tester, _plan(start, race), DateTime(2026, 8, 30, 6));
    expect(_countdown(tester), 'Race day');
  });

  testWidgets('before the plan starts it counts to the start',
      (tester) async {
    await _pump(tester, _plan(start, race), DateTime(2026, 5, 25));
    expect(_countdown(tester), 'Starts in 7 days');
  });

  testWidgets('the day before the plan starts reads as starts tomorrow',
      (tester) async {
    await _pump(tester, _plan(start, race), DateTime(2026, 5, 31, 22));
    expect(_countdown(tester), 'Starts tomorrow');
  });

  test('hides once the race is behind the runner', () {
    expect(NextRaceCard.shows(_plan(start, race), DateTime(2026, 8, 30)),
        isTrue);
    expect(NextRaceCard.shows(_plan(start, race), DateTime(2026, 8, 31)),
        isFalse);
  });

  testWidgets('tapping opens the plan', (tester) async {
    var opened = 0;
    await _pump(tester, _plan(start, race), DateTime(2026, 8, 1),
        onTap: () => opened++);
    await tester.tap(find.byType(NextRaceCard));
    expect(opened, 1);
  });
}
