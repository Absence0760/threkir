// ignore_for_file: avoid_relative_lib_imports
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/ai_disclosure_memo.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/pro_sellable.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/ai_tag.dart';
import 'realtime_drain.dart';

/// The AI Coach as a conversation in the Messages inbox (decisions § 2227):
/// placed by the runner's setting, labelled as AI, previewing the newest
/// Coach message only once the runner has consented, and absent when the
/// deploy has the Coach off.

const _me = 'me';
const _quiet = Duration(hours: 1);

DmThread _thread(String id, DateTime lastAt) => DmThread(
      partnerId: id,
      partnerName: 'Runner $id',
      lastBody: 'last from $id',
      lastAt: lastAt,
      lastFromMe: false,
      unread: 0,
    );

class _FakeApi extends ApiClient {
  _FakeApi({this.consented = true, this.latest, this.threads = const []});

  final bool consented;
  CoachMessageRow? latest;
  List<DmThread> threads;
  int latestReads = 0;

  @override
  String? get userId => _me;

  @override
  Future<List<DmThread>> fetchDmThreads() async => threads;

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => consented
      ? const {
          'ai_disclosure_version': 2,
          'coach_consent_at': '2026-01-01T00:00:00Z',
        }
      : const {'ai_disclosure_version': null, 'coach_consent_at': null};

  @override
  Future<CoachMessageRow?> fetchLatestCoachMessage() async {
    latestReads++;
    return latest;
  }

  // CoachScreen's reads, for the case that opens it.
  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async =>
      const [];
  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];
  @override
  Future<int> getCoachUsage() async => 0;
  @override
  Future<bool> isPro() async => false;
}

CoachMessageRow _coachMsg(String content, DateTime at,
        {String role = 'assistant', String? planId = 'plan-1'}) =>
    CoachMessageRow(
      id: 'c1',
      userId: _me,
      planId: planId,
      role: role,
      content: content,
      createdAt: at,
    );

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

Future<ProPerks> _coachOn() async => const ProPerks(coach: true, routeGen: false);
Future<ProPerks> _coachOff() async => ProPerks.none;

Future<List<Map<String, dynamic>>> _pump(
  WidgetTester tester,
  _FakeApi api, {
  Object? placement,
  Future<ProPerks> Function() perks = _coachOn,
  Object? writeError,
}) async {
  final writes = <Map<String, dynamic>>[];
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MessagesScreen(
      api: api,
      training: TrainingService(),
      pollInterval: _quiet,
      loadPerks: perks,
      readCoachPlacement: () => placement,
      writeUniversal: (changes) async {
        writes.add(changes);
        if (writeError != null) throw writeError;
      },
    ),
  ));
  await tester.pump();
  await tester.pump();
  return writes;
}

List<String> _rowKeys(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        (tile.key as ValueKey<String>).value,
    ];

void main() {
  setUpAll(_ensureSupabase);
  setUp(AiDisclosureMemo.forget);

  final older = DateTime.utc(2026, 10, 19, 9);
  final newer = DateTime.utc(2026, 10, 21, 9);

  testWidgets('the Coach is pinned above the conversations and labelled AI',
      (tester) async {
    final api = _FakeApi(
      latest: _coachMsg('**Easy** 6 km today', older),
      threads: [_thread('p-1', newer)],
    );
    await _pump(tester, api);

    expect(_rowKeys(tester), ['inbox-coach-row', 'dm-thread-p-1']);
    final row = find.byKey(const ValueKey('inbox-coach-row'));
    expect(find.descendant(of: row, matching: find.text('AI Coach')),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(AiTag)),
        findsOneWidget);
    // The tag reads as the full phrase, merged into the row's announcement.
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(row).label,
      allOf(contains('AI Coach'), contains('AI-generated')),
    );
    semantics.dispose();
    expect(find.text('Easy 6 km today'), findsOneWidget);
  });

  testWidgets('a runner who has not consented gets no Coach text, and none is '
      'read', (tester) async {
    final api = _FakeApi(
      consented: false,
      latest: _coachMsg('private coach reply', older),
    );
    await _pump(tester, api);

    expect(find.byKey(const ValueKey('inbox-coach-row')), findsOneWidget);
    expect(find.text('Ask about your training, your plan or a run.'),
        findsOneWidget);
    expect(find.text('private coach reply'), findsNothing);
    expect(api.latestReads, 0);
  });

  testWidgets('with the Coach off for the deploy there is no Coach row',
      (tester) async {
    final api = _FakeApi(threads: [_thread('p-1', newer)]);
    await _pump(tester, api, perks: _coachOff);

    expect(find.byKey(const ValueKey('inbox-coach-row')), findsNothing);
    expect(find.byKey(const ValueKey('dm-thread-p-1')), findsOneWidget);
    expect(api.latestReads, 0);
  });

  testWidgets('a hidden Coach is left out of the inbox', (tester) async {
    final api = _FakeApi(threads: [_thread('p-1', newer)]);
    await _pump(tester, api, placement: 'hidden');

    expect(find.byKey(const ValueKey('inbox-coach-row')), findsNothing);
    expect(api.latestReads, 0);
  });

  testWidgets('a listed Coach sorts among the conversations by its latest '
      'message', (tester) async {
    final api = _FakeApi(
      latest: _coachMsg('reply', DateTime.utc(2026, 10, 20, 9)),
      threads: [_thread('p-1', newer), _thread('p-2', older)],
    );
    await _pump(tester, api, placement: 'listed');

    expect(_rowKeys(tester),
        ['dm-thread-p-1', 'inbox-coach-row', 'dm-thread-p-2']);
  });

  testWidgets('unpinning saves the choice and moves the row', (tester) async {
    final api = _FakeApi(
      latest: _coachMsg('reply', older),
      threads: [_thread('p-1', newer)],
    );
    final writes = await _pump(tester, api);
    expect(_rowKeys(tester).first, 'inbox-coach-row');

    await tester.tap(find.byKey(const ValueKey('inbox-coach-pin')));
    await tester.pump();

    expect(writes, [
      {'messages_coach_row': 'listed'},
    ]);
    expect(_rowKeys(tester), ['dm-thread-p-1', 'inbox-coach-row']);
    expect(find.byTooltip('Pin AI Coach to the top'), findsOneWidget);
  });

  testWidgets('a refused pin write puts the row back and says so',
      (tester) async {
    final api = _FakeApi(
      latest: _coachMsg('reply', older),
      threads: [_thread('p-1', newer)],
    );
    await _pump(tester, api, writeError: Exception('rls'));

    await tester.tap(find.byKey(const ValueKey('inbox-coach-pin')));
    await tester.pump();
    await tester.pump();

    expect(_rowKeys(tester).first, 'inbox-coach-row');
    expect(find.text("Couldn't save where AI Coach goes. Try again."),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('with no conversations the Coach row stands with the empty '
      'guidance under it', (tester) async {
    final api = _FakeApi(latest: null);
    await _pump(tester, api);

    expect(find.byKey(const ValueKey('inbox-coach-row')), findsOneWidget);
    expect(find.text('Ask about your training, your plan or a run.'),
        findsOneWidget);
    expect(
      find.text('Open a runner\'s profile and tap Message to start a '
          'conversation.'),
      findsOneWidget,
    );
    expect(
      find.text('No conversations yet'),
      findsNothing,
      reason: 'the full empty state is for an inbox with no rows at all',
    );
  });

  realtimeWidgetTest(
      'tapping the row opens the Coach on the plan of its latest message',
      (tester) async {
    final api = _FakeApi(latest: _coachMsg('reply', older, planId: 'plan-9'));
    await _pump(tester, api);

    await tester.tap(find.byKey(const ValueKey('inbox-coach-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final coach = tester.widget<CoachScreen>(find.byType(CoachScreen));
    expect(coach.initialPlanId, 'plan-9');
  });
}
