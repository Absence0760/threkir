import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_request_client.dart';
import '../lib/screens/season_plan_screen.dart';
import '../lib/season_types.dart';
import '../lib/training.dart';
import '../lib/plan_calibration.dart';
import '../lib/training_service.dart';

const _today = '2026-08-14';

class _FakeTraining extends TrainingService {
  final List<TrainingPlanRow> active;
  final Set<int> failOnCall;
  final List<({String name, String start, PlanOverlapAction overlap, GeneratedPlan generated})>
      created = [];
  int _calls = 0;

  _FakeTraining({this.active = const [], this.failOnCall = const {}});

  @override
  Future<List<TrainingPlanRow>> fetchActivePlans() async => active;

  @override
  Future<PlanCalibration> fetchPlanCalibration() async =>
      PlanCalibration.unknown;

  @override
  Future<
      ({
        TrainingPlanRow? plan,
        List<PlanWeekRow> weeks,
        List<PlanWorkoutRow> workouts
      })> fetchPlan(String id) async =>
      (plan: null, weeks: <PlanWeekRow>[], workouts: <PlanWorkoutRow>[]);

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
    String? raceListingId,
    PlanOverlapAction onOverlap = PlanOverlapAction.refuse,
  }) async {
    final call = _calls++;
    if (failOnCall.contains(call)) throw Exception('connection lost');
    created.add((
      name: name,
      start: toIsoDate(startDate),
      overlap: onOverlap,
      generated: generated,
    ));
    return _row('plan-$call', name, toIsoDate(startDate),
        toIsoDate(generated.endDate));
  }
}

TrainingPlanRow _row(String id, String name, String start, String end) =>
    TrainingPlanRow(
      id: id,
      userId: 'u',
      name: name,
      goalEvent: 'distance_full',
      goalDistanceM: 42195,
      startDate: parseIsoDate(start),
      endDate: parseIsoDate(end),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

const _richmond = SeasonRace(
    name: 'Richmond Marathon',
    date: '2026-11-14',
    distanceM: 42195,
    priority: SeasonRacePriority.a,
    goalTimeSec: 12600);
const _twoOceans = SeasonRace(
    name: 'Two Oceans',
    date: '2027-04-03',
    distanceM: 56000,
    priority: SeasonRacePriority.b,
    goalTimeSec: 21600);
const _comrades = SeasonRace(
    name: 'Comrades',
    date: '2027-06-13',
    distanceM: 87000,
    priority: SeasonRacePriority.a);

Widget _host(TrainingService t,
        Future<SeasonRequestResult> Function(String, String) request) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SeasonPlanScreen(
        training: t,
        loadAiAvailable: () async => true,
        requestSeasonRacesFn: request,
        todayIso: () => _today,
      ),
    );

Future<SeasonRequestResult> Function(String, String) _returns(
        List<SeasonRace> races,
        [List<String> assumptions = const []]) =>
    (_, __) async => SeasonRequestResult(races: races, assumptions: assumptions);

Future<void> _pumpScreen(WidgetTester tester, Widget host) async {
  await tester.binding.setSurfaceSize(const Size(800, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

Future<void> _describeAndPreview(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('season-describe')),
      'Richmond in November, Two Oceans in April, Comrades in June');
  await tester.pump();
  await tester.tap(find.byKey(const Key('season-find-races')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('season-preview')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unavailable season request leaves one race to fill in by hand',
      (tester) async {
    await _pumpScreen(
        tester,
        _host(_FakeTraining(), (_, __) async {
          throw const PlanRequestError(PlanRequestErrorKind.unavailable);
        }));
    await tester.enterText(
        find.byKey(const Key('season-describe')), 'Comrades in June');
    await tester.pump();
    await tester.tap(find.byKey(const Key('season-find-races')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('season-ai-error')), findsOneWidget);
    expect(find.textContaining("isn't available right now"), findsOneWidget);
    expect(find.byKey(const Key('season-name-0')), findsOneWidget);
    expect(find.byKey(const Key('season-name-1')), findsNothing);
    expect(find.text('A — goal race'), findsOneWidget);
    expect(find.byKey(const Key('season-preview-section')), findsNothing);
  });

  testWidgets('a consent refusal offers the AI disclosure', (tester) async {
    await _pumpScreen(
        tester,
        _host(_FakeTraining(), (_, __) async {
          throw const PlanRequestError(PlanRequestErrorKind.consent);
        }));
    await tester.enterText(
        find.byKey(const Key('season-describe')), 'Comrades in June');
    await tester.pump();
    await tester.tap(find.byKey(const Key('season-find-races')));
    await tester.pumpAndSettle();

    expect(find.textContaining('updated AI disclosure'), findsOneWidget);
    expect(find.text('Review the AI disclosure'), findsOneWidget);
  });

  testWidgets(
      'races found in a description preview as chained plans with the B race placed',
      (tester) async {
    await _pumpScreen(tester,
        _host(_FakeTraining(), _returns([_richmond, _twoOceans, _comrades])));
    await _describeAndPreview(tester);

    expect(find.byKey(const Key('season-ai-found')), findsOneWidget);
    expect(find.byKey(const Key('season-plan-0')), findsOneWidget);
    expect(find.byKey(const Key('season-plan-1')), findsOneWidget);
    expect(find.byKey(const Key('season-plan-2')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('season-plan-1')),
            matching: find.textContaining('B · Two Oceans')),
        findsOneWidget);
    expect(find.textContaining('Recovery after Richmond Marathon: 49 days'),
        findsOneWidget);
    expect(find.text('Create 2 plans'), findsOneWidget);
  });

  testWidgets('editing a race after the preview hides it', (tester) async {
    await _pumpScreen(tester,
        _host(_FakeTraining(), _returns([_richmond, _twoOceans, _comrades])));
    await _describeAndPreview(tester);
    expect(find.byKey(const Key('season-preview-section')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('season-name-1')), 'Two Oceans 56');
    await tester.pump();
    expect(find.byKey(const Key('season-preview-section')), findsNothing);
  });

  testWidgets('a season with no A race is refused with its reason',
      (tester) async {
    await _pumpScreen(tester, _host(_FakeTraining(), _returns([_twoOceans])));
    await _describeAndPreview(tester);

    expect(find.byKey(const Key('season-refusal')), findsOneWidget);
    expect(find.textContaining('Mark at least one race as A'), findsOneWidget);
    expect(find.byKey(const Key('season-create')), findsNothing);
  });

  testWidgets('create writes every plan in order, the B race inside the second',
      (tester) async {
    final t = _FakeTraining();
    await _pumpScreen(
        tester, _host(t, _returns([_richmond, _twoOceans, _comrades])));
    await _describeAndPreview(tester);
    await tester.tap(find.byKey(const Key('season-create')));
    await tester.pump();
    await tester.pump();

    expect([for (final c in t.created) (c.name, c.start, c.overlap)], [
      ('Richmond Marathon', '2026-08-16', PlanOverlapAction.refuse),
      ('Comrades', '2027-01-03', PlanOverlapAction.refuse),
    ]);
    expect(toIsoDate(t.created[0].generated.endDate), '2026-11-14');
    final tuneUp = [
      for (final w in t.created[1].generated.weeks)
        for (final x in w.workouts)
          if (x.kind == WorkoutKind.race) (toIsoDate(x.scheduledDate), x.raceName, x.racePriority)
    ];
    expect(tuneUp, [
      ('2027-04-03', 'Two Oceans', 'B'),
      ('2027-06-13', 'Comrades', 'A'),
    ]);
  });

  testWidgets('a failure part-way names what was created and retries the rest',
      (tester) async {
    final t = _FakeTraining(failOnCall: {1});
    await _pumpScreen(
        tester, _host(t, _returns([_richmond, _twoOceans, _comrades])));
    await _describeAndPreview(tester);
    await tester.tap(find.byKey(const Key('season-create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('season-create-error')), findsOneWidget);
    expect(
        find.textContaining(
            'Created: Richmond Marathon. Not created yet: Comrades'),
        findsOneWidget);
    expect(find.text('Create the remaining plans'), findsOneWidget);
    expect([for (final c in t.created) c.name], ['Richmond Marathon']);

    await tester.tap(find.byKey(const Key('season-create')));
    await tester.pump();
    await tester.pump();
    expect([for (final c in t.created) (c.name, c.overlap)], [
      ('Richmond Marathon', PlanOverlapAction.refuse),
      ('Comrades', PlanOverlapAction.refuse),
    ]);
  });

  testWidgets(
      'the first plan overlapping an active plan asks first and passes the choice to it alone',
      (tester) async {
    final t = _FakeTraining(
        active: [_row('old', 'Base block', '2026-08-01', '2026-09-30')]);
    await _pumpScreen(
        tester, _host(t, _returns([_richmond, _twoOceans, _comrades])));
    await _describeAndPreview(tester);
    await tester.tap(find.byKey(const Key('season-create')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.created, isEmpty);
    await tester.tap(find.byKey(const Key('planOverlapReplace')));
    await tester.pump();
    await tester.pump();

    expect([for (final c in t.created) (c.name, c.overlap)], [
      ('Richmond Marathon', PlanOverlapAction.replace),
      ('Comrades', PlanOverlapAction.refuse),
    ]);
  });

  testWidgets(
      'a later plan overlapping an active plan blocks the season before anything is written',
      (tester) async {
    final t = _FakeTraining(
        active: [_row('old', 'Winter base', '2027-02-01', '2027-03-01')]);
    await _pumpScreen(
        tester, _host(t, _returns([_richmond, _twoOceans, _comrades])));
    await _describeAndPreview(tester);
    await tester.tap(find.byKey(const Key('season-create')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.textContaining(
            'Comrades would overlap your plan Winter base. Nothing was created'),
        findsOneWidget);
    expect(t.created, isEmpty);
  });

  testWidgets('races can be added and removed by hand', (tester) async {
    await _pumpScreen(tester, _host(_FakeTraining(), _returns(const [])));
    expect(find.byKey(const Key('season-no-races')), findsOneWidget);
    await tester.tap(find.byKey(const Key('season-add-race')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('season-add-race')));
    await tester.pump();
    expect(find.text('Race 2'), findsOneWidget);
    expect(find.text('B — tune-up'), findsOneWidget);
    await tester.tap(find.byKey(const Key('season-remove-1')));
    await tester.pump();
    expect(find.text('Race 2'), findsNothing);

    await tester.tap(find.byKey(const Key('season-preview')));
    await tester.pump();
    expect(find.byKey(const Key('season-row-error')), findsOneWidget);
  });

  testWidgets(
      'each assumption the request made gets its own line, unknown ones skipped',
      (tester) async {
    await _pumpScreen(
        tester,
        _host(
            _FakeTraining(),
            _returns([_richmond, _comrades],
                ['race_date_next_year', 'priority_default', 'not_a_key'])));
    await tester.enterText(
        find.byKey(const Key('season-describe')), 'Richmond and Comrades');
    await tester.pump();
    await tester.tap(find.byKey(const Key('season-find-races')));
    await tester.pumpAndSettle();

    final found = find.byKey(const Key('season-ai-found'));
    expect(
        find.descendant(
            of: found,
            matching: find.text(
                '• A date given without a year had already passed this year, so it was moved to next year.')),
        findsOneWidget);
    expect(
        find.descendant(
            of: found,
            matching: find.text('• Races without a priority were set to B.')),
        findsOneWidget);
    expect(find.textContaining('not_a_key'), findsNothing);
    expect(
        tester.widget<TextField>(find.byKey(const Key('season-name-0'))).controller!.text,
        'Richmond Marathon');
    expect(
        tester.widget<TextField>(find.byKey(const Key('season-goal-0'))).controller!.text,
        '3:30:00');
    expect(
        tester.widget<TextField>(find.byKey(const Key('season-name-1'))).controller!.text,
        'Comrades');
  });

  testWidgets(
      'a request that found no races explains why and leaves a race to fill in',
      (tester) async {
    await _pumpScreen(tester,
        _host(_FakeTraining(), _returns(const [], ['race_dropped_distance'])));
    await tester.enterText(
        find.byKey(const Key('season-describe')), 'A 2 km fun run');
    await tester.pump();
    await tester.tap(find.byKey(const Key('season-find-races')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No races could be found'), findsOneWidget);
    expect(
        find.text(
            '• A race was left out because its distance is outside what the planner supports (5 km to 400 km).'),
        findsOneWidget);
    expect(find.byKey(const Key('season-name-0')), findsOneWidget);
    expect(find.byKey(const Key('season-name-1')), findsNothing);
    expect(
        tester.widget<TextField>(find.byKey(const Key('season-name-0'))).controller!.text,
        '');
  });

  testWidgets('a 56 km + 90 km season previews as two chained plans',
      (tester) async {
    await _pumpScreen(
        tester,
        _host(
            _FakeTraining(),
            _returns(const [
              SeasonRace(
                  name: 'Two Oceans',
                  date: '2027-04-03',
                  distanceM: 56000,
                  priority: SeasonRacePriority.a),
              SeasonRace(
                  name: 'Comrades',
                  date: '2027-06-13',
                  distanceM: 90000,
                  priority: SeasonRacePriority.a),
            ])));
    await _describeAndPreview(tester);

    expect(find.byKey(const Key('season-refusal')), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('season-plan-0')),
            matching: find.text('Two Oceans')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('season-plan-1')),
            matching: find.text('Comrades')),
        findsOneWidget);
    expect(find.textContaining('16 weeks'), findsOneWidget);
    expect(find.textContaining('8 weeks'), findsOneWidget);
    expect(find.textContaining('Recovery after Two Oceans: 21 days'),
        findsOneWidget);
    expect(find.text('Create 2 plans'), findsOneWidget);
  });
}
