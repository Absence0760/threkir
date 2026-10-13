// The mobile inbox half of "a seat is held for you on a paid class"
// (migration 20270726000002, decisions § 1840). An event_waitlist_slot row
// must read its own sentence — titled when the event title is known — never
// the generic fallback, and must group per event like the other event kinds.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/notification_groups.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/screens/profile_screen.dart';

NotificationRow _slot({String id = 'n1', String eventId = 'e1'}) =>
    NotificationRow(
      id: id,
      userId: 'me',
      kind: 'event_waitlist_slot',
      eventId: eventId,
      createdAt: DateTime.utc(2026, 10, 13, 9),
      refunded: false,
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

  testWidgets('a held seat reads the titled waitlist sentence', (tester) async {
    await _pump(
      tester,
      _NotifApi([NotificationView(row: _slot(), eventTitle: 'Reformer')]),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l10n.profileNotifWaitlistSlotTitled('Reformer')),
      findsOneWidget,
    );
    expect(find.text(l10n.profileNotifGeneric('Someone')), findsNothing);
  });

  testWidgets('the untitled shape reads the untitled waitlist sentence', (
    tester,
  ) async {
    await _pump(tester, _NotifApi([NotificationView(row: _slot())]));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.profileNotifWaitlistSlot), findsOneWidget);
  });

  testWidgets('tapping a held seat opens the event it is held on', (
    tester,
  ) async {
    await _pump(
      tester,
      _NotifApi([
        NotificationView(
          row: _slot(eventId: 'e-reformer'),
          eventTitle: 'Reformer',
          eventClubSlug: 'studio',
        ),
      ]),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.profileNotifWaitlistSlotTitled('Reformer')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException();

    final screen = tester.widget<EventDetailScreen>(
      find.byType(EventDetailScreen),
    );
    expect(screen.eventId, 'e-reformer');
    expect(screen.clubSlug, 'studio');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  });

  testWidgets('a held seat with no club to address stays on the inbox', (
    tester,
  ) async {
    await _pump(tester, _NotifApi([NotificationView(row: _slot())]));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.profileNotifWaitlistSlot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
    expect(find.byType(EventDetailScreen), findsNothing);
  });

  test('offers on the same event group together, different events apart', () {
    final groups = groupNotifications([
      _slot(id: 'a'),
      _slot(id: 'b'),
      _slot(id: 'c', eventId: 'e2'),
    ], nowMs: DateTime.utc(2026, 10, 13, 9, 5).millisecondsSinceEpoch);
    expect(groups, hasLength(2));
  });

  test('every locale has its own held-seat sentence', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(
        l10n.profileNotifWaitlistSlotTitled('Reformer'),
        allOf(
          contains('Reformer'),
          isNot(l10n.profileNotifEventCancelTitled('Reformer')),
        ),
        reason: '$locale',
      );
      expect(
        l10n.profileNotifWaitlistSlot,
        isNot(l10n.profileNotifGeneric('Someone')),
        reason: '$locale',
      );
    }
  });
}
