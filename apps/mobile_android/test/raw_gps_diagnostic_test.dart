import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/raw_gps_diagnostic.dart';
import '../lib/screens/settings_screen.dart';

void main() {
  group('rawGpsDiagnosticAvailable', () {
    const prod = 'https://abc.supabase.co';
    const local = 'http://127.0.0.1:24321';

    test('a release build offers it only against a loopback backend', () {
      expect(
        rawGpsDiagnosticAvailable(
            backendUrl: prod,
            releaseBuild: true,
            platform: TargetPlatform.android),
        isFalse,
      );
      expect(
        rawGpsDiagnosticAvailable(
            backendUrl: null,
            releaseBuild: true,
            platform: TargetPlatform.android),
        isFalse,
      );
      expect(
        rawGpsDiagnosticAvailable(
            backendUrl: local,
            releaseBuild: true,
            platform: TargetPlatform.android),
        isTrue,
      );
    });

    test('a debug or profile build offers it against any backend', () {
      expect(
        rawGpsDiagnosticAvailable(
            backendUrl: prod,
            releaseBuild: false,
            platform: TargetPlatform.android),
        isTrue,
      );
    });

    test('never on iOS, which has one location provider', () {
      expect(
        rawGpsDiagnosticAvailable(
            backendUrl: local,
            releaseBuild: false,
            platform: TargetPlatform.iOS),
        isFalse,
      );
    });
  });

  group('settings switch', () {
    Future<Preferences> pumpSettings(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(
            preferences: prefs,
            heartRate: BleHeartRate(),
            treadmill: BleTreadmill(),
            devBackendUrl: 'https://abc.supabase.co',
          ),
        ),
      );
      return prefs;
    }

    testWidgets('defaults off and turns the stored switch on', (tester) async {
      final prefs = await pumpSettings(tester);
      final tile = find.byKey(const Key('settingsDevRawGps'));
      await tester.dragUntilVisible(
          tile, find.byType(ListView), const Offset(0, -200));
      expect(prefs.devRawGpsProvider, isFalse);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(find.text('Sim watch link'), findsNothing);
      await tester.tap(tile);
      await tester.pump();
      expect(prefs.devRawGpsProvider, isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });

    testWidgets('hidden on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpSettings(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -4000));
        await tester.pump();
        expect(find.byKey(const Key('settingsDevRawGps')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
