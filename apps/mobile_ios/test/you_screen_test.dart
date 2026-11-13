// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart'
    show IncomingFollowRequest, UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show SectionHeader;

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/parkrun_barcode_cache.dart';
import '../lib/preferences.dart';
import '../lib/screens/parkrun_barcode_screen.dart';
import '../lib/screens/follow_requests_screen.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/screens/you_screen.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

/// Signed-in fake so the identity card renders. [displayName] stands in for
/// the profile read the card makes; [failProfile] makes it throw, as an
/// offline read does.
class _FakeApi extends ApiClient {
  _FakeApi({this.displayName = 'Ada Lovelace'});

  final String? displayName;
  bool failProfile = false;

  @override
  String? get userId => 'u1';

  @override
  String? get userEmail => 'runner@test.com';

  @override
  Future<UserProfileRow?> fetchMyProfile() async {
    if (failProfile) throw Exception('offline');
    return UserProfileRow(
        profilePrivate: false,
        id: 'u1',
        displayName: displayName,
        shadowHidden: false);
  }

  @override
  Future<List<IncomingFollowRequest>> fetchIncomingFollowRequests() async =>
      const [];
}

/// Signed out, but with a client to sign in through.
class _SignedOutApi extends ApiClient {
  @override
  String? get userId => null;

  @override
  String? get userEmail => null;
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
      : UserProfileRow(
          profilePrivate: false, id: uid!, displayName: name, shadowHidden: false);

  @override
  Stream<String?> get authUserChanges => _controller.stream;

  void emit() => _controller.add(uid);
}

/// A sync wired but with no server bag, so the Privacy zones row (which
/// needs a sync to save into) is on the Privacy page.
class _SyncedNoBag extends SettingsSyncService {
  _SyncedNoBag(Preferences prefs) : super(preferences: prefs);

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;
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

  late AppLocalizations en;
  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> pump(
    WidgetTester tester, {
    ApiClient? api,
    Map<String, Object> initialPrefs = const {},
    Size? size,
    double textScale = 1.0,
    Locale locale = const Locale('en'),
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
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: YouScreen(
        apiClient: api ?? _FakeApi(),
        preferences: prefs,
        runStore: runStore,
        routeStore: routeStore,
        gearStore: gearStore,
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
        settingsSync: _SyncedNoBag(prefs),
      ),
    ));
    await tester.pump();
  }

  /// Group eyebrows top to bottom, read off geometry on a page tall enough
  /// to lay the whole list out.
  List<String> groupLabels(WidgetTester tester) {
    final found = <(double, String)>[
      for (final e in find.byType(SectionHeader).evaluate())
        (
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
          (e.widget as SectionHeader).label,
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found) f.$2];
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('settings-search')),
          matching: find.byType(TextField),
        ),
        text);
    await tester.pump();
  }

  group('the page', () {
    testWidgets('is titled You, then the identity card, then the search',
        (tester) async {
      await pump(tester, size: const Size(400, 3000));
      final title = find.text(en.navYou);
      final card = find.byKey(const ValueKey('you-identity-card'));
      final field = find.byKey(const ValueKey('settings-search'));
      expect(title, findsOneWidget);
      expect(card, findsOneWidget);
      expect(field, findsOneWidget);
      expect(tester.getTopLeft(title).dy, lessThan(tester.getTopLeft(card).dy));
      expect(tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(field).dy));
    });

    testWidgets("web's groups, in web's order", (tester) async {
      await pump(tester, size: const Size(400, 3000));
      expect(groupLabels(tester), [
        en.settingsSectionProfile,
        en.prefsTitle,
        en.settingsSectionAppsData,
        en.settingsSectionAccountLegal,
      ]);
      // Preferences is its five pages, listed here rather than behind one
      // more tap.
      for (final page in PreferencesPage.values) {
        expect(find.text(preferencesPageTitle(en, page)), findsOneWidget);
      }
    });

    testWidgets('coaching, guided runs and messages are not on You',
        (tester) async {
      // Owner decision (issue #1374): Athletes & coaches and Guided runs
      // live on the Coach, Messages on Social.
      await pump(tester, size: const Size(400, 3000));
      expect(find.text(en.coachingTitle), findsNothing);
      expect(find.text(en.guidedRunsTitle), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      expect(find.byKey(const ValueKey('you-messages')), findsNothing);
    });

    testWidgets('fits a 320 dp phone at 2x text', (tester) async {
      await pump(tester, size: const Size(320, 640), textScale: 2.0);
      await pumpUntil(
          tester, () => find.text('Ada Lovelace').evaluate().isNotEmpty,
          describe: 'the display name');
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(find.text(en.helpTitle), findsOneWidget);
    });
  });

  // Issue #1374 TO-6: the whole of You at the worst case, in every locale.
  worstCaseTestWidgets('You', (tester, locale) async {
    await pump(tester, size: kWorstCasePhone, textScale: kWorstCaseTextScale, locale: locale);
    useWorstCasePhone(tester);
    await pumpUntil(
        tester, () => find.text('Ada Lovelace').evaluate().isNotEmpty,
        describe: 'the display name');
    await walkScrollable(tester, find.byType(Scrollable).first, 'You');
  });

  group('the identity card', () {
    testWidgets('names the runner, not their email', (tester) async {
      await pump(tester);
      await pumpUntil(
          tester, () => find.text('Ada Lovelace').evaluate().isNotEmpty,
          describe: 'the display name');
      expect(find.text('View profile'), findsOneWidget);
      // The email belongs to the Account screen; the card and the Account
      // row used to both print it.
      expect(find.text('runner@test.com'), findsNothing);
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

    testWidgets("tapping it pushes the runner's own ProfileScreen",
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

    testWidgets('Edit profile opens the name and photo editor',
        (tester) async {
      // Your own profile had no edit; the name and avatar were three taps
      // away in Account (issue #1374 finding 10).
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('you-edit-profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SettingsAccountScreen), findsOneWidget);
    });

    testWidgets('reacts to sign-out and an account switch (#223)',
        (tester) async {
      final api = _SwitchableApi();
      await pump(tester, api: api);
      await pumpUntil(
          tester, () => find.text('Ada Lovelace').evaluate().isNotEmpty,
          describe: "A's name");

      // Sign out (from anywhere — the account screen, a session expiry):
      // the card must drop the departed runner, not render them until some
      // unrelated rebuild.
      api.uid = null;
      api.email = null;
      api.emit();
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(find.byKey(const ValueKey('you-profile-header')), findsNothing);
      expect(find.byKey(const ValueKey('you-sign-in-card')), findsOneWidget);

      // Sign in as someone else: the card shows B and routes to B's
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

    testWidgets('signed out, a sign-in prompt takes its place',
        (tester) async {
      await pump(tester, api: _SignedOutApi());
      expect(find.byKey(const ValueKey('you-identity-card')), findsNothing);
      expect(find.byKey(const ValueKey('you-sign-in-card')), findsOneWidget);
      expect(find.text(en.settingsAccountSignIn), findsOneWidget);
    });
  });

  group('reach', () {
    testWidgets('privacy zones are two taps from You', (tester) async {
      await pump(tester, size: const Size(400, 3000));
      await tester.tap(find.byKey(const ValueKey('you-prefs-privacy')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsPreferencesScreen>(
                find.byType(SettingsPreferencesScreen))
            .page,
        PreferencesPage.privacy,
      );
      expect(find.byKey(const ValueKey('prefs-privacy-zones')), findsOneWidget);
    });

    testWidgets('Follow requests are a row in Profile, signed in',
        (tester) async {
      await pump(tester, size: const Size(400, 3000));
      await tester.tap(find.byKey(const ValueKey('you-follow-requests')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FollowRequestsScreen), findsOneWidget);
    });

    testWidgets('Follow requests are not offered signed out', (tester) async {
      await pump(tester, api: _SignedOutApi(), size: const Size(400, 3000));
      expect(find.byKey(const ValueKey('you-follow-requests')), findsNothing);
    });
  });

  group('the settings search', () {
    testWidgets('finds a row on a Preferences page and opens that page',
        (tester) async {
      await pump(tester, size: const Size(400, 3000));
      await search(tester, 'zones');
      final hit = find.byKey(ValueKey(
          'settings-search-result-${en.privacyZonesTitle}'));
      expect(hit, findsOneWidget);
      // The result names the page it is on, and the groups give way.
      expect(
          find.descendant(of: hit, matching: find.text(en.prefsPagePrivacy)),
          findsOneWidget);
      expect(find.byType(SectionHeader), findsNothing);
      // Case is not what the runner remembers.
      await search(tester, en.prefsHrZones.toUpperCase());
      expect(find.byKey(ValueKey('settings-search-result-${en.prefsHrZones}')),
          findsOneWidget);

      await search(tester, 'zones');
      await tester.tap(hit);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsPreferencesScreen>(
                find.byType(SettingsPreferencesScreen))
            .page,
        PreferencesPage.privacy,
      );
    });

    testWidgets("finds You's own rows too", (tester) async {
      await pump(tester, size: const Size(400, 3000));
      await search(tester, 'devices');
      expect(
          find.byKey(ValueKey('settings-search-result-${en.devicesTitle}')),
          findsOneWidget);
    });

    testWidgets('says so when nothing matches, and clearing brings the '
        'groups back', (tester) async {
      await pump(tester, size: const Size(400, 3000));
      await search(tester, 'qqqzzz');
      expect(find.byKey(const ValueKey('settings-search-empty')),
          findsOneWidget);
      expect(find.text(en.settingsSearchNoResults('qqqzzz')), findsOneWidget);

      await tester.tap(find.byTooltip(en.commonClearSearch));
      await tester.pump();
      expect(find.byKey(const ValueKey('settings-search-empty')),
          findsNothing);
      expect(groupLabels(tester), isNotEmpty);
    });
  });

  group('the parkrun barcode shortcut', () {
    testWidgets('is absent until this device holds a number', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(find.byKey(const ValueKey('you-parkrun-barcode')), findsNothing);
    });

    testWidgets('opens the barcode screen', (tester) async {
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
  });
}
