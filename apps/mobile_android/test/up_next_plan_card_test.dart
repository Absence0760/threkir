import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_service.dart';
import '../lib/widgets/up_next_plan_card.dart';

TrainingPlanRow _row(String id, String name, DateTime start, DateTime end) =>
    TrainingPlanRow(
      id: id,
      userId: 'u1',
      name: name,
      goalEvent: 'distance_marathon',
      goalDistanceM: 42195,
      startDate: start,
      endDate: end,
      daysPerWeek: 5,
      status: 'active',
      source: 'app',
      isTemplate: false,
      isPublicTemplate: false,
    );

// The chaining story: a marathon block ending Nov 15 with an ultra block
// queued to start the next day.
final _marathon =
    _row('marathon', 'NYC Marathon', DateTime(2026, 8, 3), DateTime(2026, 11, 15));
final _ultra =
    _row('ultra', 'Comrades', DateTime(2026, 11, 16), DateTime(2027, 3, 1));

ActivePlanOverview _overview({TrainingPlanRow? upcoming}) => ActivePlanOverview(
      plan: _marathon,
      weeks: const [],
      workouts: const [],
      todayWorkout: null,
      completionPct: 0,
      currentWeekIndex: 0,
      upcomingPlan: upcoming,
    );

Future<void> _pump(WidgetTester tester, ActivePlanOverview o, DateTime now) {
  return tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: UpNextPlanCard(overview: o, now: now)),
  ));
}

void main() {
  test('shows only when a plan is queued', () {
    expect(UpNextPlanCard.shows(_overview()), isFalse);
    expect(UpNextPlanCard.shows(_overview(upcoming: _ultra)), isTrue);
  });

  testWidgets('names the queued plan, its start date and the days to it',
      (tester) async {
    await _pump(tester, _overview(upcoming: _ultra), DateTime(2026, 11, 6, 9));
    expect(find.text('Up next: Comrades, starts Nov 16, 2026'), findsOneWidget);
    expect(find.text('Starts in 10 days'), findsOneWidget);
  });

  testWidgets('the day before reads as tomorrow', (tester) async {
    await _pump(tester, _overview(upcoming: _ultra), DateTime(2026, 11, 15, 22));
    expect(find.text('Starts tomorrow'), findsOneWidget);
  });
}
