import 'dart:async';
import 'dart:io' show SocketException;

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton, TextLane;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/date_format.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coaching_athlete_screen.dart';
import '../lib/training_service.dart';

class _FakeApi extends ApiClient {
  _FakeApi({
    this.runs = const [],
    this.overview,
    this.plans = const [],
    this.assignError,
    this.assignOverlap = false,
    this.overviewAfterRefusal,
    this.loadError,
    this.mapEnabled = false,
  });

  final List<AthleteRunSummary> runs;
  AthletePlanOverview? overview;
  final List<TrainingPlanRow> plans;
  final String? assignError;

  /// Refuse the assignment the way the server does for an overlap (23P01).
  final bool assignOverlap;

  /// What the overview re-read returns after an overlap refusal.
  final AthletePlanOverview? overviewAfterRefusal;
  DateTime? lastAssignedStart;
  final Object? loadError;
  final bool mapEnabled;

  String? lastAssignedPlanId;
  final List<String> clipped = [];

  @override
  Future<bool> coachRunMapEnabled() async => mapEnabled;

  @override
  Future<List<Waypoint>> fetchClippedTrackForRun(String runId) async {
    clipped.add(runId);
    return const [
      Waypoint(lat: -33.87, lng: 151.22),
      Waypoint(lat: -33.88, lng: 151.23),
      Waypoint(lat: -33.89, lng: 151.24),
    ];
  }

  @override
  String? get userId => 'coach-1';

  @override
  Future<List<AthleteRunSummary>> fetchAthleteRuns(String athleteId,
          {int limit = 20}) async {
    if (loadError != null) throw loadError!;
    return runs;
  }

  @override
  Future<AthletePlanOverview?> fetchAthletePlanOverview(
    String athleteId, {
    required TrainingPlanRow? Function(List<TrainingPlanRow> activePlans) pick,
  }) async =>
      overview;

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans({int limit = 100}) async => plans;

  @override
  Future<String> assignPlanToAthlete({
    required String sourcePlanId,
    required String athleteId,
    required DateTime startDate,
    String? Function(DateTime)? toIso,
  }) async {
    lastAssignedStart = startDate;
    if (assignOverlap) {
      if (overviewAfterRefusal != null) overview = overviewAfterRefusal;
      throw const PlanAssignOverlapException(
          'assign_plan_to_athlete: these dates overlap the athlete\'s active plan');
    }
    if (assignError != null) throw Exception(assignError);
    lastAssignedPlanId = sourcePlanId;
    return 'new-plan';
  }
}

TrainingPlanRow _plan(String id, String name, {String? assignedBy}) =>
    TrainingPlanRow(
      id: id,
      userId: 'coach-1',
      name: name,
      goalEvent: 'marathon',
      goalDistanceM: 42195,
      startDate: DateTime.utc(2026, 1, 1),
      endDate: DateTime.utc(2026, 3, 1),
      daysPerWeek: 5,
      status: 'active',
      source: 'app',
      isTemplate: false,
      isPublicTemplate: false,
      assignedByCoachId: assignedBy,
    );

DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

/// An athlete plan dated relative to today.
TrainingPlanRow _athletePlan(String id, String name, int startOffset, int endOffset) =>
    TrainingPlanRow(
      id: id,
      userId: 'a1',
      name: name,
      goalEvent: 'distance_10k',
      goalDistanceM: 10000,
      startDate: _day(startOffset),
      endDate: _day(endOffset),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

/// A 28-day coach source plan.
TrainingPlanRow _sourcePlan() => TrainingPlanRow(
      id: 'src',
      userId: 'coach-1',
      name: 'Base Builder',
      goalEvent: 'distance_10k',
      goalDistanceM: 10000,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 28),
      daysPerWeek: 4,
      status: 'completed',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

AthletePlanOverview _overviewOf(TrainingPlanRow shown, List<TrainingPlanRow> active) =>
    AthletePlanOverview(
      plan: shown,
      weeks: const [],
      workouts: const [],
      completionPct: 0,
      activePlans: active,
    );

/// Every value of the `workout_kind` postgres enum except 'rest', which
/// `_focusWorkouts` filters out before any row is built.
const _kindsInEnum = [
  'easy',
  'long',
  'recovery',
  'tempo',
  'interval',
  'marathon_pace',
  'race',
  'walk_run',
];

/// Half the kinds dated before today and half after, so the ±4/+6 focus
/// window around the pivot admits every one of them.
List<PlanWorkoutRow> _oneWorkoutPerKind() {
  final today = DateTime.now();
  final half = _kindsInEnum.length ~/ 2;
  return [
    for (var i = 0; i < _kindsInEnum.length; i++)
      PlanWorkoutRow(
        id: 'w$i',
        weekId: 'wk1',
        scheduledDate: today.add(Duration(days: i < half ? i - half : i - half + 1)),
        kind: _kindsInEnum[i],
        manuallyCompleted: false,
      ),
  ];
}

AthleteRunSummary _run(String id) => AthleteRunSummary(
      id: id,
      startedAt: DateTime.utc(2026, 1, 10, 7),
      distanceM: 10000,
      durationS: 3000,
      isPublic: true,
      source: 'app',
      routeId: null,
      activityType: 'run',
      metadata: null,
    );

AthleteRunSummary _trackedRun(String id) => AthleteRunSummary(
      id: id,
      startedAt: DateTime.utc(2026, 1, 11, 7),
      distanceM: 8000,
      durationS: 2400,
      isPublic: false,
      source: 'app',
      routeId: null,
      activityType: 'run',
      metadata: null,
      trackUrl: 'a1/$id.json.gz',
    );

AthleteRunSummary _strollerRun() => AthleteRunSummary(
      id: 'r-stroller',
      startedAt: DateTime.utc(2026, 3, 28, 7),
      distanceM: 10000,
      durationS: 3000,
      isPublic: true,
      source: 'app',
      routeId: null,
      activityType: 'stroller',
      metadata: null,
    );

/// Never resolves the runs fetch, so the loading frame is observable.
class _HangingApi extends ApiClient {
  @override
  String? get userId => 'coach-1';

  @override
  Future<List<AthleteRunSummary>> fetchAthleteRuns(String athleteId,
          {int limit = 20}) =>
      Completer<List<AthleteRunSummary>>().future;

  @override
  Future<AthletePlanOverview?> fetchAthletePlanOverview(
    String athleteId, {
    required TrainingPlanRow? Function(List<TrainingPlanRow> activePlans) pick,
  }) async =>
      null;

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans({int limit = 100}) async => const [];
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  Preferences prefs, {
  Locale? locale,
  TrainingService? training,
  bool? hrPrescription,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachingAthleteScreen(
        api: api,
        preferences: prefs,
        athleteId: 'a1',
        displayName: 'Alice Runner',
        acceptedAt: DateTime.utc(2026, 1, 2),
        training: training,
        hrPrescription: hrPrescription,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _EditTraining extends TrainingService {
  String? editedId;
  PlanWorkoutRange? rpe;

  @override
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    String? fromKind,
    PlanWorkoutTargets? targets,
    String? notes,
    PlanWorkoutRaceFields? race,
    PlanWorkoutRange? rpe,
    PlanWorkoutRange? hr,
  }) async {
    editedId = workoutId;
    this.rpe = rpe;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('the loading frame stands card blocks, not a bare spinner',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, _HangingApi(), prefs);
    expect(find.byType(ListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('shows recent runs and the no-plan empty state', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(runs: [_run('r1')]);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text('Alice Runner'), findsWidgets);
    // No active plan AND no coach plans → the "create a plan first" hint
    // (mirrors web's `assignNoPlans` branch).
    expect(find.text(l10n.coachingAthleteAssignNoPlans), findsOneWidget);
    expect(find.text(l10n.coachingAthleteRecentRuns), findsOneWidget);
  });

  testWidgets(
      'with the coach map gate open, a tracked run draws its map through the '
      'clipped non-owner path', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(runs: [_trackedRun('t1'), _run('r1')], mapEnabled: true);
    await _pump(tester, api, prefs);
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byKey(const ValueKey('coach-run-map-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('coach-run-map-r1')), findsNothing);
    expect(find.text(l10n.coachingAthleteMapsClippedNote), findsOneWidget);
    expect(api.clipped, ['t1']);
  });

  testWidgets('with the gate closed no map is drawn and nothing is fetched',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(runs: [_trackedRun('t1')]);
    await _pump(tester, api, prefs);
    await tester.pump();
    expect(find.byKey(const ValueKey('coach-run-map-t1')), findsNothing);
    expect(api.clipped, isEmpty);
  });

  testWidgets('offers the assign control when the coach has plans and the '
      'athlete has none', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(plans: [_plan('p1', 'Base Builder')]);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingAthleteAssignTitle), findsOneWidget);
    expect(find.text(l10n.coachingAthleteAssignButton), findsOneWidget);
  });

  Future<void> pickSourceAndAssign(WidgetTester tester, AppLocalizations l10n) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Base Builder').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.coachingAthleteAssignButton));
    await tester.tap(find.text(l10n.coachingAthleteAssignButton));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'an athlete with an active plan still gets the assign control, naming '
      'the plan and starting the picker after it', (tester) async {
    final prefs = await _prefs();
    final own = _athletePlan('own', 'Spring Half', -5, 20);
    final api = _FakeApi(plans: [_sourcePlan()], overview: _overviewOf(own, [own]));
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingAthleteAssignTitle), findsOneWidget);
    expect(
        find.text(l10n.coachingAthleteAssignAfterOne('Alice Runner', 'Spring Half',
            formatDateMed(_day(20), 'en'))),
        findsOneWidget);
    expect(find.text(formatDateMed(_day(21), 'en')), findsOneWidget);

    await pickSourceAndAssign(tester, l10n);
    expect(api.lastAssignedPlanId, 'src');
    expect(api.lastAssignedStart, _day(21));
  });

  testWidgets(
      'a current and a queued plan are both named and the picker starts after '
      'the queued one', (tester) async {
    final prefs = await _prefs();
    final own = _athletePlan('own', 'Spring Half', -5, 20);
    final queued = _athletePlan('q', 'Autumn Full', 30, 60);
    final api = _FakeApi(plans: [_sourcePlan()], overview: _overviewOf(own, [queued, own]));
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
        find.text(l10n.coachingAthleteAssignAfterTwo(
          'Alice Runner',
          'Spring Half',
          formatDateMed(_day(20), 'en'),
          'Autumn Full',
          formatDateMed(_day(30), 'en'),
          formatDateMed(_day(60), 'en'),
        )),
        findsOneWidget);
    expect(find.text(formatDateMed(_day(61), 'en')), findsOneWidget);
  });

  testWidgets(
      'an overlap refusal re-reads the athlete\'s plans and names the one in '
      'the way', (tester) async {
    final prefs = await _prefs();
    final appeared = _athletePlan('new', 'Surprise 10K', 10, 40);
    final api = _FakeApi(
      plans: [_sourcePlan()],
      assignOverlap: true,
      overviewAfterRefusal: _overviewOf(appeared, [appeared]),
    );
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pickSourceAndAssign(tester, l10n);
    await tester.pump();
    expect(
        find.text(l10n.coachingAthleteAssignOverlapNamed('Alice Runner',
            'Surprise 10K', formatDateMed(_day(10), 'en'), formatDateMed(_day(40), 'en'))),
        findsOneWidget);
    expect(find.textContaining('assign_plan_to_athlete'), findsNothing);
    expect(find.textContaining('try again'), findsNothing);
  });

  testWidgets(
      'with three plans ahead every one is named and the picker starts after '
      'the last', (tester) async {
    final prefs = await _prefs();
    final own = _athletePlan('own', 'Spring Half', -5, 20);
    final queued = _athletePlan('q', 'Autumn Full', 21, 50);
    final third = _athletePlan('t', 'Winter Ultra', 60, 90);
    final api = _FakeApi(
        plans: [_sourcePlan()], overview: _overviewOf(own, [third, own, queued]));
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
        find.text(l10n.coachingAthleteAssignAfterMany('Alice Runner', 3,
            'Spring Half, Autumn Full, Winter Ultra', formatDateMed(_day(90), 'en'))),
        findsOneWidget);
    expect(find.text(formatDateMed(_day(91), 'en')), findsOneWidget);
  });

  testWidgets(
      'a refusal names the plan in the way even when it is neither the one '
      'shown nor the one after it', (tester) async {
    final prefs = await _prefs();
    final shown = _athletePlan('a', 'Shown Block', 40, 60);
    final after = _athletePlan('b', 'After Block', 70, 90);
    final early = _athletePlan('c', 'Early Block', 5, 30);
    final api = _FakeApi(
      plans: [_sourcePlan()],
      assignOverlap: true,
      overviewAfterRefusal: _overviewOf(shown, [shown, after, early]),
    );
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pickSourceAndAssign(tester, l10n);
    await tester.pump();
    expect(
        find.text(l10n.coachingAthleteAssignOverlapNamed('Alice Runner',
            'Early Block', formatDateMed(_day(5), 'en'), formatDateMed(_day(30), 'en'))),
        findsOneWidget);
  });

  testWidgets('an overlap refusal it cannot attribute still says what to do',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(plans: [_sourcePlan()], assignOverlap: true);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pickSourceAndAssign(tester, l10n);
    await tester.pump();
    expect(find.text(l10n.coachingAthleteAssignOverlap('Alice Runner')),
        findsOneWidget);
  });

  testWidgets('shows the assigned-by-you badge for a plan the coach assigned',
      (tester) async {
    final prefs = await _prefs();
    final plan = _plan('p1', 'My Plan', assignedBy: 'coach-1');
    final overview = AthletePlanOverview(
      plan: plan,
      weeks: const [],
      workouts: const [],
      completionPct: 0,
    );
    await _pump(tester, _FakeApi(overview: overview), prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingAthleteAssignedByYou), findsOneWidget);
  });

  testWidgets('a past skipped workout reads Skipped, not Missed, and is off '
      'the books', (tester) async {
    final prefs = await _prefs();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final overview = AthletePlanOverview(
      plan: _plan('p1', 'My Plan'),
      weeks: const [],
      workouts: [
        PlanWorkoutRow(
          id: 'skipped',
          weekId: 'wk1',
          scheduledDate: yesterday,
          kind: 'easy',
          manuallyCompleted: false,
          skippedAt: yesterday,
        ),
        PlanWorkoutRow(
          id: 'missed',
          weekId: 'wk1',
          scheduledDate: yesterday,
          kind: 'tempo',
          manuallyCompleted: false,
        ),
      ],
      completionPct: 0,
    );
    await _pump(tester, _FakeApi(overview: overview), prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingAthleteStatusSkipped), findsOneWidget);
    expect(find.text(l10n.coachingAthleteStatusMissed), findsOneWidget);
    expect(
      find.textContaining(l10n.coachingAthleteDoneCount(0, 1), findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(l10n.coachingAthleteMissedCount(1), findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets(
      'a workout row shows its effort targets and opens the edit sheet for '
      'the coach (decisions § 2092)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await _prefs();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final overview = AthletePlanOverview(
      plan: _plan('p1', 'My Plan'),
      weeks: const [],
      workouts: [
        PlanWorkoutRow(
          id: 'easy-1',
          weekId: 'wk1',
          scheduledDate: tomorrow,
          kind: 'easy',
          targetRpeMin: 3,
          targetRpeMax: 4,
          targetHrMaxBpm: 125,
          manuallyCompleted: false,
        ),
      ],
      completionPct: 0,
    );
    final training = _EditTraining();
    await _pump(tester, _FakeApi(overview: overview), prefs,
        training: training, hrPrescription: true);
    expect(find.textContaining('Effort 3–4/10 · Cap 125 bpm'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coachWorkoutRow-easy-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('workoutEditRpeMax')), '5');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(training.editedId, 'easy-1');
    expect(training.rpe, (min: 3, max: 5));
  });

  testWidgets('every workout kind renders the catalogue label, not the raw '
      'db value', (tester) async {
    final prefs = await _prefs();
    final overview = AthletePlanOverview(
      plan: _plan('p1', 'My Plan', assignedBy: 'coach-1'),
      weeks: const [],
      workouts: _oneWorkoutPerKind(),
      completionPct: 0,
    );
    await _pump(tester, _FakeApi(overview: overview), prefs,
        locale: const Locale('fr'));
    final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
    for (final label in [
      l10n.workoutKindEasy,
      l10n.workoutKindLong,
      l10n.workoutKindRecovery,
      l10n.workoutKindTempo,
      l10n.workoutKindInterval,
      l10n.workoutKindMarathonPace,
      l10n.workoutKindRace,
      l10n.workoutKindWalkRun,
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing "$label"');
    }
    // The two db values whose hand-capitalised form collides with no
    // catalogue label in any locale, so their absence proves the raw
    // capitaliser is gone rather than merely shadowed.
    expect(find.text('Marathon pace'), findsNothing);
    expect(find.text('Walk run'), findsNothing);
  });

  testWidgets('surfaces the assign RPC raise as a banner (no swallow)',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      plans: [_plan('p1', 'Base Builder')],
      assignError: 'athlete already has an active plan',
    );
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Pick the plan, then assign.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Base Builder').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.coachingAthleteAssignButton));
    await tester.pump();
    await tester.pump();

    expect(find.text('athlete already has an active plan'), findsOneWidget);
  });

  testWidgets(
      'shows friendly, localized copy (not the raw exception) when the '
      'athlete load fails', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      loadError: const SocketException("Failed host lookup: 'xyz.supabase.co'"),
    );
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l10n.coachingAthleteLoadError(l10n.authErrorOffline)),
        findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('Exception:'), findsNothing);

  });

  group('CoachingAthleteScreen — the run-row lanes', () {
    // The run row leads with a 84px date box and a 64px activity box.
    // Portuguese "28 de mar." needs 98.2px in real Roboto at bodySmall by
    // 1.5x and 130.9 at 2x; the activity label ("Stroller", the widest of the
    // five activity types) needs 69.3 then 92.4 at bodyMedium w600 against 64.
    // The activity label has no break opportunity, so it painted over the
    // distance/duration/pace summary beside it.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so lanes whose floors track
    // the scale here track it on a device too.
    Future<void> pumpRuns(WidgetTester tester, {double scale = 1.0}) async {
      final prefs = await _prefs();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: CoachingAthleteScreen(
            // 'stroller' is the widest of the five activity types, and the
            // label is not localized — English is the only case there is.
            api: _FakeApi(runs: [_strollerRun()]),
            preferences: prefs,
            athleteId: 'a1',
            displayName: 'Alice Runner',
            acceptedAt: DateTime.utc(2026, 1, 2),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('each lane widens to its label instead of overpainting',
        (tester) async {
      await pumpRuns(tester);
      final lanes = find.byType(TextLane);
      expect(lanes, findsWidgets);
      for (var i = 0; i < lanes.evaluate().length; i++) {
        final lane = lanes.at(i);
        final para = tester.renderObject<RenderParagraph>(
            find.descendant(of: lane, matching: find.byType(Text)).first);
        expect(
          tester.getSize(lane).width,
          greaterThanOrEqualTo(para.getMaxIntrinsicWidth(double.infinity)),
          reason: 'lane $i cropped its label',
        );
      }
    });

    testWidgets('the lane floors grow with the OS text scale', (tester) async {
      await pumpRuns(tester, scale: 2.0);
      final lanes = find.byType(TextLane);
      expect(lanes, findsWidgets);
      for (var i = 0; i < lanes.evaluate().length; i++) {
        final declared = tester.widget<TextLane>(lanes.at(i)).width;
        expect(tester.getSize(lanes.at(i)).width,
            greaterThanOrEqualTo(declared * 2),
            reason: 'lane $i did not double with the scale');
      }
    });
  });
}
