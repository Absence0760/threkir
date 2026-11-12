/// "Move to another day" from the workout editor (issue #1186, decisions
/// § 2073): the editor offers it only with days to move to, refuses while the
/// form holds unsaved edits, and a picked day goes to
/// `TrainingService.moveWorkout`, labelled with what it swaps with.
library;

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_move.dart';
import '../lib/training_service.dart';
import '../lib/widgets/workout_edit_sheet.dart';

class _FakeTraining extends TrainingService {
  final List<(String, String)> moves = [];
  Object? errorToThrow;

  @override
  Future<String?> moveWorkout(String workoutId, String dateIso) async {
    if (errorToThrow != null) throw errorToThrow!;
    moves.add((workoutId, dateIso));
    return null;
  }
}

PlanWorkoutRow _row(String id, DateTime date, String kind) => PlanWorkoutRow(
      id: id,
      weekId: 'wk1',
      scheduledDate: date,
      kind: kind,
      targetDistanceM: kind == 'rest' ? null : 8000,
      manuallyCompleted: false,
    );

final _tempo = _row('tempo', DateTime(2031, 3, 11), 'tempo');
final _days = [
  WorkoutMoveDay('2031-03-13', _row('thu-rest', DateTime(2031, 3, 13), 'rest')),
  const WorkoutMoveDay('2031-03-14', null),
];

Future<bool? Function()> _pump(
  WidgetTester tester,
  _FakeTraining training, {
  List<WorkoutMoveDay> days = const [],
}) async {
  bool? result;
  await tester.binding.setSurfaceSize(const Size(400, 800));
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
                workout: _tempo,
                training: training,
                moveDays: days,
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
  return () => result;
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('no days to move to, no move action', (tester) async {
    await _pump(tester, _FakeTraining());
    expect(find.byKey(const Key('workoutEditMove')), findsNothing);
  });

  testWidgets('a picked day is moved to, and the editor closes as saved',
      (tester) async {
    final training = _FakeTraining();
    final result = await _pump(tester, training, days: _days);

    await tester.ensureVisible(find.byKey(const Key('workoutEditMove')));
    await tester.tap(find.byKey(const Key('workoutEditMove')));
    await tester.pumpAndSettle();

    expect(find.text('Swaps with Rest'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workoutMoveDay-2031-03-13')));
    await tester.pumpAndSettle();

    expect(training.moves, [('tempo', '2031-03-13')]);
    expect(result(), isTrue);
    expect(find.byKey(const Key('workoutEditMove')), findsNothing);
  });

  testWidgets('a failed move says so and keeps the sheet open', (tester) async {
    final training = _FakeTraining()..errorToThrow = Exception('boom');
    await _pump(tester, training, days: _days);

    await tester.ensureVisible(find.byKey(const Key('workoutEditMove')));
    await tester.tap(find.byKey(const Key('workoutEditMove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workoutMoveDay-2031-03-14')));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't move this workout"), findsOneWidget);
    expect(find.byKey(const Key('workoutMoveDay-2031-03-14')), findsOneWidget);
  });

  testWidgets('unsaved edits must be saved or discarded before a move',
      (tester) async {
    final training = _FakeTraining();
    await _pump(tester, training, days: _days);

    // The notes field, the last field on a non-race workout.
    await tester.enterText(find.byType(TextField).last, 'changed');
    await tester.ensureVisible(find.byKey(const Key('workoutEditMove')));
    await tester.tap(find.byKey(const Key('workoutEditMove')));
    await tester.pumpAndSettle();

    expect(find.text('Save or discard your changes before moving this workout.'),
        findsOneWidget);
    expect(find.byKey(const Key('workoutMoveDay-2031-03-13')), findsNothing);
    expect(training.moves, isEmpty);
  });
}
