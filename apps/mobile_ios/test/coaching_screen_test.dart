import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coaching_screen.dart';
import 'worst_case_layout.dart';

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

  /// Page-level reads fail while set; the roster fails while [failRoster].
  bool failReads = false;
  bool failRoster = false;

  @override
  Future<List<CoachAthleteLink>> fetchMyAthletes() async {
    if (failReads) throw Exception('offline');
    return athletes;
  }

  @override
  Future<List<PendingCoachInvite>> fetchPendingCoachInvites() async => pending;

  @override
  Future<List<CoachAthleteLink>> fetchMyCoaches() async => coaches;

  @override
  Future<List<CoachRosterRow>> fetchCoachRosterSummary() async {
    if (failRoster) throw Exception('offline');
    return roster;
  }
}

CoachAthleteLink _link(String id, String userId, String? name,
        {String? avatarUrl}) =>
    CoachAthleteLink(
      id: id,
      status: 'active',
      note: null,
      createdAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
      userId: userId,
      displayName: name,
      avatarUrl: avatarUrl,
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

  worstCaseTestWidgets('Coaching cards', (tester, locale) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      roster: [_rosterRow('a1', lastRunAt: DateTime.utc(2026, 1, 3))],
      athletes: [_link('l1', 'a1', 'Alexandra Runner-Featherstonehaugh')],
      pending: [
        PendingCoachInvite(
          id: 'inv-1',
          inviteToken: 'tok-1',
          note: null,
          createdAt: DateTime.utc(2026, 1, 5),
        ),
      ],
      coaches: [_link('l2', 'c1', 'Coach Bartholomew Longname')],
    );
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: CoachingScreen(api: api, preferences: prefs),
    ));
    await tester.pump();
    await tester.pump();
    await walkScrollable(tester, find.byType(Scrollable).first, 'Coaching');
  });

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

  group('roster flags (decisions § 2092)', () {
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

    testWidgets('each flag opens its definition from the metric registry',
        (tester) async {
      final prefs = await _prefs();
      await _pump(tester, _FakeApi(roster: [flagged()]), prefs,
          hrPrescription: true);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.byTooltip(l10n.metricAbout(l10n.metricEasyHrDriftLabel)));
      await tester.pumpAndSettle();
      expect(find.text(l10n.coachingRosterHrDriftHint), findsOneWidget);
      await tester.tap(find.text(l10n.commonDismiss));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.metricAbout(l10n.metricMissStreakLabel)));
      await tester.pumpAndSettle();
      expect(find.text(l10n.metricMissStreakDefinition), findsOneWidget);
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

  // Issue #1374 FS-7: a failed load faded out in a 3-second banner and left
  // "No athletes yet", and a failed roster vanished without a word.
  testWidgets('a failed load is a whole-page error with Retry, not "no athletes"',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(athletes: [_link('l1', 'a1', 'Alice Runner')])
      ..failReads = true;
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingNoAthletes), findsNothing);
    expect(find.text(l10n.errorStateRetry), findsOneWidget);

    api.failReads = false;
    await tester.tap(find.text(l10n.errorStateRetry));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alice Runner'), findsOneWidget);
  });

  testWidgets('a failed roster says so on its card while the rest loads',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(athletes: [_link('l1', 'a1', 'Alice Runner')])
      ..failRoster = true;
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingRosterTitle), findsOneWidget);
    expect(find.text(l10n.coachingRosterLoadFailed), findsOneWidget);
    expect(find.text('Alice Runner'), findsOneWidget);

    api.failRoster = false;
    await tester.tap(find.text(l10n.errorStateRetry));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.coachingRosterLoadFailed), findsNothing);
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

  // The rows drew a bare CircleAvatar initial while the link already carried
  // the uploaded photo's URL; web's coaching page had the same gap.
  testWidgets('athlete and coach rows hand their avatar url to IdentityAvatar',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      athletes: [
        _link('l1', 'a1', 'Alice Runner',
            avatarUrl: 'https://example.test/alice.jpg'),
      ],
      coaches: [
        _link('l2', 'c1', 'Coach Bob',
            avatarUrl: 'https://example.test/bob.jpg'),
      ],
    );
    await _pump(tester, api, prefs);
    final urls = tester
        .widgetList<IdentityAvatar>(find.byType(IdentityAvatar))
        .map((a) => a.imageUrl)
        .toSet();
    expect(urls, containsAll(<String>[
      'https://example.test/alice.jpg',
      'https://example.test/bob.jpg',
    ]));
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
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });
}
