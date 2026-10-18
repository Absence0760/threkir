import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/plan_calibration.dart';
import '../lib/training_service.dart';
import 'realtime_drain.dart';

final _en = AppLocalizationsEn();

class _FakeApi extends ApiClient {
  final int runs;
  final List<CoachMessageRow> messages;
  _FakeApi({required this.runs, this.messages = const []});

  @override
  String? get userId => 'u1';

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => const {
        'ai_disclosure_version': 3,
        'coach_consent_at': '2026-01-01T00:00:00Z',
      };

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async =>
      messages;

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];

  @override
  Future<int> countRunsForUser(String userId, {int limit = 100}) async => runs;

  @override
  Future<Map<String, dynamic>?> fetchUserSettingsPrefs(String userId) async =>
      const <String, dynamic>{};

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;
}

class _Training extends TrainingService {
  final TrainingPlanRow? active;
  _Training({this.active});

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async =>
      active == null ? const [] : [active!];

  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async =>
          (plan: active, weeks: const <PlanWeekRow>[], workouts: const <PlanWorkoutRow>[]);

  @override
  Future<PlanCalibration> fetchPlanCalibration() async =>
      PlanCalibration.unknown;
  @override
  Future<PlanRunHistory?> fetchPlanRunHistory() async => null;
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];
}

TrainingPlanRow _plan() {
  final today = DateTime.now();
  return TrainingPlanRow(
    id: 'plan-1',
    userId: 'u1',
    name: 'Spring half',
    goalEvent: 'distance_half',
    goalDistanceM: 21097.5,
    startDate: today.subtract(const Duration(days: 14)),
    endDate: today.add(const Duration(days: 70)),
    daysPerWeek: 4,
    status: 'active',
    source: 'app',
    isTemplate: false,
    isPublicTemplate: false,
  );
}

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

Future<void> _pump(
  WidgetTester tester, {
  required bool aiPlan,
  int runs = 12,
  TrainingPlanRow? plan,
  List<CoachMessageRow> messages = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(
        api: _FakeApi(runs: runs, messages: messages),
        training: _Training(active: plan),
        loadAiPlanAvailable: () async => aiPlan,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(_ensureSupabase);

  group('coachPlanAdjustWebUri', () {
    const id = '11111111-2222-4333-8444-555555555555';

    test('opens the web plan page carrying only the change request', () {
      final uri = coachPlanAdjustWebUri(
          '/plans/$id?adjust=Move%20my%20long%20run%20to%20Sunday&x=1',
          'https://threkir.com/');
      expect(uri, isNotNull);
      expect(uri!.host, 'threkir.com');
      expect(uri.path, '/plans/$id');
      expect(uri.queryParameters, {'adjust': 'Move my long run to Sunday'});
    });

    test('anything else is not a plan-edit link', () {
      for (final href in [
        '/plans/$id',
        '/plans/$id?adjust=%20',
        '/plans/new?adjust=x',
        '/plans/not-a-uuid?adjust=x',
        'https://evil.example/plans/$id?adjust=x',
        '//evil.example/plans/$id?adjust=x',
        '/plans/$id/edit?adjust=x',
      ]) {
        expect(coachPlanAdjustWebUri(href, 'https://threkir.com'), isNull,
            reason: href);
      }
    });

    test('a non-web base never becomes a launch target', () {
      expect(
          coachPlanAdjustWebUri('/plans/$id?adjust=x', 'javascript:alert(1)'),
          isNull);
    });
  });

  group('coachPlanLinkDescription', () {
    test('reads a decoded description off a /plans/new link', () {
      expect(
          coachPlanLinkDescription(
              '/plans/new?describe=A%20sub-2%20half%20on%2014%20March'),
          'A sub-2 half on 14 March');
      expect(coachPlanLinkDescription('/plans/new?describe=a+10K'), 'a 10K');
    });

    test('a link without a description opens the wizard empty', () {
      expect(coachPlanLinkDescription('/plans/new'), '');
      expect(coachPlanLinkDescription('/plans/new?describe=%20%20'), '');
    });

    test('caps the description at the box budget', () {
      final long = 'a' * (kPlanDescriptionMaxChars + 50);
      expect(coachPlanLinkDescription('/plans/new?describe=$long'),
          hasLength(kPlanDescriptionMaxChars));
    });

    test('anything else is not a plan link', () {
      for (final href in [
        'https://evil.example/plans/new?describe=x',
        '//evil.example/plans/new',
        'javascript:alert(1)',
        '/plans',
        '/plans/new/extra',
        '/runs/123',
      ]) {
        expect(coachPlanLinkDescription(href), isNull, reason: href);
      }
    });

    test('a malformed escape still opens the wizard, without the text', () {
      expect(coachPlanLinkDescription('/plans/new?describe=%E0%A4%A'), '');
    });
  });

  group('CoachScreen — AI plan prompts', () {
    realtimeWidgetTest('no plan: the build-a-plan chip leads when live',
        (tester) async {
      await _pump(tester, aiPlan: true);
      expect(find.text(_en.coachSuggestBuildHalfPlan), findsOneWidget);
      expect(find.text(_en.coachSuggestNoPlanTempo), findsNothing);
      expect(find.byType(ActionChip), findsNWidgets(4));
      final first = tester.widget<ActionChip>(find.byType(ActionChip).first);
      expect((first.label as Text).data, _en.coachSuggestBuildHalfPlan);
    });

    realtimeWidgetTest('no plan: no build-a-plan chip when the assistant is off',
        (tester) async {
      await _pump(tester, aiPlan: false);
      expect(find.text(_en.coachSuggestBuildHalfPlan), findsNothing);
      expect(find.text(_en.coachSuggestNoPlanTempo), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(4));
    });

    realtimeWidgetTest('a new runner gets the first-5K plan chip when live',
        (tester) async {
      await _pump(tester, aiPlan: true, runs: 0);
      expect(find.text(_en.coachSuggestBuildFirst5kPlan), findsOneWidget);
      expect(find.text(_en.coachSuggestNewHowOften), findsNothing);
      expect(find.byType(ActionChip), findsNWidgets(4));
    });

    realtimeWidgetTest('a new runner sees no plan chip when off',
        (tester) async {
      await _pump(tester, aiPlan: false, runs: 0);
      expect(find.text(_en.coachSuggestBuildFirst5kPlan), findsNothing);
      expect(find.text(_en.coachSuggestNewHowOften), findsOneWidget);
    });

    realtimeWidgetTest('with a plan: "plan my next race" when live',
        (tester) async {
      await _pump(tester, aiPlan: true, plan: _plan());
      expect(find.text(_en.coachSuggestPlanNextRace), findsOneWidget);
      expect(find.text(_en.coachSuggestPlanLongRun), findsNothing);
      expect(find.byType(ActionChip), findsNWidgets(4));
    });

    realtimeWidgetTest('with a plan: the long-run chip stays when off',
        (tester) async {
      await _pump(tester, aiPlan: false, plan: _plan());
      expect(find.text(_en.coachSuggestPlanNextRace), findsNothing);
      expect(find.text(_en.coachSuggestPlanLongRun), findsOneWidget);
    });

    realtimeWidgetTest('a "Build this plan" link opens the wizard prefilled',
        (tester) async {
      await _pump(
        tester,
        aiPlan: false,
        messages: [
          CoachMessageRow(
            id: 'm1',
            userId: 'u1',
            role: 'assistant',
            content: '[Build this plan](/plans/new?describe='
                'A%20sub-2%20half%20on%2014%20March)',
            createdAt: DateTime(2026, 10, 1),
          ),
        ],
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      markdown.onTapLink!('Build this plan',
          '/plans/new?describe=A%20sub-2%20half%20on%2014%20March', '');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 500));

      final wizard = tester.widget<PlanNewScreen>(find.byType(PlanNewScreen));
      expect(wizard.initialDescription, 'A sub-2 half on 14 March');
    });
  });

  group('CoachScreen — web handoff links', () {
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    const planId = '11111111-2222-4333-8444-555555555555';

    Future<List<Uri>> tapCoachLink(
        WidgetTester tester, String text, String href,
        {String env = 'WEB_BASE_URL=https://preview.threkir.com'}) async {
      dotenv.loadFromString(
        envString: env,
        isOptional: true,
      );
      final launched = <Uri>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
          (call) async {
        if (call.method == 'launch' || call.method == 'launchUrl') {
          launched.add(Uri.parse((call.arguments as Map)['url'] as String));
        }
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null));
      await _pump(
        tester,
        aiPlan: false,
        plan: _plan(),
        messages: [
          CoachMessageRow(
            id: 'm1',
            userId: 'u1',
            role: 'assistant',
            content: '[$text]($href)',
            createdAt: DateTime(2026, 10, 1),
          ),
        ],
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      markdown.onTapLink!(text, href, '');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return launched;
    }

    realtimeWidgetTest('an "Adjust my plan" link opens the web plan page',
        (tester) async {
      final launched = await tapCoachLink(tester, 'Adjust my plan',
          '/plans/$planId?adjust=Move%20my%20long%20run%20to%20Sunday');
      expect(launched, hasLength(1));
      expect(launched.single.origin, 'https://preview.threkir.com');
      expect(launched.single.path, '/plans/$planId');
      expect(launched.single.queryParameters,
          {'adjust': 'Move my long run to Sunday'});
      expect(find.byType(PlanNewScreen), findsNothing);
    });

    realtimeWidgetTest(
        'an "Adjust my plan" link with a blank WEB_BASE_URL opens production',
        (tester) async {
      final launched = await tapCoachLink(tester, 'Adjust my plan',
          '/plans/$planId?adjust=Move%20my%20long%20run%20to%20Sunday',
          env: 'WEB_BASE_URL=');
      expect(launched, hasLength(1));
      expect(launched.single.origin, 'https://threkir.com');
      expect(launched.single.path, '/plans/$planId');
    });

    realtimeWidgetTest('a "Plan your fuelling" link opens the web fuelling page',
        (tester) async {
      final launched = await tapCoachLink(tester, 'Plan your fuelling',
          '/nutrition/fuel?duration=9000&carbs=70&heat=1');
      expect(launched, hasLength(1));
      expect(launched.single.origin, 'https://preview.threkir.com');
      expect(launched.single.path, '/nutrition/fuel');
      expect(launched.single.queryParameters,
          {'duration': '9000', 'carbs': '70', 'heat': '1'});
    });
  });
}
