// Issue #1213: the Coach plan picker offers "My season" — the current plan
// and the plans queued after it — beside "No plan" and the single plans, and
// the request says which one the runner picked.
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/training_service.dart';
import 'realtime_drain.dart';

final _en = AppLocalizationsEn();

class _FakeApi extends ApiClient {
  final threadReads = <String?>[];

  @override
  String? get userId => 'u1';

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => const {
        'ai_disclosure_version': 6,
        'coach_consent_at': '2026-01-01T00:00:00Z',
      };

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async {
    threadReads.add(planId);
    return const [];
  }

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];

  @override
  Future<int> countRunsForUser(String userId, {int limit = 100}) async => 5;

  @override
  Future<Map<String, dynamic>?> fetchUserSettingsPrefs(String userId) async =>
      const <String, dynamic>{};

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;
}

class _Training extends TrainingService {
  final List<TrainingPlanRow> plans;
  final Map<String, int> weeks;
  _Training(this.plans, this.weeks);

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async => plans;

  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async => (
            plan: plans.firstWhere((p) => p.id == id),
            weeks: [
              for (var i = 0; i < (weeks[id] ?? 0); i++)
                PlanWeekRow(id: '$id-w$i', planId: id, weekIndex: i, phase: 'base'),
            ],
            workouts: const <PlanWorkoutRow>[],
          );
}

TrainingPlanRow _plan(String id, int startDay, int endDay,
    {String status = 'active'}) {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  return TrainingPlanRow(
    id: id,
    userId: 'u1',
    name: id,
    goalEvent: 'distance_marathon',
    goalDistanceM: 42195,
    startDate: day.add(Duration(days: startDay)),
    endDate: day.add(Duration(days: endDay)),
    daysPerWeek: 4,
    status: status,
    source: 'app',
    isTemplate: false,
    isPublicTemplate: false,
  );
}

// Listed queued-first, the way fetchMyPlans' created_at order puts a block
// that was planned after the current one.
final _marathon = _plan('Marathon block', -14, 20);
final _ultra = _plan('Ultra block', 21, 120);
final _spring = _plan('Spring block', -200, -100, status: 'completed');

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<_FakeApi> _pump(WidgetTester tester, List<TrainingPlanRow> plans,
    {DateTime Function()? now}) async {
  final api = _FakeApi();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(
        api: api,
        training: _Training(plans, {_marathon.id: 5, _ultra.id: 14}),
        loadAiPlanAvailable: () async => false,
        now: now,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return api;
}

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label).last);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(_ensureSupabase);

  test('the request names the scope beside the plan the thread is kept under',
      () {
    final body = coachRequestBody(
      messages: const [
        {'role': 'user', 'content': 'How does my build look?'},
      ],
      planId: 'plan-1',
      planScope: 'season',
      recentRunsLimit: 20,
      mode: 'send',
      anchorMessageId: null,
    );
    expect(body['plan_id'], 'plan-1');
    expect(body['plan_scope'], 'season');
    expect(body['recent_runs_limit'], 20);
  });

  testWidgets(
      'opens on the current plan, not the queued block listed first',
      (tester) async {
    final api = await _pump(tester, [_ultra, _marathon]);
    expect(api.threadReads.first, _marathon.id);
    expect(find.text(_en.coachContextPlanWeeks(_marathon.name, 5)),
        findsOneWidget);
    await drainRealtimeTimers(tester);
  });

  testWidgets(
      'picking My season keeps the thread under the current plan and names '
      'the season with its weeks', (tester) async {
    final api = await _pump(tester, [_ultra, _marathon]);
    await _pick(tester, _en.coachSeasonOption);
    expect(api.threadReads.last, _marathon.id);
    expect(find.text(_en.coachContextPlanWeeks(_en.coachSeasonName, 19)),
        findsOneWidget);
    await drainRealtimeTimers(tester);
  });

  testWidgets(
      'a season that shrinks to one plan while the screen is open falls back '
      'to that plan instead of a picker value with no item', (tester) async {
    var clock = DateTime.now();
    final api = await _pump(tester, [_ultra, _marathon], now: () => clock);
    await _pick(tester, _en.coachSeasonOption);
    clock = clock.add(const Duration(days: 21));
    (tester.element(find.byType(CoachScreen)) as StatefulElement)
        .markNeedsBuild();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(_en.coachSeasonOption), findsNothing);
    expect(find.text(_en.coachPlanActive(_marathon.name)), findsOneWidget);
    expect(api.threadReads.last, _marathon.id);
    await drainRealtimeTimers(tester);
  });

  testWidgets('No plan clears the plan from the thread and the strip',
      (tester) async {
    final api = await _pump(tester, [_ultra, _marathon]);
    await _pick(tester, _en.coachNoPlanOption);
    expect(api.threadReads.last, isNull);
    expect(find.text(_en.coachContextNoPlan), findsOneWidget);
    await drainRealtimeTimers(tester);
  });

  testWidgets('with nothing queued after the current plan there is no season '
      'option', (tester) async {
    await _pump(tester, [_marathon, _spring]);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_en.coachSeasonOption), findsNothing);
    expect(find.text(_en.coachNoPlanOption), findsWidgets);
    await drainRealtimeTimers(tester);
  });
}
