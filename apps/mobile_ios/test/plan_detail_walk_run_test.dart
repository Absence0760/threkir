import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// A couch-to-5K plan on plan detail (decisions § 2158, § 2161): every
/// session states its minutes and the 5K its distance, no week is sized in
/// km, and once the 5K is done the graduation card leads the page.

const _uid = 'owner-uuid';
final DateTime _start = DateTime(2026, 3, 2);

const _timed = {
  'warmup': {'duration_s': 300, 'pace': 'easy'},
  'repeats': {
    'count': 8,
    'duration_s': 60,
    'recovery_duration_s': 90,
    'recovery_pace': 'walk',
  },
  'cooldown': {'duration_s': 300, 'pace': 'easy'},
};

const _fiveK = {
  'warmup': {'duration_s': 300, 'pace': 'easy'},
  'repeats': {'count': 1, 'distance_m': 5000, 'recovery_pace': 'walk'},
  'cooldown': {'duration_s': 300, 'pace': 'easy'},
};

class _Training extends TrainingService {
  _Training({required this.fiveKDone});
  final bool fiveKDone;

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async {
    PlanWeekRow week(int i) => PlanWeekRow(
        id: 'w$i',
        planId: 'plan-1',
        weekIndex: i,
        phase: i == 1 ? 'graduation' : 'build',
        targetVolumeM: 6150);
    PlanWorkoutRow wo(String id, int week, int day,
            {bool done = false, bool fiveK = false}) =>
        PlanWorkoutRow(
          id: id,
          weekId: 'w$week',
          scheduledDate: _start.add(Duration(days: week * 7 + day)),
          kind: 'walk_run',
          targetDistanceM: fiveK ? 5857 : 2050,
          targetDurationSeconds: fiveK ? 4260 : 1710,
          targetPaceSecPerKm: 732,
          structure: fiveK ? _fiveK : _timed,
          manuallyCompleted: done,
        );
    return (
      plan: TrainingPlanRow(
        id: 'plan-1',
        userId: _uid,
        name: 'Couch to 5K',
        goalEvent: 'distance_5k',
        goalDistanceM: 5000,
        startDate: _start,
        endDate: _start.add(const Duration(days: 13)),
        daysPerWeek: 3,
        status: 'active',
        source: 'generated',
        isTemplate: false,
        isPublicTemplate: false,
      ),
      weeks: [week(0), week(1)],
      workouts: [
        wo('a', 0, 0, done: true),
        wo('b', 0, 2, done: true),
        wo('c', 0, 4, done: true),
        wo('d', 1, 0, done: true),
        wo('e', 1, 2, done: true),
        wo('f', 1, 4, done: fiveKDone, fiveK: true),
      ],
    );
  }
}

class _Social extends SocialService {
  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];
}

Future<void> _pump(WidgetTester tester, _Training training) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PlanDetailScreen(
      training: training,
      planId: 'plan-1',
      social: _Social(),
      viewerIdOverride: _uid,
      now: () => DateTime(2026, 3, 13),
    ),
  ));
  await pumpUntil(tester, () => !tester.any(find.byType(FullBodyLoader)),
      describe: 'the plan fetch to replace the full-body loader');
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('sessions read in minutes, the 5K as its distance, no week in km',
      (tester) async {
    await _pump(tester, _Training(fiveKDone: false));
    final size = find.byKey(const ValueKey('planDetailWorkoutSize-e'));
    await tester.scrollUntilVisible(size, 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Text>(size).data, '29 min');
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('planDetailWorkoutSize-f')))
            .data,
        '5.0 km');
    expect(find.byKey(const ValueKey('planDetailWeekVolume-1')), findsNothing);
    expect(find.byKey(const Key('walkRunGraduationCard')), findsNothing);
  });

  testWidgets('the 5K done puts the graduation card on the page',
      (tester) async {
    await _pump(tester, _Training(fiveKDone: true));
    expect(find.byKey(const Key('walkRunGraduationCard')), findsOneWidget);
    expect(find.text('You did it: couch to 5K'), findsOneWidget);
  });
}
