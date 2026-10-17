import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/preferences.dart';
import '../lib/training.dart' show WorkoutKind;
import '../lib/training_service.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/workout_edit_sheet.dart';

class _FakeTraining extends TrainingService {
  ({
    String workoutId,
    String? kind,
    String? fromKind,
    PlanWorkoutTargets? targets,
    double? targetDistanceM,
    int? targetPaceSecPerKm,
    String? notes,
    PlanWorkoutRaceFields? race,
  })? lastUpdate;
  Object? errorToThrow;

  @override
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    String? fromKind,
    PlanWorkoutTargets? targets,
    String? notes,
    PlanWorkoutRaceFields? race,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastUpdate = (
      workoutId: workoutId,
      kind: kind,
      fromKind: fromKind,
      targets: targets,
      targetDistanceM: targets?.distanceM,
      targetPaceSecPerKm: targets?.paceSecPerKm,
      notes: notes,
      race: race,
    );
  }
}

PlanWorkoutRow _workout({
  String kind = 'tempo',
  double? targetDistanceM = 8000,
  int? targetPaceSecPerKm = 300,
  String? notes = 'Easy effort',
  int? targetDurationSeconds,
  String? raceName,
  String? racePriority,
}) =>
    PlanWorkoutRow(
      id: 'wo1',
      weekId: 'wk1',
      scheduledDate: DateTime(2026, 4, 25),
      kind: kind,
      targetDistanceM: targetDistanceM,
      targetPaceSecPerKm: targetPaceSecPerKm,
      notes: notes,
      targetDurationSeconds: targetDurationSeconds,
      raceName: raceName,
      racePriority: racePriority,
      manuallyCompleted: false,
    );

Future<bool?> _pumpSheet(
  WidgetTester tester,
  PlanWorkoutRow workout,
  _FakeTraining training,
) async {
  bool? result;
  await tester.binding.setSurfaceSize(const Size(400, 700));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await showWorkoutEditSheet(
                ctx,
                workout: workout,
                training: training,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('WorkoutEditSheet', () {
    testWidgets('pre-populates kind, distance, and notes from the workout',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      // Full-screen dialog presentation (was a bottom sheet).
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      // Distance 8.0 km
      expect(find.text('8.0'), findsOneWidget);
      // Notes field
      expect(find.text('Easy effort'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid pace format', (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(targetPaceSecPerKm: null), training);
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. 5:30'),
        'notapace',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pace must look like'), findsOneWidget);
    });

    testWidgets(
        'invalid distance + pace flag their own fields in ONE save attempt; '
        'editing clears each; save then proceeds (issue #666 U6)',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(
        tester,
        _workout(targetDistanceM: null, targetPaceSecPerKm: null, notes: ''),
        training,
      );
      final distanceField = find.widgetWithText(TextField, 'e.g. 8.0');
      final paceField = find.widgetWithText(TextField, 'e.g. 5:30');
      await tester.enterText(distanceField, 'abc');
      await tester.enterText(paceField, 'notapace');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(
          tester.widget<TextField>(distanceField).decoration?.errorText,
          'Enter a positive distance in km');
      expect(tester.widget<TextField>(paceField).decoration?.errorText,
          'Pace must look like 5:30');
      expect(training.lastUpdate, isNull);

      await tester.enterText(distanceField, '10');
      await tester.pump();
      expect(tester.widget<TextField>(distanceField).decoration?.errorText,
          isNull);
      expect(tester.widget<TextField>(paceField).decoration?.errorText,
          isNotNull);

      await tester.enterText(paceField, '5:00');
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate, isNotNull);
      expect(training.lastUpdate!.targetDistanceM, closeTo(10000, 1));
      expect(training.lastUpdate!.targetPaceSecPerKm, 300);
    });

    testWidgets('Cancel returns false and does not call updateWorkout',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate, isNull);
    });

    testWidgets('Save calls updateWorkout with the edited values', (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(
        tester,
        _workout(targetDistanceM: 10000, targetPaceSecPerKm: null, notes: ''),
        training,
      );
      // Edit the distance.
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. 8.0'),
        '12.0',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate, isNotNull);
      expect(training.lastUpdate!.targetDistanceM, closeTo(12000, 1));
    });
  });

  group('WorkoutEditSheet — race fields', () {
    PlanWorkoutRow race() => _workout(
          kind: 'race',
          targetDistanceM: 56000,
          targetPaceSecPerKm: null,
          notes: '',
          targetDurationSeconds: 23400,
          raceName: 'Two Oceans Ultra',
          racePriority: 'B',
        );

    testWidgets('a non-race workout shows no race fields', (tester) async {
      await _pumpSheet(tester, _workout(), _FakeTraining());
      expect(find.byKey(const Key('workoutEditRaceName')), findsNothing);
      expect(find.byKey(const Key('workoutEditRacePriority')), findsNothing);
      expect(find.byKey(const Key('workoutEditRaceGoal')), findsNothing);
    });

    testWidgets('a race workout pre-populates its name, priority and goal time',
        (tester) async {
      await _pumpSheet(tester, race(), _FakeTraining());
      expect(find.widgetWithText(TextField, 'Two Oceans Ultra'),
          findsOneWidget);
      expect(find.text('B — important race'), findsOneWidget);
      expect(find.widgetWithText(TextField, '6:30:00'), findsOneWidget);
    });

    testWidgets('Save writes the edited race name, priority and goal time',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, race(), training);
      await tester.ensureVisible(find.byKey(const Key('workoutEditRaceName')));
      await tester.enterText(
          find.byKey(const Key('workoutEditRaceName')), 'Two Oceans');
      await tester.ensureVisible(find.byKey(const Key('workoutEditRaceGoal')));
      await tester.enterText(
          find.byKey(const Key('workoutEditRaceGoal')), '6:15:00');
      await tester.ensureVisible(find.byKey(const Key('workoutEditRacePriority')));
      await tester.tap(find.byKey(const Key('workoutEditRacePriority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A — goal race').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final race0 = training.lastUpdate!.race!;
      expect(race0.name, 'Two Oceans');
      expect(race0.priority, 'A');
      expect(race0.goalTimeSec, 22500);
    });

    testWidgets(
        'a sub-hour goal on a race with no distance survives an untouched save',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(
          tester,
          _workout(
            kind: 'race',
            targetDistanceM: null,
            targetPaceSecPerKm: null,
            targetDurationSeconds: 2700,
            raceName: 'Parkrun PB',
          ),
          training);
      expect(find.widgetWithText(TextField, '0:45:00'), findsOneWidget);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate!.race!.goalTimeSec, 2700);
    });

    for (final typed in ['45:00', '5:45']) {
      testWidgets('a two-part goal "$typed" is rejected, not unit-guessed',
          (tester) async {
        final training = _FakeTraining();
        await _pumpSheet(tester, race(), training);
        final goal = find.byKey(const Key('workoutEditRaceGoal'));
        await tester.ensureVisible(goal);
        await tester.enterText(goal, typed);
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(tester.widget<TextField>(goal).decoration?.errorText,
            'Goal time must look like 6:30:00');
        expect(training.lastUpdate, isNull);
      });
    }

    testWidgets('changing a race to another kind reports it was a race',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, race(), training);
      await tester.tap(find.byType(DropdownButtonFormField<WorkoutKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Long run').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate!.kind, 'long');
      expect(training.lastUpdate!.fromKind, 'race');
      expect(training.lastUpdate!.race, isNull);
    });

    testWidgets('choosing Automatic clears the priority', (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, race(), training);
      await tester.ensureVisible(find.byKey(const Key('workoutEditRacePriority')));
      await tester.tap(find.byKey(const Key('workoutEditRacePriority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatic').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate!.race!.priority, isNull);
    });

    testWidgets('an unreadable goal time is flagged and nothing is saved',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, race(), training);
      final goal = find.byKey(const Key('workoutEditRaceGoal'));
      await tester.ensureVisible(goal);
      await tester.enterText(goal, 'soon');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(tester.widget<TextField>(goal).decoration?.errorText,
          'Goal time must look like 6:30:00');
      expect(training.lastUpdate, isNull);
    });

    testWidgets('a non-race save sends no race fields', (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(training.lastUpdate!.kind, 'tempo');
      expect(training.lastUpdate!.race, isNull);
    });
  });

  group('WorkoutEditSheet — discard guard', () {
    testWidgets('unedited form: Cancel pops with no discard confirm',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(training.lastUpdate, isNull);
    });

    testWidgets(
        'edited form: system back shows the confirm; dialog Cancel keeps the edit',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.enterText(find.widgetWithText(TextField, '8.0'), '12.0');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);

      // The sheet has its own Cancel button — scope to the dialog's.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('12.0'), findsOneWidget);
    });

    testWidgets(
        'edited form: the Cancel button routes through the confirm; Discard pops without saving',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.enterText(find.widgetWithText(TextField, '8.0'), '12.0');
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Discard')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(AppBar), findsNothing);
      expect(training.lastUpdate, isNull);
    });
  });

  group('WorkoutEditSheet — clearing, rest and units', () {
    Future<void> withUnit(bool miles) async {
      SharedPreferences.setMockInitialValues({'use_miles': miles});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
    }

    tearDown(() async => withUnit(false));

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('emptying distance and pace clears both targets',
        (tester) async {
      // A null used to mean "leave it", so an emptied field kept its target.
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.enterText(
          find.byKey(const Key('workoutEditDistance')), '');
      await tester.enterText(find.byKey(const Key('workoutEditPace')), '');
      await save(tester);
      expect(training.lastUpdate!.targets, isNotNull);
      expect(training.lastUpdate!.targets!.distanceM, isNull);
      expect(training.lastUpdate!.targets!.paceSecPerKm, isNull);
      expect(
        planWorkoutPatch(targets: training.lastUpdate!.targets),
        {'target_distance_m': null, 'target_pace_sec_per_km': null},
      );
    });

    testWidgets('an untouched form re-saves the stored values exactly',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(
          tester, _workout(targetDistanceM: 8050, targetPaceSecPerKm: 301),
          training);
      await save(tester);
      expect(training.lastUpdate!.targetDistanceM, 8050);
      expect(training.lastUpdate!.targetPaceSecPerKm, 301);
    });

    testWidgets('switching to rest disables the targets and clears them',
        (tester) async {
      final training = _FakeTraining();
      await _pumpSheet(tester, _workout(), training);
      await tester.tap(find.text('Tempo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rest').last);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('workoutEditDistance')))
              .enabled,
          isFalse);
      await save(tester);
      expect(training.lastUpdate!.kind, 'rest');
      final patch = planWorkoutPatch(
        kind: training.lastUpdate!.kind,
        targets: training.lastUpdate!.targets,
      );
      expect(patch['target_distance_m'], isNull);
      expect(patch['target_pace_sec_per_km'], isNull);
      expect(patch.containsKey('target_pace_tolerance_sec'), isTrue);
      expect(patch.containsKey('structure'), isTrue);
    });

    testWidgets('miles mode labels, shows and reads targets in miles',
        (tester) async {
      await tester.runAsync(() => withUnit(true));
      final training = _FakeTraining();
      // 8046.72 m = 5.0 mi; 300 s/km = 8:03/mi.
      await _pumpSheet(
          tester, _workout(targetDistanceM: 8046.72, targetPaceSecPerKm: 300),
          training);
      expect(find.text('Target distance (mi)'), findsOneWidget);
      expect(find.text('Target pace (mm:ss /mi)'), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
      expect(find.text('8:03'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('workoutEditDistance')), '10');
      await tester.enterText(find.byKey(const Key('workoutEditPace')), '8:00');
      await save(tester);
      expect(training.lastUpdate!.targetDistanceM, closeTo(16093.44, 0.01));
      // 480 s/mi / 1.609344 = 298.26 s/km.
      expect(training.lastUpdate!.targetPaceSecPerKm, 298);
    });
  });

}
