import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/apple_watch_route_bridge.dart';
import '../lib/local_route_store.dart';

/// Records what the bridge sends over the `run_app/watch_route` channel and
/// can play the native side's failures back at it.
class _MockChannel {
  static const _channel = MethodChannel(AppleWatchRouteBridge.channelName);

  final List<MethodCall> calls = [];
  bool available = true;
  Object? throwOnPush;
  Object? throwOnAvailable;
  Object? throwOnPushSaved;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Future<dynamic> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'available':
        if (throwOnAvailable != null) throw throwOnAvailable!;
        return available;
      case 'push':
        if (throwOnPush != null) throw throwOnPush!;
        return null;
      case 'push_saved':
        if (throwOnPushSaved != null) throw throwOnPushSaved!;
        return null;
    }
    return null;
  }
}

Route _route({
  required String id,
  String name = 'Route',
  double distance = 5000,
  bool starred = false,
  List<Waypoint>? waypoints,
}) =>
    Route(
      id: id,
      userId: 'uid',
      name: name,
      waypoints: waypoints ?? _line(4),
      distanceMetres: distance,
      isStarred: starred,
    );

List<Waypoint> _line(int count) => [
      for (var i = 0; i < count; i++)
        // A gentle arc rather than a straight line, so priority
        // Douglas-Peucker has real geometry to spend its budget on.
        Waypoint(lat: 51.5 + i * 0.0001, lng: -0.12 + (i % 7) * 0.00002),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockChannel channel;

  setUp(() {
    channel = _MockChannel()..install();
  });

  tearDown(() {
    channel.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  group('appleWatchRouteFromWaypoints', () {
    test('refuses a route with fewer than two positions', () {
      for (final points in [<Waypoint>[], _line(1)]) {
        final shaped = appleWatchRouteFromWaypoints(points);
        expect(shaped.points, isNull);
        expect(shaped.refusal, AppleWatchRouteRefusal.tooFewPoints);
        expect(shaped.sourcePointCount, points.length);
        expect(shaped.simplified, isFalse);
      }
    });

    test('passes a route already inside the budget through untouched', () {
      final points = _line(120);
      final shaped = appleWatchRouteFromWaypoints(points);
      expect(shaped.refusal, isNull);
      expect(shaped.points, points);
      expect(shaped.sourcePointCount, 120);
      expect(shaped.simplified, isFalse);
    });

    test('accepts exactly the budget without thinning', () {
      final shaped =
          appleWatchRouteFromWaypoints(_line(kMaxAppleWatchRoutePoints));
      expect(shaped.points, hasLength(kMaxAppleWatchRoutePoints));
      expect(shaped.simplified, isFalse);
    });

    test('thins an over-budget route to fit instead of cutting it short', () {
      final points = _line(kMaxAppleWatchRoutePoints * 3);
      final shaped = appleWatchRouteFromWaypoints(points);
      expect(shaped.points, hasLength(kMaxAppleWatchRoutePoints));
      expect(shaped.sourcePointCount, points.length);
      expect(shaped.simplified, isTrue);
      // Both endpoints survive: a course that stopped early would put the
      // watch off route against geometry the route does not have.
      expect(shaped.points!.first, points.first);
      expect(shaped.points!.last, points.last);
    });
  });

  group('isAvailable', () {
    test('false off iOS without ever reaching the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);
      expect(channel.calls, isEmpty);
    });

    test('true on iOS when the native side reports a usable watch', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.available = true;
      expect(await AppleWatchRouteBridge.isAvailable(), isTrue);
      expect(channel.calls.single.method, 'available');
    });

    test('false on iOS when no watch can take a push', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.available = false;
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);
    });

    test('false when the native side is missing or errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.throwOnAvailable = MissingPluginException('test: no plugin');
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);

      channel.throwOnAvailable =
          PlatformException(code: 'boom', message: 'test failure');
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);
    });
  });

  group('push', () {
    Future<void> pushLine(List<Waypoint> points) => AppleWatchRouteBridge.push(
          id: 'route-1',
          name: 'Riverside loop',
          distanceMetres: 5120.5,
          points: points,
        );

    test('sends the id, name, distance and parallel coordinate arrays',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final points = _line(4);
      await pushLine(points);

      final call = channel.calls.single;
      expect(call.method, 'push');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['route_id'], 'route-1');
      expect(args['route_name'], 'Riverside loop');
      expect(args['route_distance_m'], 5120.5);
      expect(args['route_lat'], [for (final p in points) p.lat]);
      expect(args['route_lng'], [for (final p in points) p.lng]);
      expect((args['route_lat'] as List).length,
          (args['route_lng'] as List).length);
      expect(args.keys.toSet(), {
        'route_id',
        'route_name',
        'route_distance_m',
        'route_lat',
        'route_lng',
      });
    });

    test('throws off iOS rather than reporting a push that cannot happen',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await expectLater(pushLine(_line(4)), throwsA(isA<PlatformException>()));
      expect(channel.calls, isEmpty);
    });

    test('surfaces a native rejection instead of swallowing it', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.throwOnPush =
          PlatformException(code: 'watch_unavailable', message: 'no watch');
      await expectLater(pushLine(_line(4)), throwsA(isA<PlatformException>()));
    });
  });

  group('encodeSavedRoutesForWatch', () {
    test('offers only the starred routes', () {
      final encoded = AppleWatchRouteBridge.encodeSavedRoutesForWatch([
        _route(id: 'starred', starred: true),
        _route(id: 'plain'),
        _route(id: 'also-starred', starred: true),
      ]);
      expect([for (final e in encoded) e['route_id']],
          ['starred', 'also-starred']);
    });

    test('carries the same five keys a single armed push carries', () {
      final encoded = AppleWatchRouteBridge.encodeSavedRoutesForWatch(
        [_route(id: 'r', name: 'Riverside loop', distance: 5120.5, starred: true)],
      );
      expect(encoded.single.keys.toSet(), {
        'route_id',
        'route_name',
        'route_distance_m',
        'route_lat',
        'route_lng',
      });
      expect(encoded.single['route_name'], 'Riverside loop');
      expect(encoded.single['route_distance_m'], 5120.5);
    });

    test('stops at the route cap, keeping the store order', () {
      final encoded = AppleWatchRouteBridge.encodeSavedRoutesForWatch([
        for (var i = 0; i < kMaxAppleWatchSavedRoutes * 2; i++)
          _route(id: 'r$i', starred: true),
      ]);
      expect(encoded, hasLength(kMaxAppleWatchSavedRoutes));
      expect(encoded.first['route_id'], 'r0');
      expect(encoded.last['route_id'], 'r${kMaxAppleWatchSavedRoutes - 1}');
    });

    test('thins a dense route to the per-route budget, keeping both ends', () {
      final points = _line(kMaxAppleWatchSavedRoutePoints * 4);
      final encoded = AppleWatchRouteBridge.encodeSavedRoutesForWatch(
        [_route(id: 'r', starred: true, waypoints: points)],
      );
      final lat = encoded.single['route_lat'] as List;
      final lng = encoded.single['route_lng'] as List;
      expect(lat, hasLength(kMaxAppleWatchSavedRoutePoints));
      expect(lng, hasLength(kMaxAppleWatchSavedRoutePoints));
      expect(lat.first, points.first.lat);
      expect(lat.last, points.last.lat);
    });

    test('drops a route the watch could not follow rather than offering it',
        () {
      // Each of these fails `ArmedRoute.decode` on the wrist, so arming it
      // would fail at the start of the run — after the runner chose it.
      final encoded = AppleWatchRouteBridge.encodeSavedRoutesForWatch([
        _route(id: '', starred: true),
        _route(id: 'one-point', starred: true, waypoints: _line(1)),
        _route(id: 'no-points', starred: true, waypoints: const []),
        _route(id: 'nan-distance', starred: true, distance: double.nan),
        _route(id: 'negative-distance', starred: true, distance: -1),
        _route(
          id: 'off-globe',
          starred: true,
          waypoints: const [
            Waypoint(lat: 91, lng: 0),
            Waypoint(lat: 51.5, lng: -0.12),
          ],
        ),
        _route(
          id: 'nan-point',
          starred: true,
          waypoints: const [
            Waypoint(lat: double.nan, lng: 0),
            Waypoint(lat: 51.5, lng: -0.12),
          ],
        ),
        _route(id: 'good', starred: true),
      ]);
      expect([for (final e in encoded) e['route_id']], ['good']);
    });
  });

  group('pushSavedRoutes', () {
    test('never reaches the channel off iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await AppleWatchRouteBridge.pushSavedRoutes([]), isFalse);
      expect(channel.calls, isEmpty);
    });

    test('sends the list under the saved_routes key', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final list = AppleWatchRouteBridge.encodeSavedRoutesForWatch(
        [_route(id: 'r', starred: true)],
      );
      expect(await AppleWatchRouteBridge.pushSavedRoutes(list), isTrue);

      final call = channel.calls.single;
      expect(call.method, 'push_saved');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args.keys.toSet(), {'saved_routes'});
      expect((args['saved_routes'] as List).single, list.single);
    });

    test('sends an empty list, which is how the picker is emptied', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await AppleWatchRouteBridge.pushSavedRoutes([]), isTrue);
      final args =
          Map<String, dynamic>.from(channel.calls.single.arguments as Map);
      expect(args['saved_routes'], isEmpty);
    });

    test('reports a failure instead of throwing into whatever edited a route',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final failure in <Object>[
        PlatformException(code: 'watch_unavailable', message: 'no watch'),
        MissingPluginException('test: no plugin'),
      ]) {
        channel.throwOnPushSaved = failure;
        expect(await AppleWatchRouteBridge.pushSavedRoutes([]), isFalse);
      }
    });
  });

  group('attach', () {
    late Directory tempDir;
    late LocalRouteStore store;
    late AppleWatchRouteBridge bridge;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      AppleWatchRouteBridge.kPushDebounceWindow = Duration.zero;
      tempDir = Directory.systemTemp.createTempSync('apple_watch_routes_');
      store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      bridge = AppleWatchRouteBridge();
    });

    tearDown(() {
      bridge.detach();
      AppleWatchRouteBridge.kPushDebounceWindow =
          const Duration(milliseconds: 250);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    List<Map<String, dynamic>> saved() => [
          for (final c in channel.calls)
            if (c.method == 'push_saved')
              Map<String, dynamic>.from(c.arguments as Map),
        ];

    test('states the current list immediately', () async {
      await store.save(_route(id: 'starred', starred: true));
      await store.save(_route(id: 'plain'));

      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);

      expect(saved(), hasLength(1));
      final routes = saved().single['saved_routes'] as List;
      expect(routes, hasLength(1));
      expect((routes.single as Map)['route_id'], 'starred');
    });

    test('never pushes a starred route owned by somebody else', () async {
      // The privacy-zone leak: `is_starred` is per-owner curation the public
      // view drops (20260703_001), so another owner's star is not this
      // runner's, and the bridge sent `Route.waypoints` raw where the
      // single-route push clips for a non-owner. Asserted at the CHANNEL,
      // not on the helper, because the helper being right proves nothing
      // about whether `_pushStore` calls it.
      store.currentUserIdProvider = () => 'uid';
      await store.save(_route(id: 'mine', starred: true));
      await store.save(
        Route(
          id: 'theirs',
          userId: 'someone-else',
          name: 'theirs',
          waypoints: _line(4),
          distanceMetres: 1000,
          isStarred: true,
        ),
      );

      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);

      final routes = saved().last['saved_routes'] as List;
      expect(
        [for (final r in routes) (r as Map)['route_id']],
        ['mine'],
      );
    });

    test('pushes again when a route is starred', () async {
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      await store.save(_route(id: 'r', starred: true));
      await Future<void>.delayed(Duration.zero);

      expect(saved(), hasLength(2));
      expect((saved().last['saved_routes'] as List), hasLength(1));
    });

    test('skips an edit the wrist cannot see', () async {
      await store.save(_route(id: 'starred', starred: true));
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // A mutation that leaves the starred subset byte-identical. Without the
      // diff gate this burns a slot in a DURABLE transfer queue.
      await store.save(_route(id: 'unstarred'));
      await Future<void>.delayed(Duration.zero);

      expect(saved(), hasLength(1));
    });

    test('retries after a failed push rather than caching it as sent',
        () async {
      // The second change produces the SAME payload as the failed first one,
      // so only a diff cache that refused to remember the failure sends it.
      channel.throwOnPushSaved =
          PlatformException(code: 'watch_unavailable', message: 'no watch');
      await store.save(_route(id: 'starred', starred: true));
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      expect(saved(), hasLength(1));

      channel.throwOnPushSaved = null;
      await store.save(_route(id: 'unstarred'));
      await Future<void>.delayed(Duration.zero);
      expect(saved(), hasLength(2));
      expect(saved().last, saved().first);
    });

    test('stops pushing once detached', () async {
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      final before = saved().length;
      bridge.detach();
      await store.save(_route(id: 'r', starred: true));
      await Future<void>.delayed(Duration.zero);

      expect(saved(), hasLength(before));
    });

    test('coalesces a burst of stars into one push', () async {
      AppleWatchRouteBridge.kPushDebounceWindow =
          const Duration(milliseconds: 20);
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      final initial = saved().length;
      for (var i = 0; i < 5; i++) {
        await store.save(_route(id: 'r$i', starred: true));
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(saved(), hasLength(initial + 1));
      expect((saved().last['saved_routes'] as List), hasLength(5));
    });

    test('a second attach replaces the subscription rather than doubling it',
        () async {
      // Both `main.dart` sites reach this, and the second one runs on every
      // sign-out. Two listeners on one store is a duplicate durable transfer
      // per route edit, forever.
      bridge.attach(store);
      AppleWatchRouteBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      final before = saved().length;
      await store.save(_route(id: 'r', starred: true));
      await Future<void>.delayed(Duration.zero);

      expect(saved(), hasLength(before + 1));
    });

    test('subscribes to nothing off iOS', () async {
      bridge.detach();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      bridge.attach(store);
      await store.save(_route(id: 'r', starred: true));
      await Future<void>.delayed(Duration.zero);

      expect(saved(), isEmpty);
    });
  });

  // ---- Cross-language wiring guards -----------------------------------
  //
  // The route push crosses three languages and nothing else compiles the
  // three together:
  //
  //   apps/mobile_android/lib/apple_watch_route_bridge.dart   (Dart writer)
  //   apps/mobile_ios/ios/Runner/WatchIngestBridge.swift      (phone bridge)
  //   apps/watch_ios/WatchApp/ArmedRoute.swift                (watch decoder)
  //
  // A renamed key or a drifting point cap fails silently at runtime — the
  // watch simply never arms a route — so pin them here. Each guard
  // auto-skips when the sibling app isn't checked out.
  group('Apple Watch route-push cross-language wiring guards', () {
    String? read(String path) {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync() : null;
    }

    const payloadKeys = [
      'route_id',
      'route_name',
      'route_distance_m',
      'route_lat',
      'route_lng',
    ];

    test('the phone bridge serves the same channel and payload keys', () {
      final swift = read('../mobile_ios/ios/Runner/WatchIngestBridge.swift');
      if (swift == null) return;
      expect(swift, contains('"${AppleWatchRouteBridge.channelName}"'),
          reason: 'WatchIngestBridge.swift must register the same '
              'MethodChannel name the Dart bridge invokes.');
      expect(swift, contains('transferUserInfo'),
          reason: 'A route push must ride the queued, durable transport — '
              'sendMessage needs a reachable watch, which is exactly what '
              'the runner does not have when picking a route.');
      for (final key in payloadKeys) {
        expect(swift, contains('"$key"'),
            reason: 'WatchIngestBridge.swift must forward "$key".');
      }
    });

    test('the watch decoder reads the same payload keys', () {
      final swift = read('../watch_ios/WatchApp/ArmedRoute.swift');
      if (swift == null) return;
      for (final key in payloadKeys) {
        expect(swift, contains('"$key"'),
            reason: 'ArmedRoute.decode must read "$key".');
      }
    });

    test('the point cap is the same number in all three languages', () {
      final phone = read('../mobile_ios/ios/Runner/WatchIngestBridge.swift');
      final watch = read('../watch_ios/WatchApp/ArmedRoute.swift');
      if (phone == null || watch == null) return;
      expect(phone, contains('maxRoutePoints = $kMaxAppleWatchRoutePoints'),
          reason: 'A phone cap above the watch cap queues a durable transfer '
              'the watch will reject on every retry.');
      expect(watch, contains('maxPoints = $kMaxAppleWatchRoutePoints'),
          reason: 'ArmedRoute.maxPoints must match '
              'kMaxAppleWatchRoutePoints.');
    });

    test('route detail offers the push and shapes the route first', () {
      final screen = read('lib/screens/route_detail_screen.dart')!;
      expect(screen, contains('appleWatchRouteFromWaypoints(_displayWaypoints)'),
          reason: 'The push must read the privacy-clipped polyline '
              '(decisions §33) and go through the shaping helper, so an '
              'over-cap route is thinned rather than rejected by the '
              'native bridge.');
      expect(screen, contains('AppleWatchRouteBridge.push('),
          reason: 'route_detail_screen must reach the bridge.');
      expect(screen, contains("value: 'apple_watch'"),
          reason: 'The share menu must carry the Send-to-Apple-Watch row.');
      expect(screen, contains('routeDetailAppleWatchRouteTooShort'),
          reason: 'A refused route must tell the runner why, not fail '
              'silently.');
    });

    test('the saved-routes list rides the same three rails', () {
      final phone = read('../mobile_ios/ios/Runner/WatchIngestBridge.swift');
      final watch = read('../watch_ios/WatchApp/ArmedRoute.swift');
      if (phone == null || watch == null) return;
      expect(phone, contains('case "push_saved":'),
          reason: 'WatchIngestBridge.swift must serve the method '
              'AppleWatchRouteBridge.pushSavedRoutes invokes.');
      expect(phone, contains('savedRoutesUserInfo'),
          reason: 'The list must be re-validated on the phone: a payload the '
              'watch refuses is retried by the system forever against a '
              'runner who was told it was sent.');
      expect(phone, contains('routeUserInfo(from: element)'),
          reason: 'Each element must go through the SINGLE-route validator, '
              'so the picker can never offer a route ArmedRoute.decode '
              'would refuse.');
      for (final src in [phone, watch]) {
        expect(src, contains('"saved_routes"'),
            reason: 'Both Swift ends must hang the list off the same key.');
      }
      expect(watch, contains('ArmedRoute.decode(element)'),
          reason: 'SavedRoutes.decodeList must validate with the same '
              'decoder a single armed push takes.');
    });

    test('the saved-routes budgets are the same numbers in all three languages',
        () {
      final phone = read('../mobile_ios/ios/Runner/WatchIngestBridge.swift');
      final watch = read('../watch_ios/WatchApp/ArmedRoute.swift');
      if (phone == null || watch == null) return;
      expect(phone, contains('maxSavedRoutes = $kMaxAppleWatchSavedRoutes'));
      expect(phone,
          contains('maxSavedRoutePoints = $kMaxAppleWatchSavedRoutePoints'));
      expect(watch, contains('maxRoutes = $kMaxAppleWatchSavedRoutes'),
          reason: 'A phone cap above SavedRoutes.maxRoutes pushes routes the '
              'watch silently drops on arrival.');
      expect(
          watch,
          contains(
              'maxPointsPerRoute = $kMaxAppleWatchSavedRoutePoints'),
          reason: 'A route over the watch cap is dropped from the picker '
              'with nothing reported.');
    });

    test('startup subscribes the bridge to the route store', () {
      final main = read('lib/main.dart')!;
      expect(main, contains('AppleWatchRouteBridge().attach(routeStore);'),
          reason: 'The list only stays fresh because the bridge follows '
              'LocalRouteStore — the same trigger WearRoutesBridge uses. '
              'Without the attach the wrist picker renders its empty state '
              'forever.');
    });

    test('the watch consumes the navigator during a run', () {
      final content = read('../watch_ios/WatchApp/ContentView.swift');
      final workout = read('../watch_ios/WatchApp/WorkoutManager.swift');
      if (content == null || workout == null) return;
      expect(content, contains('RouteGuidanceView(navigator:'),
          reason: 'The running screen must render the RouteNavigator '
              'outputs — an engine with no surface is unreachable.');
      expect(workout, contains('ArmedRouteStore.load()'),
          reason: 'WorkoutManager.start() must pick up the armed route.');
      expect(workout, contains('navigator.update(currentLocation:'),
          reason: 'The navigator must be fed from the GPS stream.');
    });
  });
}
