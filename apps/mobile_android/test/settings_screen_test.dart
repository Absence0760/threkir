import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show SettingsList;
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/help_guides.dart';
import '../lib/help_loader.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/help_screen.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/screens/settings_about_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/screens/settings_pro_screen.dart';
import '../lib/screens/settings_screen.dart';

late Directory _runsDir;

Future<({LocalRunStore runStore, Preferences prefs, BleHeartRate heartRate})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('settings_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  return (runStore: runStore, prefs: prefs, heartRate: BleHeartRate());
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required BleHeartRate heartRate,
  LocalRunStore? runStore,
  LocalGearStore? gearStore,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The You tab supplies the scaffold; the list is its body.
      home: Scaffold(
        body: SettingsScreen(
          preferences: prefs,
          heartRate: heartRate,
          treadmill: BleTreadmill(),
          runStore: runStore,
          gearStore: gearStore,
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('SettingsScreen (landing)', () {
    testWidgets('is a body, not a page: no AppBar and no Scaffold of its own',
        (tester) async {
      // It used to be a second Scaffold + SafeArea nested inside You's.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(SettingsList), findsOneWidget);
    });

    testWidgets("web's four groups in web's order", (tester) async {
      final s = await _makeStores();
      tester.view.physicalSize = const Size(400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.pumpAndSettle();
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('PROFILE'), lessThan(y('Account')));
      expect(y('Safety contacts'), lessThan(y('PREFERENCES')));
      expect(y('PREFERENCES'), lessThan(y('Units & display')));
      expect(y('Notifications'), lessThan(y('APPS & DATA')));
      expect(y('APPS & DATA'), lessThan(y('Integrations')));
      expect(y('Gear'), lessThan(y('ACCOUNT & LEGAL')));
      expect(y('ACCOUNT & LEGAL'), lessThan(y('Pro & support')));
      // The old Training and Settings eyebrows are gone with the groups
      // that did not predict their rows.
      expect(find.text('TRAINING'), findsNothing);
      expect(find.text('SETTINGS'), findsNothing);
    });

    testWidgets('renders every tab tile', (tester) async {
      final s = await _makeStores();
      tester.view.physicalSize = const Size(400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.pumpAndSettle();
      for (final label in const [
        'Account',
        'Body metrics',
        'Units & display',
        'Recording & voice',
        'Training',
        'Privacy & sharing',
        'Notifications',
        'Integrations',
        'Signed-in devices',
        'Gear',
        'Pro & support',
        'About & updates',
        'Help',
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: '$label tab must render on the landing');
      }
    });

    testWidgets('Signed-in devices tile surfaces a sign-in subtitle when signed-out',
        (tester) async {
      // Devices is server-only (user_device_settings table); the tile
      // stays tappable but the subtitle tells the user sign-in is
      // needed. Gear, by contrast, now works fully offline via
      // LocalGearStore, so its subtitle stays neutral regardless of
      // sign-in state.
      // A gear store must be wired for this test to say anything about
      // sign-out: without one the tile is disabled for a different reason
      // entirely (#666 I16), and the pre-I16 code hid that by leaving `onTap`
      // non-null while doing nothing when tapped.
      final s = await _makeStores();
      await _pump(
        tester,
        prefs: s.prefs,
        heartRate: s.heartRate,
        gearStore: LocalGearStore(),
      );
      await tester.scrollUntilVisible(find.text('Signed-in devices'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final devices = tester.widget<ListTile>(find.ancestor(
        of: find.text('Signed-in devices'),
        matching: find.byType(ListTile),
      ));
      expect(devices.onTap, isNotNull,
          reason: 'Devices tile must stay tappable when signed-out');
      expect(find.text("Sign in to see where you're signed in"), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Gear'), 200,
          scrollable: find.byType(Scrollable).first);
      final gear = tester.widget<ListTile>(find.ancestor(
        of: find.text('Gear'),
        matching: find.byType(ListTile),
      ));
      expect(gear.onTap, isNotNull,
          reason: 'Gear tile must stay tappable when signed-out');
      expect(find.text('Track shoes + bikes and per-item mileage'),
          findsOneWidget,
          reason:
              'Gear is offline-capable now — no sign-in copy on the tile.');
    });

    testWidgets('Account tile pushes SettingsAccountScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, heartRate: s.heartRate, runStore: s.runStore);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsAccountScreen), findsOneWidget);
    });

    testWidgets('a Preferences page row opens that page', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(find.text('Privacy & sharing'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Privacy & sharing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy & sharing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SettingsPreferencesScreen>(
                find.byType(SettingsPreferencesScreen))
            .page,
        PreferencesPage.privacy,
      );
    });

    testWidgets('Pro & support tile pushes SettingsProScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(
        find.text('Pro & support'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Pro & support'));
      await tester.pump();
      await tester.tap(find.text('Pro & support'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsProScreen), findsOneWidget);
    });

    testWidgets('About & updates tile pushes SettingsAboutScreen',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(
        find.text('About & updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('About & updates'));
      await tester.pump();
      await tester.tap(find.text('About & updates'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsAboutScreen), findsOneWidget);
    });
  });

  group('SettingsScreen Help entry', () {
    tearDown(() => helpLibraryLoader = loadHelpLibraryCached);

    testWidgets('the Help tile opens the guide list', (tester) async {
      final library = HelpLibrary.parse(
          File('test/fixtures/help_guides.json').readAsStringSync())!;
      helpLibraryLoader = (_) => Future.value(library);
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(
        find.text('Help'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('How races, classes, clubs and the app work'),
          findsOneWidget);
      await tester.ensureVisible(find.text('Help'));
      await tester.pump();
      await tester.tap(find.text('Help'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(HelpScreen), findsOneWidget);
      expect(find.text('Racing an event'), findsOneWidget);
    });
  });

  group('signed-out affordances', () {
    testWidgets('Sentry opt-out renders when signed-out (local data)',
        (tester) async {
      // It moved from Account to Privacy & sharing with web's page split.
      final s = await _makeStores();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPreferencesScreen(
          page: PreferencesPage.privacy,
          apiClient: null,
          preferences: s.prefs,
          settingsSync: null,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Send error reports'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Send error reports'), findsOneWidget,
          reason: 'Sentry opt-out is a local GDPR control — must be '
              'reachable without an account.');
    });
  });
}
