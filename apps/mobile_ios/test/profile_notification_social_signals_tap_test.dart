// Tapping a comment-like or a mention row in the mobile inbox (decisions
// § 1971) marks it read and opens the run it names in the public view, which
// is the one a recipient who does not own the run can read.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/screens/public_run_screen.dart';

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
}
