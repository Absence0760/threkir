// The mobile half of "the cancel notification does not say the registrant
// was refunded". A paid registrant's event_cancel row carries `refunded`
// (migration 20270725000002) and must read the refund sentence; a free
// attendee's must not. The rendered text is the contract, so this renders it.
// Mark-all-read rebuilds each row, the one place the flag could be dropped,
// so that path is pinned too.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/profile_screen.dart';

NotificationRow _cancel({required bool refunded}) => NotificationRow(
  id: 'n1',
  userId: 'me',
  kind: 'event_cancel',
  eventId: 'e1',
  createdAt: DateTime.utc(2026, 10, 13, 9),
  refunded: refunded,
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

  testWidgets('a paid registrant is told the payment is being refunded', (
    tester,
  ) async {
    await _pump(
      tester,
      _NotifApi([
        NotificationView(row: _cancel(refunded: true), eventTitle: 'Barre'),
      ]),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.profileNotifEventCancelRefundedTitled('Barre')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.profileNotifEventCancelTitled('Barre')),
      findsNothing,
    );
  });

  testWidgets('the untitled shape reads the untitled refund sentence', (
    tester,
  ) async {
    await _pump(
      tester,
      _NotifApi([NotificationView(row: _cancel(refunded: true))]),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.profileNotifEventCancelRefunded), findsOneWidget);
  });

  testWidgets('a free attendee gets the plain cancel sentence', (tester) async {
    await _pump(
      tester,
      _NotifApi([
        NotificationView(row: _cancel(refunded: false), eventTitle: 'Barre'),
      ]),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.profileNotifEventCancelTitled('Barre')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.profileNotifEventCancelRefundedTitled('Barre')),
      findsNothing,
    );
  });

  testWidgets('marking all read keeps the refund sentence', (tester) async {
    await _pump(
      tester,
      _NotifApi([
        NotificationView(row: _cancel(refunded: true), eventTitle: 'Barre'),
      ]),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.profileMarkAllRead));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(l10n.profileNotifEventCancelRefundedTitled('Barre')),
      findsOneWidget,
    );
  });

  test('every locale says something different for a paid cancel', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(
        l10n.profileNotifEventCancelRefunded,
        isNot(l10n.profileNotifEventCancel),
        reason: '$locale',
      );
      expect(
        l10n.profileNotifEventCancelRefundedTitled('Barre'),
        allOf(
          contains('Barre'),
          isNot(l10n.profileNotifEventCancelTitled('Barre')),
        ),
        reason: '$locale',
      );
    }
  });
}
