// Opening the Coach on a conversation longer than the screen lands on its
// latest exchange. The scroll down used to fire on a fixed 50 ms timer and
// give up when the message list had not been laid out by then, so on a quick
// backend the thread opened at its first message instead.
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ai_disclosure.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/training_service.dart';
import 'realtime_drain.dart';
import 'supabase_test_init.dart';

const _firstQuestion = 'My legs felt heavy on Sunday. Should I still run?';
const _latestQuestion = 'Am I still on track for my goal time?';

final _longAnswer = List.filled(
  6,
  'Keep the long runs easy and the tempo honest; one session never decides '
  'race day.',
).join('\n\n');

CoachMessageRow _row(int i, String role, String content) => CoachMessageRow(
  id: 'm$i',
  userId: 'u1',
  planId: 'p1',
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 1, 1, 7, i),
);

/// Answers every read at once, so the thread is ready well inside the first
/// pumped frame interval.
class _InstantApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => {
    'ai_disclosure_version': kAiDisclosureCurrentVersion,
    'coach_consent_at': '2026-01-01T00:00:00Z',
  };

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async => [
    _row(0, 'user', _firstQuestion),
    _row(1, 'assistant', _longAnswer),
    _row(2, 'user', _latestQuestion),
    _row(3, 'assistant', 'Yes, comfortably.'),
  ];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];

  @override
  Future<int> countRunsForUser(String userId, {int limit = 100}) async => 20;

  @override
  Future<Map<String, dynamic>?> fetchUserSettingsPrefs(String userId) async =>
      const <String, dynamic>{};

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => true;

  @override
  Future<bool> fetchCoachShareEnabled() async => false;
}

class _Training extends TrainingService {
  static final _plan = TrainingPlanRow(
    id: 'p1',
    userId: 'u1',
    name: 'Riverside Half Marathon',
    goalEvent: 'distance_half',
    goalDistanceM: 21097,
    startDate: DateTime.now().subtract(const Duration(days: 35)),
    endDate: DateTime.now().add(const Duration(days: 49)),
    daysPerWeek: 5,
    status: 'active',
    source: 'app',
    isTemplate: false,
    isPublicTemplate: false,
  );

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async => [_plan];

  @override
  Future<
    ({
      TrainingPlanRow? plan,
      List<PlanWeekRow> weeks,
      List<PlanWorkoutRow> workouts,
    })
  >
  fetchPlan(String id) async =>
      (plan: _plan, weeks: <PlanWeekRow>[], workouts: <PlanWorkoutRow>[]);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initializeTestSupabase();
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'opens on the latest exchange when the thread loads between frames '
      '(reduce motion: $reduceMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: CoachScreen(
              api: _InstantApi(),
              training: _Training(),
              initialPlanId: 'p1',
              loadAiPlanAvailable: () async => false,
            ),
          ),
        );
        // Frames a device draws while the reads land: every read resolves
        // before the first of them, as on a fast local backend.
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        Finder onScreen(String text) =>
            find.textContaining(text, findRichText: true);
        Finder built(String text) =>
            find.textContaining(text, findRichText: true, skipOffstage: false);
        expect(
          built(_firstQuestion).evaluate().isNotEmpty ||
              built(_latestQuestion).evaluate().isNotEmpty,
          isTrue,
          reason: 'the thread loaded',
        );
        expect(
          onScreen(_latestQuestion),
          findsOneWidget,
          reason: 'the latest exchange is on screen, not below the fold',
        );
        expect(
          onScreen(_firstQuestion),
          findsNothing,
          reason:
              'the thread is longer than the screen, so its start has '
              'scrolled away',
        );
        await drainRealtimeTimers(tester);
      },
    );
  }
}
