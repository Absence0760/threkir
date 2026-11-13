import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/pre_run_status.dart';
import '../lib/tile_cache.dart';
import '../lib/widgets/live_run_map.dart';
import '../lib/widgets/pre_run_status.dart';
import 'pump_until.dart';
import 'worst_case_layout.dart';

// The idle Run page used to end at its setup row, so a phone with location
// off, permission refused or no fix yet showed a blank area down to the
// bottom bar and said nothing until START. These pin each state the page now
// shows in that area, and what each one's action reaches.

Position _position({double accuracy = 5, double lat = 37.42}) => Position(
      latitude: lat,
      longitude: -122.08,
      timestamp: DateTime.utc(2026, 11, 13),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _FakeProbe implements PreRunProbe {
  bool servicesOn = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  bool precise = true;
  Position? lastKnown;
  final Map<PreRunExtra, ph.PermissionStatus?> extras = {
    PreRunExtra.activityRecognition: ph.PermissionStatus.granted,
    PreRunExtra.notifications: ph.PermissionStatus.granted,
  };
  ph.PermissionStatus extraAfterRequest = ph.PermissionStatus.granted;

  final calls = <String>[];
  final _fixes = StreamController<Position>.broadcast();
  int listens = 0;

  bool get listening => _fixes.hasListener;
  void emit(Position p) => _fixes.add(p);

  @override
  Future<bool> locationServiceEnabled() async => servicesOn;

  @override
  Future<LocationPermission> locationPermission() async => permission;

  @override
  Future<LocationPermission> requestLocationPermission() async {
    calls.add('requestLocationPermission');
    permission = afterRequest;
    return permission;
  }

  @override
  Future<bool> preciseLocation() async => precise;

  @override
  Future<Position?> lastKnownPosition() async => lastKnown;

  @override
  Stream<Position> positions() {
    listens++;
    return _fixes.stream;
  }

  @override
  Future<ph.PermissionStatus?> extraStatus(PreRunExtra extra) async =>
      extras[extra];

  @override
  Future<ph.PermissionStatus> requestExtra(PreRunExtra extra) async {
    calls.add('request:${extra.name}');
    extras[extra] = extraAfterRequest;
    return extraAfterRequest;
  }

  @override
  Future<void> openLocationSettings() async =>
      calls.add('openLocationSettings');

  @override
  Future<void> openAppSettings() async => calls.add('openAppSettings');
}

/// A tile provider whose every tile fails to decode, as a dead tile server's
/// error page would.
class _BrokenTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(utf8.encode('not a png')));
}

final _l10n = lookupAppLocalizations(const Locale('en'));

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 13, 7);
  DateTime call() => now;
}

Future<void> _pump(
  WidgetTester tester,
  _FakeProbe probe, {
  ValueListenable<bool>? shown,
  ValueListenable<bool>? fixesAllowed,
  _Clock? clock,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
        body: _host(probe,
            shown: shown, fixesAllowed: fixesAllowed, clock: clock)),
  ));
  await _settleChecks(tester);
}

Widget _host(_FakeProbe probe,
        {ValueListenable<bool>? shown,
        ValueListenable<bool>? fixesAllowed,
        _Clock? clock}) =>
    CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: PreRunStatusSliver(
            probe: probe,
            shown: shown,
            fixesAllowed: fixesAllowed,
            unit: DistanceUnit.km,
            clock: (clock ?? _Clock()).call,
          ),
        ),
      ],
    );

/// The checks are microtask chains over the fake probe; a few pumps drain them
/// and paint the result. No pumpAndSettle: the map's dot pulses forever.
Future<void> _settleChecks(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  group('resolvePreRunGps', () {
    PreRunGps resolve({
      bool? servicesOn = true,
      LocationPermission? permission = LocationPermission.whileInUse,
      double? accuracyM,
      Duration? fixAge = Duration.zero,
    }) =>
        resolvePreRunGps(
          servicesOn: servicesOn,
          permission: permission,
          accuracyM: accuracyM,
          fixAge: fixAge,
        );

    test('services off wins over everything', () {
      expect(
          resolve(
              servicesOn: false,
              permission: LocationPermission.deniedForever,
              accuracyM: 3),
          PreRunGps.servicesOff);
    });

    test('a refusal the system will ask again is needed, a final one blocked',
        () {
      expect(resolve(permission: LocationPermission.denied),
          PreRunGps.permissionNeeded);
      expect(resolve(permission: LocationPermission.deniedForever),
          PreRunGps.permissionBlocked);
    });

    test('an unreadable check is never reported as a block', () {
      expect(resolve(servicesOn: null, permission: null), PreRunGps.searching);
    });

    test('grades a current fix against the recorder gate', () {
      expect(resolve(accuracyM: 20), PreRunGps.ready);
      expect(resolve(accuracyM: 20.5), PreRunGps.weak);
    });

    test('a fix older than the GPS-lost age is searching again', () {
      expect(resolve(accuracyM: 5, fixAge: kPreRunFixMaxAge), PreRunGps.ready);
      expect(
          resolve(
              accuracyM: 5,
              fixAge: kPreRunFixMaxAge + const Duration(milliseconds: 1)),
          PreRunGps.searching);
      expect(resolve(accuracyM: null), PreRunGps.searching);
    });
  });

  group('preRunRemedy', () {
    test('asks while Android will still prompt, then sends to settings', () {
      expect(preRunRemedy(ph.PermissionStatus.denied), PreRunRemedy.request);
      expect(preRunRemedy(ph.PermissionStatus.permanentlyDenied),
          PreRunRemedy.openSettings);
      expect(preRunRemedy(ph.PermissionStatus.restricted),
          PreRunRemedy.openSettings);
    });

    test('says nothing for a grant or an unread status', () {
      for (final s in [
        ph.PermissionStatus.granted,
        ph.PermissionStatus.limited,
        ph.PermissionStatus.provisional,
        null,
      ]) {
        expect(preRunRemedy(s), isNull, reason: '$s');
      }
    });
  });

  group('the idle page says what stands in the way', () {
    testWidgets('location off: says so and opens location settings',
        (tester) async {
      final probe = _FakeProbe()..servicesOn = false;
      await _pump(tester, probe);
      expect(find.byKey(const ValueKey('pre-run-services-off')), findsOneWidget);
      expect(find.text(_l10n.runPreRunLocationOffBody), findsOneWidget);
      expect(probe.listens, 0, reason: 'no fixes to wait for with Location off');
      await tester.tap(find.text(_l10n.runPreRunTurnOnLocation));
      await _settleChecks(tester);
      expect(probe.calls, ['openLocationSettings']);
    });

    testWidgets('permission not given: Allow asks, then the page searches',
        (tester) async {
      final probe = _FakeProbe()..permission = LocationPermission.denied;
      await _pump(tester, probe);
      expect(find.byKey(const ValueKey('pre-run-permission')), findsOneWidget);
      await tester.tap(find.text(_l10n.runPreRunAllowLocation));
      await _settleChecks(tester);
      expect(probe.calls, ['requestLocationPermission']);
      expect(find.byKey(const ValueKey('pre-run-searching')), findsOneWidget);
      expect(probe.listening, isTrue);
    });

    testWidgets('permission blocked: Open settings goes to the app page',
        (tester) async {
      final probe = _FakeProbe()..permission = LocationPermission.deniedForever;
      await _pump(tester, probe);
      expect(find.byKey(const ValueKey('pre-run-permission-blocked')),
          findsOneWidget);
      await tester.tap(find.text(_l10n.runOpenSettings));
      await _settleChecks(tester);
      expect(probe.calls, ['openAppSettings']);
    });

    testWidgets('a refusal Android marks final mid-page moves to settings',
        (tester) async {
      final probe = _FakeProbe()
        ..permission = LocationPermission.denied
        ..afterRequest = LocationPermission.deniedForever;
      await _pump(tester, probe);
      await tester.tap(find.text(_l10n.runPreRunAllowLocation));
      await _settleChecks(tester);
      expect(find.byKey(const ValueKey('pre-run-permission-blocked')),
          findsOneWidget);
    });
  });

  group('GPS once location works', () {
    testWidgets('no fix yet: searching, with no map and no spinner',
        (tester) async {
      final probe = _FakeProbe();
      await _pump(tester, probe);
      expect(find.byKey(const ValueKey('pre-run-searching')), findsOneWidget);
      expect(find.text(_l10n.runPreRunSearchingHint), findsOneWidget);
      expect(find.byType(LiveRunMap), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(probe.listening, isTrue);
    });

    testWidgets('the last known place shows the map while still searching',
        (tester) async {
      final probe = _FakeProbe()..lastKnown = _position();
      await _pump(tester, probe);
      expect(find.byType(LiveRunMap), findsOneWidget);
      final map = tester.widget<LiveRunMap>(find.byType(LiveRunMap));
      expect(map.coarsePosition, isTrue,
          reason: 'a cached place is not a current fix');
      expect(map.interactive, isFalse,
          reason: 'a drag over the preview scrolls the page');
      expect(find.text(_l10n.runPreRunSearching), findsOneWidget);
    });

    testWidgets('a good fix reads GPS ready with its accuracy', (tester) async {
      final probe = _FakeProbe();
      await _pump(tester, probe);
      probe.emit(_position(accuracy: 4.6));
      await _settleChecks(tester);
      expect(find.text(_l10n.runPreRunGpsReady('5 m')), findsOneWidget);
      expect(tester.widget<LiveRunMap>(find.byType(LiveRunMap)).coarsePosition,
          isFalse);
      expect(find.bySemanticsLabel(_l10n.runPreRunGpsReadyA11y('5 m')),
          findsOneWidget);
      expect(find.bySemanticsLabel(_l10n.runPreRunGpsReady('5 m')),
          findsNothing,
          reason: 'the chip is read once, as a sentence');
    });

    testWidgets('a coarse fix reads weak GPS', (tester) async {
      final probe = _FakeProbe();
      await _pump(tester, probe);
      probe.emit(_position(accuracy: 35));
      await _settleChecks(tester);
      expect(find.text(_l10n.runPreRunGpsWeak('35 m')), findsOneWidget);
      expect(tester.widget<LiveRunMap>(find.byType(LiveRunMap)).weakPosition,
          isTrue);
    });

    testWidgets('fixes that stop arriving go back to searching',
        (tester) async {
      final probe = _FakeProbe();
      final clock = _Clock();
      await _pump(tester, probe, clock: clock);
      probe.emit(_position());
      await _settleChecks(tester);
      expect(find.text(_l10n.runPreRunGpsReady('5 m')), findsOneWidget);
      clock.now = clock.now.add(const Duration(seconds: 11));
      await tester.pump(kPreRunRecheckInterval);
      await _settleChecks(tester);
      expect(find.text(_l10n.runPreRunSearching), findsOneWidget);
    });

    testWidgets('Location switched off while the page shows is caught',
        (tester) async {
      final probe = _FakeProbe();
      await _pump(tester, probe);
      expect(probe.listening, isTrue);
      probe.servicesOn = false;
      await tester.pump(kPreRunRecheckInterval);
      await _settleChecks(tester);
      expect(find.byKey(const ValueKey('pre-run-services-off')), findsOneWidget);
      expect(probe.listening, isFalse);
    });
  });

  group('losses the run can start with', () {
    testWidgets('approximate location only offers settings', (tester) async {
      final probe = _FakeProbe()..precise = false;
      await _pump(tester, probe);
      expect(find.byKey(const ValueKey('pre-run-approximate')), findsOneWidget);
      expect(find.text(_l10n.runPreciseLocationOff), findsOneWidget);
    });

    testWidgets('Physical activity off says what is lost and asks',
        (tester) async {
      final probe = _FakeProbe()
        ..extras[PreRunExtra.activityRecognition] = ph.PermissionStatus.denied;
      await _pump(tester, probe);
      final row = find.byKey(const ValueKey('pre-run-activityRecognition'));
      expect(row, findsOneWidget);
      expect(find.text(_l10n.runPreRunActivityOff), findsOneWidget);
      await tester.tap(
          find.descendant(of: row, matching: find.text(_l10n.runPreRunAllow)));
      await _settleChecks(tester);
      expect(probe.calls, ['request:activityRecognition']);
      expect(row, findsNothing);
    });

    testWidgets('a final refusal turns Allow into Open settings',
        (tester) async {
      final probe = _FakeProbe()
        ..extras[PreRunExtra.notifications] = ph.PermissionStatus.denied
        ..extraAfterRequest = ph.PermissionStatus.permanentlyDenied;
      await _pump(tester, probe);
      final row = find.byKey(const ValueKey('pre-run-notifications'));
      expect(find.text(_l10n.runNotificationsOffHint), findsOneWidget);
      await tester.tap(
          find.descendant(of: row, matching: find.text(_l10n.runPreRunAllow)));
      await _settleChecks(tester);
      final settings =
          find.descendant(of: row, matching: find.text(_l10n.runOpenSettings));
      expect(settings, findsOneWidget);
      await tester.tap(settings);
      await _settleChecks(tester);
      expect(probe.calls, ['request:notifications', 'openAppSettings']);
    });

    testWidgets('an unread permission is not reported', (tester) async {
      final probe = _FakeProbe()
        ..extras[PreRunExtra.activityRecognition] = null
        ..extras[PreRunExtra.notifications] = null;
      await _pump(tester, probe);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  testWidgets('listens only while the Run page shows', (tester) async {
    final probe = _FakeProbe();
    final shown = ValueNotifier<bool>(false);
    addTearDown(shown.dispose);
    await _pump(tester, probe, shown: shown);
    expect(probe.listens, 0);
    shown.value = true;
    await _settleChecks(tester);
    expect(probe.listening, isTrue);
    shown.value = false;
    await _settleChecks(tester);
    expect(probe.listening, isFalse);
  });

  testWidgets('lets go of its fixes the moment a recorder is built',
      (tester) async {
    final probe = _FakeProbe();
    final allowed = ValueNotifier<bool>(true);
    addTearDown(allowed.dispose);
    await _pump(tester, probe, fixesAllowed: allowed);
    expect(probe.listening, isTrue);
    allowed.value = false;
    expect(probe.listening, isFalse,
        reason: 'synchronously, before the recorder asks for its stream');
    allowed.value = true;
    await _settleChecks(tester);
    expect(probe.listening, isTrue);
  });

  testWidgets('a map that cannot load says so, and recording is unaffected',
      (tester) async {
    final previous = TileCache.debugTileProviderOverride;
    TileCache.debugTileProviderOverride = _BrokenTileProvider();
    addTearDown(() => TileCache.debugTileProviderOverride = previous);
    final probe = _FakeProbe();
    await _pump(tester, probe);
    probe.emit(_position());
    await _settleChecks(tester);
    final notice = find.byKey(const ValueKey('pre-run-map-failed'));
    await pumpUntil(tester, () => notice.evaluate().isNotEmpty,
        describe: 'the map-failed notice');
    expect(find.text(_l10n.runPreRunMapFailed), findsOneWidget);
    expect(find.text(_l10n.runPreRunGpsReady('5 m')), findsOneWidget,
        reason: 'the GPS status does not depend on the map');
    await tester.tap(find.text(_l10n.runPreRunMapRetry));
    await tester.pump();
    expect(notice, findsNothing, reason: 'Try again starts a fresh map');
  });

  for (final state in ['services-off', 'permission-blocked', 'warnings']) {
    worstCaseTestWidgets('The idle GPS status ($state)', (tester, locale) async {
      final probe = _FakeProbe();
      switch (state) {
        case 'services-off':
          probe.servicesOn = false;
        case 'permission-blocked':
          probe.permission = LocationPermission.deniedForever;
        default:
          probe
            ..precise = false
            ..extras[PreRunExtra.activityRecognition] =
                ph.PermissionStatus.denied
            ..extras[PreRunExtra.notifications] =
                ph.PermissionStatus.permanentlyDenied;
      }
      await tester.pumpWidget(worstCaseApp(
        locale: locale,
        home: Scaffold(body: _host(probe)),
      ));
      await _settleChecks(tester);
      await walkScrollable(tester, primaryScrollable(), 'idle GPS status');
    });
  }

  test('every fix the page reads goes through LocationManager', () {
    final src = File('lib/pre_run_status.dart').readAsStringSync();
    expect(
        RegExp(r'getPositionStream\(').allMatches(src).length, 1);
    expect(src, contains('forceLocationManager: true'));
    expect(src, contains('getLastKnownPosition(forceAndroidLocationManager: true)'));
  });
}
