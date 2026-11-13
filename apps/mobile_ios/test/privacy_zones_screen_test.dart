import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/privacy_zones_screen.dart';
import '../lib/widgets/map_attribution.dart';
import '../lib/settings_sync.dart';
import 'package:api_client/api_client.dart' show SettingsService;

Position _fakePosition({double lat = 37.53, double lng = -77.45}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Future<({SettingsSyncService sync})> _makeSync() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (sync: SettingsSyncService(preferences: prefs));
}

Future<void> _pump(
  WidgetTester tester, {
  required SettingsSyncService sync,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PrivacyZonesScreen(settingsSync: sync),
    ),
  );
  // Drain pending timers from flutter_map_cache + Dio so the
  // post-test "Timer is still pending" guard doesn\'t fire. The
  // May 2026 audit wired the screen onto the shared
  // CachedTileProvider; that provider schedules background timers
  // (cache eviction / Dio interceptor) that the bare single-pump
  // pattern doesn\'t flush.
  await tester.pump(const Duration(seconds: 1));
}

// A map that reaches the screen bottom drew its credit under the system
// navigation bar (route builder field report; same root cause here).
void simulateNavBar(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 48);
  tester.view.viewPadding = const FakeViewPadding(bottom: 48);
  addTearDown(tester.view.reset);
}

void expectCreditsAboveNavBar(WidgetTester tester) {
  final credits = find.descendant(
      of: find.byType(MapAttribution), matching: find.byType(Text));
  expect(credits, findsWidgets);
  for (final credit in credits.evaluate()) {
    final rect = tester.getRect(find.byWidget(credit.widget));
    expect(rect.bottom, lessThanOrEqualTo(780 - 48),
        reason: 'credit $rect is under the navigation bar');
  }
}

void main() {
  group('PrivacyZonesScreen — initial render', () {
    testWidgets('the map credit stays above the navigation bar',
        (tester) async {
      simulateNavBar(tester);
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expectCreditsAboveNavBar(tester);
    });

    // #1374 A11Y-4: the radius slider read "33%, slider" with no name.
    testWidgets('the radius slider is named Radius and reads its value in metres',
        (tester) async {
      final handle = tester.ensureSemantics();
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      final data = tester.getSemantics(find.byType(Slider)).getSemanticsData();
      expect(data.label, contains('Radius'));
      expect(data.value, matches(RegExp(r'^\d+ m$')));
      expect(data.value, isNot(contains('%')));
      expect(data.increasedValue, matches(RegExp(r'^\d+ m$')));
      handle.dispose();
    });

    // #1374 round 3: the phone once offered 50 m; both platforms now offer
    // 100-1000 m, and a zone saved smaller is read as 100 m, never less.
    testWidgets('the slider offers 100-1000 m, as web does', (tester) async {
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 100);
      expect(slider.max, 1000);
      expect(find.byKey(const ValueKey('privacy-zones-raised-to-floor')),
          findsNothing);
    });

    testWidgets('a zone stored under 100 m is drawn at 100 m and says so',
        (tester) async {
      final service = _ZonesService([
        {'lat': 37.53, 'lng': -77.45, 'radius_m': 50},
        {'lat': 37.6, 'lng': -77.5, 'radius_m': 300},
      ]);
      await _pump(tester, sync: _ZonesSync(service));
      await tester.pump();
      final circles = tester
          .widget<CircleLayer>(find.byType(CircleLayer))
          .circles
          .map((c) => c.radius)
          .toList();
      expect(circles, [100, 300]);
      expect(
          find.text('1 zone was smaller than 100 m and now covers 100 m, '
              'the smallest a zone can be.'),
          findsOneWidget);
    });

    testWidgets('renders the Privacy zones app-bar title', (tester) async {
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expect(find.text('Privacy zones'), findsOneWidget);
    });

    testWidgets('renders the Save action in the app bar', (tester) async {
      // Reason: edits to the zone list are non-destructive until Save
      // is tapped — the action must be present so users can commit.
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('renders a place-search field + a Locate-me FAB', (
      tester,
    ) async {
      // Both were missing — the picker had no way to navigate to the
      // user's area, so on a self-hosted-tiles setup it opened on a
      // far-away default and looked like a blank map.
      final s = await _makeSync();
      await _pump(tester, sync: s.sync);
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search places…'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('typing surfaces place results (Nominatim fallback)', (
      tester,
    ) async {
      final s = await _makeSync();
      Future<String> stub(Uri _) async => jsonEncode([
        {
          'display_name': 'Richmond, Virginia',
          'lat': '37.5407',
          'lon': '-77.4360',
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacyZonesScreen(
            settingsSync: s.sync,
            geocodingFetcher: stub,
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search places…'),
        'Richmond',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Richmond, Virginia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Locate FAB invokes the locate seam without crashing', (
      tester,
    ) async {
      final s = await _makeSync();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrivacyZonesScreen(
            settingsSync: s.sync,
            locateFn: () async {
              calls++;
              return _fakePosition();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(calls, greaterThanOrEqualTo(1));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('PrivacyZonesScreen — unsaved-changes guard', () {
    // Pushes the screen over a root route so a guarded pop can be observed
    // returning to the root. pumpAndSettle hangs on the map, so pump fixed
    // durations instead (per the mobile-test gotcha).
    Future<void> pushScreen(
      WidgetTester tester,
      SettingsSyncService sync,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PrivacyZonesScreen(settingsSync: sync),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('back with a freshly drawn zone shows the discard confirm', (
      tester,
    ) async {
      final s = await _makeSync();
      await pushScreen(tester, s.sync);

      // Drawing a zone (map tap) marks the editor dirty.
      await tester.tap(find.byType(FlutterMap));
      await tester.pump(const Duration(seconds: 1));

      // System back is intercepted by the PopScope guard.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Discard changes?'), findsOneWidget);
      // Cancelling keeps the editor mounted (nothing discarded).
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PrivacyZonesScreen), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('confirming discard leaves the editor', (tester) async {
      final s = await _makeSync();
      await pushScreen(tester, s.sync);
      await tester.tap(find.byType(FlutterMap));
      await tester.pump(const Duration(seconds: 1));

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Popped back to the root route.
      expect(find.byType(PrivacyZonesScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('back with no edits pops without a confirm', (tester) async {
      final s = await _makeSync();
      await pushScreen(tester, s.sync);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(PrivacyZonesScreen), findsNothing);
    });
  });

  // Locate me is MapFirstPage's map control, above the zone footer: as a
  // Scaffold FAB it sat on Clear all (issue #1374 IK-3).
  group('PrivacyZonesScreen — insets', () {
    Future<void> pumpOn(WidgetTester tester, Size size, FakeViewPadding bar,
        {double textScale = 1}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = bar;
      tester.view.viewPadding = bar;
      addTearDown(tester.view.reset);
      final s = await _makeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: PrivacyZonesScreen(settingsSync: s.sync),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      // Draw a zone so the count + Clear all footer shows.
      await tester.tapAt(tester.getTopLeft(find.byType(FlutterMap)) +
          const Offset(24, 24));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> expectClearAllReachable(WidgetTester tester, Size size,
        {double bottomBar = 0, double sideBar = 0}) async {
      expect(tester.takeException(), isNull);
      final clear = find.text('Clear all');
      await tester.ensureVisible(clear);
      await tester.pump();
      expect(clear.hitTestable(), findsOneWidget);
      final rect = tester.getRect(clear);
      final locate = tester.getRect(find.byType(FloatingActionButton));
      expect(locate.overlaps(rect), isFalse,
          reason: 'Locate me $locate covers Clear all $rect');
      expect(rect.bottom, lessThanOrEqualTo(size.height - bottomBar));
      expect(rect.right, lessThanOrEqualTo(size.width - sideBar));
      expect(locate.right, lessThanOrEqualTo(size.width - sideBar));
    }

    testWidgets('320 dp, 2x text, 3-button bar: Locate me sits above Clear all',
        (tester) async {
      const size = Size(320, 640);
      await pumpOn(tester, size, const FakeViewPadding(bottom: 48),
          textScale: 2);
      await expectClearAllReachable(tester, size, bottomBar: 48);
    });

    testWidgets('landscape: the controls and the footer clear a side bar',
        (tester) async {
      const size = Size(780, 360);
      await pumpOn(tester, size, const FakeViewPadding(right: 48));
      await expectClearAllReachable(tester, size, sideBar: 48);
    });
  });
}

class _ZonesService extends SettingsService {
  _ZonesService(this._zones)
      : super(deviceId: 'test-device', platform: 'android');
  final List<Map<String, dynamic>> _zones;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      key == 'privacy_zones' ? _zones as T : fallback;
}

class _ZonesSync extends SettingsSyncService {
  _ZonesSync(this._service) : super(preferences: Preferences());
  final SettingsService _service;

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;
}
