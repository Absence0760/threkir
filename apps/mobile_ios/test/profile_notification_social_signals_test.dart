// The mobile inbox half of reactions, comment likes and mentions
// (migration 20270826000001, decisions § 1971). Each kind must read its own
// sentence with the actor's name, never the generic fallback.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';

NotificationView _view(String kind) => NotificationView(
      row: NotificationRow(
        id: 'n-$kind',
        userId: 'me',
        actorId: 'u-ana',
        kind: kind,
        runId: 'r1',
        createdAt: DateTime.utc(2026, 10, 13, 9),
        refunded: false,
      ),
      actor: const PublicProfile(id: 'u-ana', displayName: 'Ana', avatarUrl: null),
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
    'reaction': (l) => l.profileNotifReaction('Ana'),
    'comment_like': (l) => l.profileNotifCommentLike('Ana'),
    'mention': (l) => l.profileNotifMention('Ana'),
  };
  for (final entry in cases.entries) {
    testWidgets('a ${entry.key} row reads its own sentence', (tester) async {
      await _pump(tester, _NotifApi([_view(entry.key)]));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(entry.value(l10n)), findsOneWidget);
      expect(find.text(l10n.profileNotifGeneric('Ana')), findsNothing);
    });
  }
}
