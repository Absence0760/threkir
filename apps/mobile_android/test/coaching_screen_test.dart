import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coaching_screen.dart';

/// Signed-in fake whose coaching reads return canned data so the roster
/// screen renders without touching Supabase. Subclassing the real type keeps
/// it a drop-in for the screen's `api` field.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.athletes = const [],
    this.pending = const [],
    this.coaches = const [],
    this.roster = const [],
  });

  final List<CoachRosterRow> roster;
  final List<CoachAthleteLink> athletes;
  final List<PendingCoachInvite> pending;
  final List<CoachAthleteLink> coaches;

  @override
  String? get userId => 'coach-1';

  @override
  Future<List<CoachAthleteLink>> fetchMyAthletes() async => athletes;

  @override
  Future<List<PendingCoachInvite>> fetchPendingCoachInvites() async => pending;

  @override
  Future<List<CoachAthleteLink>> fetchMyCoaches() async => coaches;

  @override
  Future<List<CoachRosterRow>> fetchCoachRosterSummary() async => roster;
}

CoachAthleteLink _link(String id, String userId, String? name) =>
    CoachAthleteLink(
      id: id,
      status: 'active',
      note: null,
      createdAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
      userId: userId,
      displayName: name,
      avatarUrl: null,
    );

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, ApiClient api, Preferences prefs,
    {bool hrPrescription = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachingScreen(
          api: api, preferences: prefs, hrPrescription: hrPrescription),
    ),
  );
  await tester.pump(); // let initState's _load future resolve
  await tester.pump();
}

CoachRosterRow _rosterRow(String id, {DateTime? lastRunAt}) => CoachRosterRow(
      athleteId: id,
      displayName: null,
      avatarUrl: null,
      lastRunAt: lastRunAt,
      runs7d: 0,
      distance7dM: 0,
      loadAcute: 0,
      loadChronic: 0,
      activePlanId: null,
      planCompletionPct: 0,
    );

void main() {
  test('within a risk band the roster puts the most-stale athlete first', () {
    // The tiebreak used to compare newest-first, so the athlete who had gone
    // quiet sank to the bottom of their band. Web twin: roster_sort.test.ts.
    final rows = sortRosterByAttention([
      _rosterRow('fresh', lastRunAt: DateTime.utc(2026, 10, 15, 7)),
      _rosterRow('never'),
      _rosterRow('quiet', lastRunAt: DateTime.utc(2026, 9, 1, 7)),
      _rosterRow('also-never'),
    ]);
    expect(rows.map((r) => r.athleteId),
        ['also-never', 'never', 'quiet', 'fresh']);
  });

  setUpAll(() => initializeDateFormatting());

  group('coachInviteLink', () {
    test('builds the accept URL with the default host', () {
      expect(
        coachInviteLink('abc123', webBase: ''),
        'https://threkir.com/coaching/accept/abc123',
      );
    });

    test('uses the provided base and trims a trailing slash', () {
      expect(
        coachInviteLink('tok', webBase: 'https://preview.threkir.com/'),
        'https://preview.threkir.com/coaching/accept/tok',
      );
    });
  });

  group('roster flags (decisions § 2087)', () {
    CoachRosterRow flagged() => CoachRosterRow(
          athleteId: 'a1',
          displayName: 'Alice Runner',
          avatarUrl: null,
          lastRunAt: DateTime.utc(2031, 3, 1),
          runs7d: 1,
          distance7dM: 5000,
          loadAcute: 50,
          loadChronic: 50,
          activePlanId: 'plan-1',
          planCompletionPct: 40,
          athleteToday: '2031-03-10',
          recentWorkouts: const [
            {'scheduled_date': '2031-03-09', 'kind': 'easy', 'completed': false, 'skipped': false},
            {'scheduled_date': '2031-03-07', 'kind': 'tempo', 'completed': false, 'skipped': false},
            {'scheduled_date': '2031-03-05', 'kind': 'easy', 'completed': true, 'skipped': false},
          ],
          easyHrDriftPct: 6.6,
        );

    testWidgets('a two-miss streak and the easy-HR drift are flagged',
        (tester) async {
      final prefs = await _prefs();
      await _pump(tester, _FakeApi(roster: [flagged()]), prefs,
          hrPrescription: true);
      expect(find.byKey(const Key('rosterMissFlag-a1')), findsOneWidget);
      expect(find.text('2 missed in a row'), findsOneWidget);
      expect(find.text('Easy HR +7%'), findsOneWidget);
    });

    testWidgets('with the gate off the drift chip stays hidden',
        (tester) async {
      final prefs = await _prefs();
      await _pump(tester, _FakeApi(roster: [flagged()]), prefs);
      expect(find.text('2 missed in a row'), findsOneWidget);
      expect(find.byKey(const Key('rosterHrDriftFlag-a1')), findsNothing);
    });
  });

  testWidgets('renders empty state when there are no athletes or coaches',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, _FakeApi(), prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingNoAthletes), findsOneWidget);
    expect(find.text(l10n.coachingNoCoaches), findsOneWidget);
    expect(find.text(l10n.coachingInviteAnAthlete), findsOneWidget);
  });

  testWidgets('lists athletes and coaches', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      athletes: [_link('l1', 'a1', 'Alice Runner')],
      coaches: [_link('l2', 'c1', 'Coach Bob')],
    );
    await _pump(tester, api, prefs);
    expect(find.text('Alice Runner'), findsOneWidget);
    expect(find.text('Coach Bob'), findsOneWidget);
  });

  testWidgets('shows a pending invite with copy/share/revoke actions',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(pending: [
      PendingCoachInvite(
        id: 'inv-1',
        inviteToken: 'tok-1',
        note: null,
        createdAt: DateTime.utc(2026, 1, 5),
      ),
    ]);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingPendingInvite), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });
}
