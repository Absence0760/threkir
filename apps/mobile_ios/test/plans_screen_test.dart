import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState, ListSkeleton, ProgressBar;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_labels.dart' show starterStartDate;
import '../lib/screens/plan_library_screen.dart';
import '../lib/screens/plans_screen.dart';
import '../lib/training.dart';
import '../lib/plan_calibration.dart';
import '../lib/training_service.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/plan_list_card.dart';
import '../lib/widgets/sign_in_required_state.dart';

Future<void> _pump(WidgetTester tester, {required TrainingService training}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlansScreen(training: training, apiClient: null),
    ),
  );
}

class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'u';
}

class _FakeTraining extends TrainingService {
  _FakeTraining(this.plans, {this.throwOnUpdate = false});
  List<TrainingPlanRow> plans;
  final bool throwOnUpdate;
  Object? loadError;
  int fetchCalls = 0;
  int updateCalls = 0;
  String? lastUpdateStatus;
  String? lastUpdateId;
  final deleted = <String>[];
  ({String name, DateTime start, int days, GoalEvent goal})? created;

  /// Holds the starter create open until completed, when set.
  Completer<void>? createGate;

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async {
    fetchCalls++;
    final e = loadError;
    if (e != null) throw e;
    return plans;
  }

  /// Holds the status write open until completed, when set.
  Completer<void>? updateGate;

  @override
  Future<void> updateStatus(String id, String status) async {
    updateCalls++;
    lastUpdateId = id;
    lastUpdateStatus = status;
    await updateGate?.future;
    if (throwOnUpdate) throw Exception('boom');
  }

  @override
  Future<void> deletePlan(String id) async {
    deleted.add(id);
    plans = plans.where((p) => p.id != id).toList();
  }

  @override
  Future<PlanCalibration> fetchPlanCalibration() async =>
      PlanCalibration.unknown;

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
    created = (name: name, start: startDate, days: daysPerWeek, goal: goalEvent);
    await createGate?.future;
    return _plan('new', name, 'active', startDate, generated.endDate);
  }

  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async =>
          (plan: null, weeks: const <PlanWeekRow>[], workouts: const <PlanWorkoutRow>[]);
}

TrainingPlanRow _plan(
  String id,
  String name,
  String status,
  DateTime start,
  DateTime end, {
  String goalEvent = 'distance_half',
  int? goalTimeSeconds,
  double? vdot,
}) =>
    TrainingPlanRow(
      id: id,
      userId: 'u',
      name: name,
      goalEvent: goalEvent,
      goalDistanceM: 21097,
      startDate: start,
      endDate: end,
      daysPerWeek: 4,
      status: status,
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
      goalTimeSeconds: goalTimeSeconds,
      vdot: vdot,
    );

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime _days(int d) {
  final t = _today();
  return DateTime(t.year, t.month, t.day + d);
}

/// An active plan 15 days in: week 3 of 12, with 68 days to go.
TrainingPlanRow _activePlan({int? goalTimeSeconds, double? vdot}) => _plan(
    'p1', 'Richmond Half', 'active', _days(-15), _days(68),
    goalTimeSeconds: goalTimeSeconds, vdot: vdot);

/// An active plan that starts [days] from today — queued behind the current one.
TrainingPlanRow _queuedPlan(int days) =>
    _plan('p2', 'Comrades block', 'active', _days(days), _days(days + 120),
        goalEvent: 'distance_full');

Future<void> _pumpSignedIn(WidgetTester tester, _FakeTraining training,
    {double textScale = 1.0}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PlansScreen(training: training, apiClient: _SignedInApi()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Tall enough that a ListView builds every card the test names.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(PlanListCard));

void main() {
  group('PlansScreen — not signed in', () {
    testWidgets('pushed on its own, its app bar says Plans, the tab\'s name',
        (tester) async {
      await _pump(tester, training: TrainingService());
      await tester.pump();
      expect(find.widgetWithText(AppBar, 'Plans'), findsOneWidget);
    });

    testWidgets('shows the shared sign-in state', (tester) async {
      await _pump(tester, training: TrainingService());
      await tester.pump();
      expect(find.byType(SignInRequiredState), findsOneWidget);
    });

    testWidgets('offers no New plan or library action', (tester) async {
      await _pump(tester, training: TrainingService());
      await tester.pump();
      expect(find.text('New plan'), findsNothing);
      expect(find.text('Browse library'), findsNothing);
    });

    testWidgets('does not render a loading treatment over the sign-in state',
        (tester) async {
      // Reason: the not-signed-in branch must short-circuit BEFORE the
      // _loading flag has a chance to surface a loading treatment.
      await _pump(tester, training: TrainingService());
      await tester.pump();
      expect(find.byType(ListSkeleton), findsNothing);
    });
  });

  group('PlansScreen — load states', () {
    testWidgets('a failed load shows the error state, and retry reloads',
        (tester) async {
      final training = _FakeTraining([_activePlan()])
        ..loadError = Exception('offline');
      await _pumpSignedIn(tester, training);
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text("Couldn't load training plans. Tap retry to try again."),
          findsOneWidget);

      training.loadError = null;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Richmond Half'), findsOneWidget);
    });

    testWidgets('a timed-out load says so', (tester) async {
      final training = _FakeTraining([])
        ..loadError = TimeoutException('slow');
      await _pumpSignedIn(tester, training);
      expect(find.text('Connection timed out. Check your network and try again.'),
          findsOneWidget);
    });

    testWidgets('pull to refresh fetches again', (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);
      final before = training.fetchCalls;
      await tester.fling(find.text('Richmond Half'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(training.fetchCalls, greaterThan(before));
    });

    // The list reloads on every TrainingService change, so one blip used to
    // swap a loaded list for the full error page.
    testWidgets('a failed refresh keeps the plans on screen under a banner',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);
      expect(find.text('Richmond Half'), findsOneWidget);

      training.loadError = Exception('boom');
      await tester.fling(find.text('Richmond Half'), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Richmond Half'), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.commonStaleRefreshFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('PlansScreen — cards', () {
    testWidgets('an active card names its status, goal, target and week',
        (tester) async {
      final training = _FakeTraining([_activePlan(vdot: 45.2)]);
      await _pumpSignedIn(tester, training);
      final card = _card('Richmond Half');
      expect(find.descendant(of: card, matching: find.text('active')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Goal')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Half marathon')),
          findsOneWidget);
      // No goal time: the target is simply to finish.
      expect(find.descendant(of: card, matching: find.text('Finish')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('45.2')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Week 3 of 12')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(ProgressBar)),
          findsOneWidget);
      // Dates are localized, not ISO.
      expect(
          find.descendant(
              of: card, matching: find.textContaining(RegExp(r'\d{4}-\d{2}'))),
          findsNothing);
    });

    testWidgets('the card reads as one composed label to a screen reader',
        (tester) async {
      final handle = tester.ensureSemantics();
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);
      expect(
        find.bySemanticsLabel(RegExp(
            r'^Richmond Half, active, Goal: Half marathon, Target: Finish, .*Week 3 of 12')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an active plan that starts after today reads as upcoming',
        (tester) async {
      final training = _FakeTraining([_activePlan(), _queuedPlan(30)]);
      await _pumpSignedIn(tester, training);
      expect(find.byKey(const Key('planTileUpcoming')), findsOneWidget);
      expect(find.text('upcoming'), findsOneWidget);
      expect(find.text('Starts in 30 days'), findsOneWidget);
    });

    testWidgets('each card carries exactly one action', (tester) async {
      _tallView(tester);
      final training = _FakeTraining([
        _activePlan(),
        _plan('p3', 'Spring 10K', 'paused', _days(-30), _days(20)),
        _plan('p4', 'Old marathon', 'completed', _days(-200), _days(-90)),
      ]);
      await _pumpSignedIn(tester, training);
      for (final name in ['Richmond Half', 'Spring 10K']) {
        expect(find.descendant(of: _card(name), matching: find.text('Abandon')),
            findsOneWidget);
        expect(find.descendant(of: _card(name), matching: find.text('Delete')),
            findsNothing);
      }
      expect(
          find.descendant(of: _card('Old marathon'), matching: find.text('Delete')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _card('Old marathon'), matching: find.text('Abandon')),
          findsNothing);
    });

    testWidgets('the list runs active, paused, completed, abandoned',
        (tester) async {
      _tallView(tester);
      // fetchMyPlans orders by created_at desc, so the newest — abandoned —
      // plan arrives first.
      final training = _FakeTraining([
        _plan('a', 'Abandoned one', 'abandoned', _days(-5), _days(80)),
        _plan('c', 'Completed one', 'completed', _days(-200), _days(-90)),
        _plan('p', 'Paused one', 'paused', _days(-30), _days(20)),
        _activePlan(),
      ]);
      await _pumpSignedIn(tester, training);
      final ys = [
        for (final n in ['Richmond Half', 'Paused one', 'Completed one', 'Abandoned one'])
          tester.getTopLeft(find.text(n)).dy,
      ];
      expect(ys, [...ys]..sort());
    });

    testWidgets('the status filter narrows the list and shows counts',
        (tester) async {
      final training = _FakeTraining([
        _activePlan(),
        _plan('p', 'Paused one', 'paused', _days(-30), _days(20)),
      ]);
      await _pumpSignedIn(tester, training);
      expect(find.text('All · 2'), findsOneWidget);
      await tester.tap(find.text('Paused · 1'));
      await tester.pump();
      expect(find.text('Paused one'), findsOneWidget);
      expect(find.text('Richmond Half'), findsNothing);

      await tester.tap(find.text('Completed'));
      await tester.pump();
      expect(find.text('No completed plans.'), findsOneWidget);
      await tester.tap(find.text('Show all plans'));
      await tester.pump();
      expect(find.text('Richmond Half'), findsOneWidget);
    });

    testWidgets('a card does not overflow at 2.0x text on a narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final training = _FakeTraining([
        _activePlan(goalTimeSeconds: 6300, vdot: 48.3),
        _queuedPlan(30),
      ]);
      await _pumpSignedIn(tester, training, textScale: 2.0);
      expect(tester.takeException(), isNull);
      // Both are active, so the later start (the queued plan) leads.
      expect(find.text('Comrades block'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Richmond Half'), 300,
          scrollable: find.byType(Scrollable).last);
      expect(tester.takeException(), isNull);
    });
  });

  group('PlansScreen — actions', () {
    testWidgets('Browse library is a labelled button that opens the library',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Browse library'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanLibraryScreen), findsOneWidget);
    });

    testWidgets('deleting a finished plan confirms, deletes and reloads',
        (tester) async {
      // Tall, so the New plan FAB floats clear of the second card's Delete.
      _tallView(tester);
      final training = _FakeTraining([
        _plan('p4', 'Old marathon', 'completed', _days(-200), _days(-90)),
        _activePlan(),
      ]);
      await _pumpSignedIn(tester, training);
      final before = training.fetchCalls;
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(training.deleted, isEmpty);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Delete')));
      await tester.pumpAndSettle();
      expect(training.deleted, ['p4']);
      expect(training.fetchCalls, greaterThan(before));
      expect(find.text('Old marathon'), findsNothing);
    });

    testWidgets('a paused plan can be abandoned from the list', (tester) async {
      final training = _FakeTraining(
          [_plan('p3', 'Spring 10K', 'paused', _days(-30), _days(20))]);
      await _pumpSignedIn(tester, training);
      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pumpAndSettle();
      expect(training.lastUpdateId, 'p3');
      expect(training.lastUpdateStatus, 'abandoned');
    });
  });

  group('PlansScreen — abandon confirm', () {
    testWidgets('abandoning asks first, and says what is kept',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Abandon "Richmond Half"?'), findsOneWidget);
      expect(
          find.text(
              'Its weeks, workouts and linked runs are kept. You can create a new plan after.'),
          findsOneWidget);
      expect(training.updateCalls, 0);
    });

    testWidgets('cancelling the abandon dialog is a no-op', (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(training.updateCalls, 0);
    });

    testWidgets('confirming the abandon dialog updates the status',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pumpAndSettle();

      expect(training.updateCalls, 1);
      expect(training.lastUpdateStatus, 'abandoned');
    });

    // The list's Abandon used a FilledButton confirm of its own while plan
    // detail used confirmDestructive; one action, one confirm.
    testWidgets('Abandon confirms with the destructive dialog plan detail uses',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);
      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();

      final confirm = find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon'));
      expect(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
          findsNothing);
      final button = tester.widget<TextButton>(
          find.ancestor(of: confirm, matching: find.byType(TextButton)));
      final context = tester.element(confirm);
      expect(button.style?.foregroundColor?.resolve({}),
          Theme.of(context).colorScheme.error);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('an abandon in flight holds every card and spins on its own',
        (tester) async {
      _tallView(tester);
      final gate = Completer<void>();
      final training = _FakeTraining([
        _activePlan(),
        _plan('p2', 'Old 10K', 'completed', _days(-90), _days(-30)),
      ])
        ..updateGate = gate;
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      ButtonStyleButton action(String key) =>
          tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
      expect(action('planCardAbandon').onPressed, isNull);
      expect(action('planCardDelete').onPressed, isNull);
      expect(
          find.descendant(
              of: _card('Richmond Half'),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('planCardDelete')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(training.updateCalls, 1);

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('an abandon the backend never answers gives up and says so',
        (tester) async {
      final training = _FakeTraining([_activePlan()])
        ..updateGate = Completer<void>();
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining("Couldn't update the plan"), findsNothing);

      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a failed abandon surfaces a banner', (tester) async {
      final training = _FakeTraining([_activePlan()], throwOnUpdate: true);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pumpAndSettle();

      expect(training.updateCalls, 1);
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
    });
  });

  group('PlansScreen — empty', () {
    testWidgets('offers the three built-in starters', (tester) async {
      final training = _FakeTraining([]);
      await _pumpSignedIn(tester, training);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No plans yet.'), findsOneWidget);
      expect(find.text('Couch to 5K (beginner walk-run)'), findsOneWidget);
      expect(find.text('Half Marathon — 12 weeks'), findsOneWidget);
      expect(find.text('Marathon — 16 weeks'), findsOneWidget);
    });

    testWidgets('each starter is one tile: name, summary, start date, prompt',
        (tester) async {
      final training = _FakeTraining([]);
      await _pumpSignedIn(tester, training);
      for (final id in ['c25k', 'half_12wk', 'marathon_16wk']) {
        final tile = find.byKey(Key('planStarter-$id'));
        expect(tile, findsOneWidget);
        expect(
            find.descendant(
                of: tile, matching: find.byKey(Key('planStarterSummary-$id'))),
            findsOneWidget);
        expect(find.descendant(of: tile, matching: find.text('Start this plan')),
            findsOneWidget);
      }
      expect(
          find.descendant(
              of: find.byType(EmptyState),
              matching: find.byType(OutlinedButton)),
          findsNothing);
      final half = tester
          .widget<Text>(find.byKey(const Key('planStarterSummary-half_12wk')))
          .data!;
      expect(half, startsWith('12 weeks · 4 days a week · Starts '));
    });

    testWidgets('a screen reader hears the plan name, with the summary as hint',
        (tester) async {
      final handle = tester.ensureSemantics();
      final training = _FakeTraining([]);
      await _pumpSignedIn(tester, training);
      final summary = tester
          .widget<Text>(find.byKey(const Key('planStarterSummary-half_12wk')))
          .data!;
      expect(
        find.bySemanticsLabel('Half Marathon — 12 weeks'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Half Marathon — 12 weeks')),
        matchesSemantics(
          label: 'Half Marathon — 12 weeks',
          hint: summary,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Start this plan'), findsNothing);
      handle.dispose();
    });

    testWidgets('a create in flight holds every tile and says so on its own',
        (tester) async {
      final training = _FakeTraining([])..createGate = Completer<void>();
      await _pumpSignedIn(tester, training);
      await tester.tap(find.byKey(const Key('planStarter-half_12wk')));
      await tester.pump();
      await tester.pump();
      expect(training.created, isNotNull);
      InkWell tile(String id) => tester.widget<InkWell>(find.descendant(
          of: find.byKey(Key('planStarter-$id')),
          matching: find.byType(InkWell)));
      for (final id in ['c25k', 'half_12wk', 'marathon_16wk']) {
        expect(tile(id).onTap, isNull, reason: id);
      }
      final busy = find.byKey(const Key('planStarter-half_12wk'));
      expect(find.descendant(of: busy, matching: find.text('Creating…')),
          findsOneWidget);
      expect(
          find.descendant(
              of: busy, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(find.text('Start this plan'), findsNWidgets(2));
      final first = training.created;
      await tester.tap(find.byKey(const Key('planStarter-c25k')),
          warnIfMissed: false);
      await tester.pump();
      expect(training.created, same(first));
      training.createGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the tiles do not overflow at 2.0x text on a 360 px phone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final training = _FakeTraining([]);
      await _pumpSignedIn(tester, training, textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('planStarter-c25k')), findsOneWidget);
    });

    testWidgets('a starter creates that plan on a Sunday at least a week out',
        (tester) async {
      final training = _FakeTraining([]);
      await _pumpSignedIn(tester, training);
      await tester.tap(find.byKey(const Key('planStarter-half_12wk')));
      await tester.pump();
      await tester.pump();
      final c = training.created!;
      expect(c.name, 'Half Marathon — 12 weeks');
      expect(c.goal, GoalEvent.distanceHalf);
      expect(c.days, 4);
      expect(c.start.weekday, DateTime.sunday);
      expect(c.start.difference(_today()).inDays, greaterThanOrEqualTo(7));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Couch to 5K starts tomorrow and says what it asks',
        (tester) async {
      final training = _FakeTraining([]);
      await _pumpSignedIn(tester, training);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('planStarterSummary-c25k')))
            .data,
        matches(RegExp(r'^9 weeks · 3 days a week · \d+–\d+ min a session · Starts ')),
      );
      await tester.tap(find.byKey(const Key('planStarter-c25k')));
      await tester.pump();
      await tester.pump();
      expect(training.created!.start, _today().add(const Duration(days: 1)));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a starter start date: tomorrow for walk-run, else a Sunday a week out',
        (_) async {
      // Wednesday 2026-10-14 → a week out is 2026-10-21 → Sunday 2026-10-25.
      expect(starterStartDate('half_12wk', DateTime(2026, 10, 14, 18)),
          DateTime(2026, 10, 25));
      // Sunday → the Sunday a week later, never today.
      expect(starterStartDate('marathon_16wk', DateTime(2026, 10, 18)),
          DateTime(2026, 10, 25));
      expect(starterStartDate('c25k', DateTime(2026, 10, 14, 18)),
          DateTime(2026, 10, 15));
    });
  });
}
