import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/workout_detail_screen.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';

/// A done workout run long reads "Completed · +3 km" on the workout itself
/// (decisions § 2126); a few hundred metres, or a refused run read, leaves
/// the plain "Completed".

class _FakeTraining extends TrainingService {
  final double? runDistance;
  final bool distanceFails;
  int distanceReads = 0;
  _FakeTraining({this.runDistance, this.distanceFails = false});

  @override
  Future<PlanWorkoutRow?> fetchWorkout(String id) async => PlanWorkoutRow(
        id: 'wo',
        weekId: 'week-1',
        scheduledDate: DateTime(2026, 4, 5),
        kind: 'tempo',
        targetDistanceM: 10000,
        completedRunId: 'run-1',
        completedAt: DateTime(2026, 4, 5, 8),
        manuallyCompleted: false,
      );

  @override
  Future<String?> fetchPlanOwnerId(String planId) async => null;

  @override
  Future<Map<String, double>> fetchRunDistances(List<String> ids) async {
    distanceReads++;
    if (distanceFails) throw Exception('runs read refused');
    return {if (runDistance != null) 'run-1': runDistance!};
  }
}

Future<void> _pump(WidgetTester tester, _FakeTraining training) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: WorkoutDetailScreen(
      training: training,
      planId: 'plan',
      workoutId: 'wo',
    ),
  ));
  await pumpUntil(tester, () => training.distanceReads > 0,
      describe: 'the linked run distance read');
  await tester.pump();
}

String _status(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('workoutDetailStatusLabel')))
    .data!;

void main() {
  testWidgets('3 km past the target reads "Completed · +3 km"',
      (tester) async {
    await _pump(tester, _FakeTraining(runDistance: 13000));
    expect(_status(tester), 'Completed · +3 km');
    expect(find.bySemanticsLabel('Completed, 3 km more than planned'),
        findsOneWidget);
  });

  testWidgets('a few hundred metres past the target stays "Completed"',
      (tester) async {
    await _pump(tester, _FakeTraining(runDistance: 10600));
    expect(_status(tester), 'Completed');
  });

  testWidgets('a refused run read stays "Completed"', (tester) async {
    await _pump(tester, _FakeTraining(runDistance: 13000, distanceFails: true));
    expect(_status(tester), 'Completed');
  });
}
