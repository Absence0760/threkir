// The Coach screen's header: the context strip (plan picker, runs window,
// settings chips), the season hint under it and the daily-allowance banner.
// Pumped on a 360 dp phone, the narrow end of what the app supports.
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;
import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/race_service.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/screens/races_screen.dart';
import '../lib/training_service.dart';
import 'pump_until.dart';
import 'realtime_drain.dart';

final _en = AppLocalizationsEn();

class _FakeApi extends ApiClient {
  final int usage;
  _FakeApi({this.usage = 0});

  @override
  String? get userId => 'u1';

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => const {
        'ai_disclosure_version': 6,
        'coach_consent_at': '2026-01-01T00:00:00Z',
      };

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async =>
      const [];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];

  @override
  Future<int> countRunsForUser(String userId, {int limit = 100}) async => 5;

  @override
  Future<Map<String, dynamic>?> fetchUserSettingsPrefs(String userId) async =>
      const <String, dynamic>{
        'hr_zones': {'z1': 120, 'z2': 135, 'z3': 150, 'z4': 165, 'z5': 180},
        'weekly_mileage_goal_m': 40000,
      };

  @override
  Future<int> getCoachUsage() async => usage;

  @override
  Future<bool> isPro() async => false;
}

class _Training extends TrainingService {
  final List<TrainingPlanRow> plans;
  _Training(this.plans);

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async => plans;

  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async => (
            plan: plans.firstWhere((p) => p.id == id),
            weeks: [
              for (var i = 0; i < 5; i++)
                PlanWeekRow(id: '$id-w$i', planId: id, weekIndex: i, phase: 'base'),
            ],
            workouts: const <PlanWorkoutRow>[],
          );
}

class _Races extends RaceService {
  @override
  Future<List<RaceListingView>> searchRaceListings({
    String? query,
    String? distance,
    String? from,
    String? to,
    String? nearPlace,
    String? mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
    int limit = 60,
    bool newestFirst = false,
  }) async =>
      const [];
}

TrainingPlanRow _plan(String id, String name, int startDay, int endDay) {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  return TrainingPlanRow(
    id: id,
    userId: 'u1',
    name: name,
    goalEvent: 'distance_marathon',
    goalDistanceM: 42195,
    startDate: day.add(Duration(days: startDay)),
    endDate: day.add(Duration(days: endDay)),
    daysPerWeek: 4,
    status: 'active',
    source: 'app',
    isTemplate: false,
    isPublicTemplate: false,
  );
}

const _richmondName = 'Richmond Marathon 2026';
final _richmond = _plan('p-richmond', _richmondName, -14, 20);
final _ultra = _plan('p-ultra', 'Autumn ultra block', 21, 120);

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

/// A 360 dp phone at [textScale], with the strip loaded.
Future<void> _pump(
  WidgetTester tester,
  List<TrainingPlanRow> plans, {
  int usage = 0,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(
        api: _FakeApi(usage: usage),
        training: _Training(plans),
        loadAiPlanAvailable: () async => false,
        raceService: _Races(),
      ),
    ),
  );
  await pumpUntil(
    tester,
    () => find.byType(DropdownButton<int>).evaluate().isNotEmpty,
    describe: 'the context strip with the runs window',
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('the season hint', () {
    testWidgets(
        'with one plan and nothing queued, points to adding the next race',
        (tester) async {
      await _pump(tester, [_richmond]);
      expect(find.text(_en.coachSeasonHint), findsOneWidget);
      final action = find.byKey(const Key('coach-season-hint-action'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await pumpUntil(
        tester,
        () => find.byType(RacesScreen).evaluate().isNotEmpty,
        describe: 'the race calendar opening from the season hint',
      );
      await drainRealtimeTimers(tester);
    });

    testWidgets('is gone once a plan is queued, where My season is offered',
        (tester) async {
      await _pump(tester, [_ultra, _richmond]);
      expect(find.text(_en.coachSeasonHint), findsNothing);
      await drainRealtimeTimers(tester);
    });
  });

  group('the daily allowance banner', () {
    testWidgets('a count of messages left sits on the neutral surface',
        (tester) async {
      await _pump(tester, [_richmond]);
      final banner = tester.widget<Container>(
          find.byKey(const Key('coach-limit-banner')));
      final cs = Theme.of(tester.element(find.byType(CoachScreen))).colorScheme;
      expect(find.text(_en.coachMessagesLeft(2)), findsOneWidget);
      expect(banner.color, cs.surfaceContainerHighest);
      await drainRealtimeTimers(tester);
    });

    testWidgets('only an exhausted allowance takes the warning colour',
        (tester) async {
      await _pump(tester, [_richmond], usage: 2);
      final banner = tester.widget<Container>(
          find.byKey(const Key('coach-limit-banner')));
      final theme = Theme.of(tester.element(find.byType(CoachScreen)));
      expect(find.text(_en.coachLimitReachedFree), findsOneWidget);
      expect(banner.color, AppSemanticColors.ofTheme(theme).warning);
      await drainRealtimeTimers(tester);
    });
  });
}
