// Marking a notification read must change its read stamp and nothing else.
// The inbox used to rebuild each row by hand on mark-read / mark-all-read,
// and that list had fallen behind the table: it dropped plan_id, club_id,
// achievement_id, challenge_id, event_instance_start and the view's
// clubName / clubSlug, so a read row lost the link to its target and a club
// post fell back to its unnamed sentence (decisions § 1836).

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';

final _created = DateTime.utc(2026, 10, 13, 9);

NotificationRow _fullRow({DateTime? readAt}) => NotificationRow(
  id: 'n1',
  userId: 'me',
  actorId: 'a1',
  kind: 'club_post',
  runId: 'r1',
  commentId: 'c1',
  readAt: readAt,
  createdAt: _created,
  eventId: 'e1',
  planId: 'p1',
  clubId: 'club1',
  emailSentAt: DateTime.utc(2026, 10, 13, 10),
  eventInstanceStart: DateTime.utc(2026, 10, 20, 7),
  activityKind: 'run',
  activityId: 'act1',
  webPushSentAt: DateTime.utc(2026, 10, 13, 11),
  achievementId: 'ach1',
  challengeId: 'ch1',
  nativePushSentAt: DateTime.utc(2026, 10, 13, 12),
  refunded: true,
);

NotificationView _clubPost({DateTime? readAt}) => NotificationView(
  row: _fullRow(readAt: readAt),
  actor: const PublicProfile(id: 'a1', displayName: 'Ana'),
  runDistanceM: 5000,
  commentExcerpt: 'see you there',
  eventTitle: 'Hill reps',
  eventClubSlug: 'hill-club',
  clubName: 'Hill Club',
  clubSlug: 'hill-club',
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
  Future<List<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<AchievementRow>> fetchUserBadges(String userId) async => const [];

  @override
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async => _views;

  @override
  Future<void> markAllNotificationsRead() async {}
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

void main() {
  setUpAll(_ensureSupabase);

  test('markedRead changes read_at and carries every other column', () {
    final at = DateTime.utc(2026, 10, 14, 8);
    final before = _clubPost();
    final after = before.markedRead(at);

    expect(after.row.readAt, at);
    // Compared through the generated toJson, so a column added later is
    // covered without this test naming it.
    final expected = before.row.toJson()
      ..[NotificationRow.colReadAt] = at.toIso8601String();
    expect(after.row.toJson(), expected);

    expect(after.actor, same(before.actor));
    expect(after.runDistanceM, before.runDistanceM);
    expect(after.commentExcerpt, before.commentExcerpt);
    expect(after.eventTitle, before.eventTitle);
    expect(after.eventClubSlug, before.eventClubSlug);
    expect(after.clubName, 'Hill Club');
    expect(after.clubSlug, 'hill-club');
  });

  test('markedRead keeps the original stamp on an already-read row', () {
    final first = DateTime.utc(2026, 10, 13, 12);
    final view = _clubPost(readAt: first);
    expect(view.markedRead(DateTime.utc(2026, 10, 14)).row.readAt, first);
  });

  testWidgets('marking all read keeps a club post named and linked', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileScreen(
          api: _NotifApi([_clubPost()]),
          userId: 'me',
          initialTab: ProfileTab.notifications,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final named = l10n.profileNotifClubPostNamed('Ana', 'Hill Club');
    expect(find.text(named), findsOneWidget);

    await tester.tap(find.text(l10n.profileMarkAllRead));
    await tester.pump();
    await tester.pump();

    expect(find.text(named), findsOneWidget);
    expect(find.text(l10n.profileNotifClubPost('Ana')), findsNothing);
  });
}
