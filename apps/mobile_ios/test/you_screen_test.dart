// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/parkrun_barcode_cache.dart';
import '../lib/preferences.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/screens/parkrun_barcode_screen.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/screens/you_screen.dart';
import 'pump_until.dart';

/// Signed-in fake so the identity header renders. [displayName] and
/// [unread] stand in for the two reads the header makes; [failProfile] makes
/// the profile read throw, as an offline read does.
class _FakeApi extends ApiClient {
  _FakeApi({this.displayName = 'Ada Lovelace', this.unread = 0});

  final String? displayName;
  final int unread;
  bool failProfile = false;

  @override
  String? get userId => 'u1';

  @override
  String? get userEmail => 'runner@test.com';

  @override
  Future<UserProfileRow?> fetchMyProfile() async {
    if (failProfile) throw Exception('offline');
    return UserProfileRow(profilePrivate: false, 
        id: 'u1', displayName: displayName, shadowHidden: false);
  }

  @override
  Future<int> fetchUnreadDmCount() async => unread;
}

/// Drives auth transitions: mutate [uid]/[email]/[name], then [emit] a tick
/// on the stream the AuthChangeAware mixin listens to (#223/#232).
class _SwitchableApi extends ApiClient {
  String? uid = 'u1';
  String? email = 'runner@test.com';
  String? name = 'Ada Lovelace';
  final _controller = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;

  @override
  String? get userEmail => email;

  @override
  Future<UserProfileRow?> fetchMyProfile() async => uid == null
      ? null
      : UserProfileRow(profilePrivate: false, id: uid!, displayName: name, shadowHidden: false);

  @override
  Future<int> fetchUnreadDmCount() async => 0;

  @override
  Stream<String?> get authUserChanges => _controller.stream;

  void emit() => _controller.add(uid);
}

void main() {
  final tmpDirs = <Directory>[];
  tearDown(() {
    for (final d in tmpDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tmpDirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    tmpDirs.add(d);
    return d;
  }

  Future<void> pump(
    WidgetTester tester, {
    ApiClient? api,
    Map<String, Object> initialPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('you_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('you_routes_'));
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tmp('you_gear_'));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: YouScreen(
        apiClient: api ?? _FakeApi(),
        preferences: prefs,
        runStore: runStore,
        routeStore: routeStore,
        gearStore: gearStore,
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the header names the runner, not their email',
      (tester) async {
    await pump(tester);
    await pumpUntil(
        tester, () => find.text('Ada Lovelace').evaluate().isNotEmpty,
        describe: 'the display name');
    expect(find.text('View profile'), findsOneWidget);
    // The email belongs to the Account screen; the header and the Account
    // row used to both print it.
    expect(find.text('runner@test.com'), findsNothing);
    // Settings section tiles fold in below.
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
  });

  testWidgets('a runner with no display name sees "Your profile"',
      (tester) async {
    await pump(tester, api: _FakeApi(displayName: null));
    await tester.pump();
    expect(find.text('Your profile'), findsOneWidget);
  });

  testWidgets('a failed profile read falls back to "Your profile"',
      (tester) async {
    await pump(tester, api: _FakeApi()..failProfile = true);
    await tester.pump();
    expect(find.text('Your profile'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
  });

  testWidgets("tapping the header pushes the runner's own ProfileScreen",
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('you-profile-header')));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<ProfileScreen>(find.byType(ProfileScreen)).userId,
      'u1',
    );
  });

  testWidgets('the header reacts to sign-out and an account switch (#223)',
      (tester) async {
    final api = _SwitchableApi();
    await pump(tester, api: api);
    await pumpUntil(
        tester, () => find.text('Ada Lovelace').evaluate().isNotEmpty,
        describe: "A's name");

    // Sign out (from anywhere — the account screen, a session expiry):
    // the header must drop the departed runner, not render them until
    // some unrelated rebuild.
    api.uid = null;
    api.email = null;
    api.emit();
    await tester.pump();
    await tester.pump();
    expect(find.text('Ada Lovelace'), findsNothing);
    expect(find.byKey(const ValueKey('you-profile-header')), findsNothing);

    // Sign in as someone else: the header shows B and routes to B's
    // profile, not A's (#232 instance 3 — stale viewerId).
    api.uid = 'u2';
    api.email = 'other@test.com';
    api.name = 'Grace Hopper';
    api.emit();
    await pumpUntil(
        tester, () => find.text('Grace Hopper').evaluate().isNotEmpty,
        describe: "B's name");
    await tester.tap(find.byKey(const ValueKey('you-profile-header')));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<ProfileScreen>(find.byType(ProfileScreen)).userId,
      'u2',
    );
  });

  testWidgets('the inbox icon shows and announces the unread count',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, api: _FakeApi(unread: 3));
    final icon = find.byKey(const ValueKey('you-messages'));
    await pumpUntil(
      tester,
      () => find
          .descendant(of: icon, matching: find.text('3'))
          .evaluate()
          .isNotEmpty,
      describe: 'the unread badge',
    );
    // One merged node: the count is read as the button's value, not as a
    // stray "3" after it.
    final data = tester.getSemantics(icon).getSemanticsData();
    expect(data.tooltip, 'Messages');
    expect(data.value, '3 unread messages');
    expect(data.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('no badge with nothing unread', (tester) async {
    await pump(tester, api: _FakeApi(unread: 0));
    await tester.pump();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('a settings tile drills into its sub-screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Preferences'));
    // Let the push route transition complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The Preferences sub-screen pushed over You — its own AppBar (with a
    // back button) is up, which a top-level tab screen never shows.
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('the Messages entry opens the inbox, and only when signed in',
      (tester) async {
    final api = _SwitchableApi();
    await pump(tester, api: api);
    final tile = find.byKey(const ValueKey('you-messages'));
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MessagesScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(MessagesScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    api.uid = null;
    api.emit();
    await tester.pump();
    await tester.pump();
    expect(tile, findsNothing);
  });

  testWidgets('no parkrun barcode shortcut until this device holds a number',
      (tester) async {
    await pump(tester);
    await tester.pump();
    expect(find.byKey(const ValueKey('you-parkrun-barcode')), findsNothing);
  });

  testWidgets('the parkrun barcode shortcut opens the barcode screen',
      (tester) async {
    await pump(tester, initialPrefs: {
      ParkrunBarcodeCache.storageKey:
          jsonEncode({'user_id': 'u1', 'number': 'A123456'}),
    });
    final tile = find.byKey(const ValueKey('you-parkrun-barcode'));
    await pumpUntil(
      tester,
      () => tile.evaluate().isNotEmpty,
      describe: 'the barcode shortcut',
    );
    expect(find.descendant(of: tile, matching: find.text('A123456')),
        findsOneWidget);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ParkrunBarcodeScreen), findsOneWidget);
  });
}
