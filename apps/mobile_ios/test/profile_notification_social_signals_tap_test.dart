// Tapping a row in the mobile inbox marks it read and opens what it names,
// kind for kind with web's notificationLinkFor. Every run kind opens the run
// view that serves owner and non-owner alike (decisions § 1971); kudos,
// comment, comment_reply and reaction used to mark read and go nowhere.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenge_detail_screen.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/screens/public_run_screen.dart';
import '../lib/widgets/badge_grid.dart';

NotificationView _view(String kind, {String? eventClubSlug}) => NotificationView(
      row: NotificationRow(
        id: 'n-$kind',
        userId: 'me',
        actorId: 'u-ana',
        kind: kind,
        runId: 'r1',
        eventId: 'e1',
        planId: 'p1',
        achievementId: 'a1',
        challengeId: 'c1',
        createdAt: DateTime.utc(2026, 10, 13, 9),
        refunded: false,
      ),
      actor: const PublicProfile(id: 'u-ana', displayName: 'Ana', avatarUrl: null),
      eventClubSlug: eventClubSlug,
    );

class _NotifApi extends ApiClient {
  _NotifApi(this._views);

  final List<NotificationView> _views;

  @override
  String? get userId => 'me';

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async =>
      const ProfileSummary(
        id: 'me',
        displayName: 'Me',
        followerCount: 0,
        followingCount: 0,
        viewerFollows: false,
      );

  @override
  Future<List<RunRow>> fetchPublicRunsByUser(
    String userId, {
    int limit = 50,
  }) async => const [];

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 20,
    List<Object?>? after,
  }) async => const KeysetPage(<UserProfileRow>[], null);

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 20,
    List<Object?>? after,
  }) async => const KeysetPage(<UserProfileRow>[], null);

  @override
  Future<List<AchievementRow>> fetchUserBadges(String userId) async => const [];

  @override
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async => _views;

  @override
  Future<void> markAllNotificationsRead() async {}

  final List<String> read = [];
  final List<String> opened = [];

  @override
  Future<void> markNotificationRead(String id) async => read.add(id);

  @override
  Future<({RunRow? row, bool shared})> fetchViewableRunById(String runId) async {
    opened.add(runId);
    return (row: null, shared: false);
  }
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

Future<void> _pump(WidgetTester tester, _NotifApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProfileScreen(
        api: api,
        userId: 'me',
        initialTab: ProfileTab.notifications,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(_ensureSupabase);

  final cases = <String, String Function(AppLocalizations)>{
    'kudos': (l) => l.profileNotifKudos('Ana', l.profileNotifYourRun),
    'comment': (l) => l.profileNotifComment('Ana', l.profileNotifYourRun),
    'comment_reply': (l) => l.profileNotifCommentReply('Ana'),
    'reaction': (l) => l.profileNotifReaction('Ana'),
    'comment_like': (l) => l.profileNotifCommentLike('Ana'),
    'mention': (l) => l.profileNotifMention('Ana'),
  };
  for (final entry in cases.entries) {
    testWidgets('tapping a ${entry.key} row marks it read and opens the run', (tester) async {
      final api = _NotifApi([_view(entry.key)]);
      await _pump(tester, api);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.tap(find.text(entry.value(l10n)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(api.read, ['n-${entry.key}']);
      expect(find.byType(PublicRunScreen), findsOneWidget);
      expect(api.opened, ['r1']);
    });
  }

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  }

  testWidgets('tapping a follow row opens the follower\'s profile', (tester) async {
    final api = _NotifApi([_view('follow')]);
    await _pump(tester, api);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tapAndSettle(tester, l10n.profileNotifFollow('Ana'));

    expect(api.read, ['n-follow']);
    expect(
      find.byWidgetPredicate((w) => w is ProfileScreen && w.userId == 'u-ana'),
      findsOneWidget,
    );
     await teardown(tester);
  });

  final eventCases = <String, String Function(AppLocalizations)>{
    'event_cancel': (l) => l.profileNotifEventCancel,
    'event_reminder': (l) => l.profileNotifEventReminder,
  };
  for (final entry in eventCases.entries) {
    testWidgets('tapping an ${entry.key} row opens the event', (tester) async {
      final api = _NotifApi([_view(entry.key, eventClubSlug: 'studio')]);
      await _pump(tester, api);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tapAndSettle(tester, entry.value(l10n));

      expect(api.read, ['n-${entry.key}']);
      final screen = tester.widget<EventDetailScreen>(
        find.byType(EventDetailScreen),
      );
      expect(screen.eventId, 'e1');
      expect(screen.clubSlug, 'studio');
      await teardown(tester);
    });
  }

  final planCases = <String, String Function(AppLocalizations)>{
    'plan_update': (l) => l.profileNotifPlanUpdate('Ana'),
    'plan_assigned': (l) => l.profileNotifPlanAssigned('Ana'),
  };
  for (final entry in planCases.entries) {
    testWidgets('tapping a ${entry.key} row opens the plan', (tester) async {
      final api = _NotifApi([_view(entry.key)]);
      await _pump(tester, api);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tapAndSettle(tester, entry.value(l10n));

      expect(api.read, ['n-${entry.key}']);
      final screen = tester.widget<PlanDetailScreen>(
        find.byType(PlanDetailScreen),
      );
      expect(screen.planId, 'p1');
      await teardown(tester);
    });
  }

  testWidgets('tapping a challenge_complete row opens the challenge', (tester) async {
    final api = _NotifApi([_view('challenge_complete')]);
    await _pump(tester, api);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tapAndSettle(tester, l10n.profileNotifChallengeComplete);

    expect(api.read, ['n-challenge_complete']);
    final screen = tester.widget<ChallengeDetailScreen>(
      find.byType(ChallengeDetailScreen),
    );
    expect(screen.challengeId, 'c1');
    await teardown(tester);
  });

  testWidgets('tapping an achievement row shows the badges tab', (tester) async {
    final api = _NotifApi([_view('achievement')]);
    await _pump(tester, api);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byType(BadgeGrid), findsNothing);

    await tapAndSettle(tester, l10n.profileNotifAchievement);

    expect(api.read, ['n-achievement']);
    expect(find.byType(BadgeGrid), findsOneWidget);
  });
}
