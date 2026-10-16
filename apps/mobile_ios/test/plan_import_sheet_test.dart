import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_serialize.dart';
import '../lib/training.dart';
import '../lib/training_service.dart';
import '../lib/widgets/plan_import_sheet.dart';

const String _plan = '''# Comrades block

- Goal event: custom
- Goal distance: 91.00 km
- Goal time: 11:00:00
- Start date: 2027-03-28

| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2027-03-28 | long | 30.00 km | 6:00 |  |  |  |  |
| 1 | 2027-03-30 | easy | 8.00 km |  |  |  |  |  |
| 2 | 2027-04-04 | race | 56.00 km |  | Two Oceans | Two Oceans Ultra | B | 6:30:00 |
| 3 | 2027-04-11 | race | 91.00 km |  |  | Comrades | A |  |
''';

TrainingPlanRow _row(String id, String name, DateTime start, DateTime end) =>
    TrainingPlanRow(
      id: id,
      userId: 'me-uuid',
      name: name,
      goalEvent: 'custom',
      goalDistanceM: 91000,
      startDate: start,
      endDate: end,
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

class _Training extends TrainingService {
  final List<TrainingPlanRow> activePlans;
  final Object? createError;
  int createCalls = 0;
  ({
    String name,
    GoalEvent goalEvent,
    double goalDistanceM,
    int? goalTimeSec,
    DateTime startDate,
    int daysPerWeek,
    GeneratedPlan generated,
    PlanOverlapAction onOverlap,
  })?
  created;

  _Training({this.activePlans = const [], this.createError});

  @override
  Future<List<TrainingPlanRow>> fetchActivePlans() async => activePlans;

  @override
  Future<TrainingPlanRow> createPlan({
    required String name,
    required GoalEvent goalEvent,
    required double goalDistanceM,
    int? goalTimeSec,
    int? recent5kSec,
    required DateTime startDate,
    required int daysPerWeek,
    String? notes,
    required GeneratedPlan generated,
    PlanOverlapAction onOverlap = PlanOverlapAction.replace,
  }) async {
    createCalls++;
    if (createError != null) throw createError!;
    created = (
      name: name,
      goalEvent: goalEvent,
      goalDistanceM: goalDistanceM,
      goalTimeSec: goalTimeSec,
      startDate: startDate,
      daysPerWeek: daysPerWeek,
      generated: generated,
      onOverlap: onOverlap,
    );
    return _row('new-plan', name, startDate, generated.endDate);
  }
}

class _Result {
  String? planId;
  bool closed = false;
}

Future<_Result> _open(WidgetTester tester, TrainingService training) async {
  final result = _Result();
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result.planId = await showPlanImportSheet(ctx, training);
              result.closed = true;
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

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('planImportText')), text);
  await tester.tap(find.byKey(const Key('planImportLoad')));
  await tester.pumpAndSettle();
}

Future<void> _create(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('planImportCreate')));
  await tester.tap(find.byKey(const Key('planImportCreate')));
  await tester.pumpAndSettle();
}

void main() {
  test('importedDaysPerWeek counts the busiest week, held to 3-7', () {
    expect(importedDaysPerWeek(parsePlanMarkdown(_plan).generated), 3);
    final busy = parsePlanMarkdown(
      [
        '| Week | Date | Type | Distance | Pace | Notes |',
        '| --- | --- | --- | --- | --- | --- |',
        for (var d = 1; d <= 7; d++) '| 1 | 2027-03-0$d | easy | 5 km |  |  |',
        '| 2 | 2027-03-08 | rest |  |  |  |',
      ].join('\n'),
    );
    expect(importedDaysPerWeek(busy.generated), 7);
  });

  testWidgets('Load previews the weeks, workouts and races of a pasted plan', (
    tester,
  ) async {
    await _open(tester, _Training());
    expect(find.byKey(const Key('planImportCreate')), findsNothing);
    await _paste(tester, _plan);
    expect(find.byKey(const Key('planImportPreview')), findsOneWidget);
    expect(find.text('Comrades block'), findsOneWidget);
    expect(find.text('3 weeks · 4 workouts'), findsOneWidget);
    expect(find.text('Week 1: 2 workouts'), findsOneWidget);
    expect(find.text('Week 2: 1 workout'), findsOneWidget);
    expect(find.textContaining('Race: Two Oceans Ultra'), findsOneWidget);
    expect(find.textContaining('Race: Comrades'), findsOneWidget);
    expect(find.byKey(const Key('planImportCreate')), findsOneWidget);
  });

  testWidgets('a malformed plan shows the reason and offers no Create', (
    tester,
  ) async {
    await _open(tester, _Training());
    await _paste(
      tester,
      [
        '| Week | Date | Type | Distance | Pace | Notes |',
        '| --- | --- | --- | --- | --- | --- |',
        '| 1 | 07/05/2026 | easy | 5 km | | |',
      ].join('\n'),
    );
    expect(find.textContaining("Couldn't read that plan"), findsOneWidget);
    expect(find.textContaining('Bad date'), findsOneWidget);
    expect(find.byKey(const Key('planImportPreview')), findsNothing);
    expect(find.byKey(const Key('planImportCreate')), findsNothing);
  });

  testWidgets('editing the text after Load drops the stale preview', (
    tester,
  ) async {
    await _open(tester, _Training());
    await _paste(tester, _plan);
    await tester.enterText(
      find.byKey(const Key('planImportText')),
      '$_plan\n| 4 |',
    );
    await tester.pump();
    expect(find.byKey(const Key('planImportPreview')), findsNothing);
    expect(find.byKey(const Key('planImportCreate')), findsNothing);
  });

  testWidgets('Create sends the parsed plan, races included, and closes', (
    tester,
  ) async {
    final training = _Training();
    final result = await _open(tester, training);
    await _paste(tester, _plan);
    await _create(tester);
    final c = training.created!;
    expect(c.name, 'Comrades block');
    expect(c.goalEvent, GoalEvent.custom);
    expect(c.goalDistanceM, 91000);
    expect(c.goalTimeSec, 11 * 3600);
    expect(c.startDate, DateTime(2027, 3, 28));
    expect(c.daysPerWeek, 3);
    expect(c.onOverlap, PlanOverlapAction.replace);
    final races = [
      for (final w in c.generated.weeks)
        for (final wo in w.workouts)
          if (wo.kind == WorkoutKind.race) wo,
    ];
    expect(races.map((r) => r.raceName), ['Two Oceans Ultra', 'Comrades']);
    expect(races.map((r) => r.racePriority), ['B', 'A']);
    expect(races.first.targetDurationSeconds, 6 * 3600 + 30 * 60);
    expect(result.closed, isTrue);
    expect(result.planId, 'new-plan');
  });

  testWidgets('an overlapping plan asks first, and Keep creates nothing', (
    tester,
  ) async {
    final training = _Training(
      activePlans: [
        _row(
          'old',
          'Marathon block',
          DateTime(2027, 1, 1),
          DateTime(2027, 4, 1),
        ),
      ],
    );
    final result = await _open(tester, training);
    await _paste(tester, _plan);
    await _create(tester);
    expect(find.byKey(const Key('planOverlapReplace')), findsOneWidget);
    await tester.tap(find.text('Keep current').last);
    await tester.pumpAndSettle();
    expect(training.createCalls, 0);
    expect(result.closed, isFalse);
    expect(find.byKey(const Key('planImportPreview')), findsOneWidget);
  });

  testWidgets('a failed create stays open and says so', (tester) async {
    final training = _Training(createError: Exception('offline'));
    final result = await _open(tester, training);
    await _paste(tester, _plan);
    await _create(tester);
    expect(training.createCalls, 1);
    expect(result.closed, isFalse);
    expect(
      find.text(
        "Couldn't create the plan. Check your connection and try again.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('an overlap refused by the server reads as a plan conflict', (
    tester,
  ) async {
    final training = _Training(createError: const ActivePlanExistsError());
    await _open(tester, training);
    await _paste(tester, _plan);
    await _create(tester);
    expect(
      find.text(
        'Another active plan now covers these dates. '
        'Check your plans and try again.',
      ),
      findsOneWidget,
    );
  });
}
