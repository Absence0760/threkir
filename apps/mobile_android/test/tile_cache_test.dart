import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/offline_tile_pack.dart';
import '../lib/tile_cache.dart';
import '../lib/widgets/live_run_map.dart';

/// The basemap tile path must cost the same on the thousandth rebuild of a
/// map as on the first. `LiveRunMap` rebuilds at ~45 Hz while following
/// the runner, and every rebuild calls [basemapTileLayer]; a stall that
/// grows with rebuild count is what "the map stops loading tiles partway
/// through a session and only a relaunch fixes it" looks like.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter([this.body = const [0x89, 0x50, 0x4E, 0x47]]);

  final List<int> body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromBytes(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A cache store whose disk has gone bad: reads and/or writes throw.
class _FailingStore extends MemCacheStore {
  _FailingStore({this.failGet = false, this.failSet = false});

  final bool failGet;
  final bool failSet;

  @override
  Future<CacheResponse?> get(String key) {
    if (failGet) throw const FileSystemException('read failed');
    return super.get(key);
  }

  @override
  Future<void> set(CacheResponse response) {
    if (failSet) throw const FileSystemException('write failed');
    return super.set(response);
  }
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._root);
  final Directory _root;

  @override
  Future<String?> getApplicationCachePath() async => _root.path;
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Resolves one tile the way `TileLayer` does: through the cancellable path.
Future<ui.Image> _resolveTile(TileLayer layer, TileCoordinates coords) {
  final provider = layer.tileProvider.getImageWithCancelLoadingSupport(
    coords,
    layer,
    Completer<void>().future,
  );
  final done = Completer<ui.Image>();
  provider.resolve(ImageConfiguration.empty).addListener(
        ImageStreamListener(
          (info, _) => done.complete(info.image),
          onError: (e, st) => done.completeError(e, st),
        ),
      );
  return done.future.timeout(const Duration(seconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheRoot;

  // Production runs every map against the disk-backed client `main()`
  // initialises once, so the suite does too.
  setUpAll(() async {
    cacheRoot = Directory.systemTemp.createTempSync('tile_cache_test');
    PathProviderPlatform.instance = _FakePathProvider(cacheRoot);
    await TileCache.init();
  });

  tearDownAll(() {
    if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
  });

  const url = 'http://localhost:8080/styles/basic/{z}/{x}/{y}.png';

  test('rebuilding the basemap layer reuses one tile provider', () {
    final first = basemapTileLayer(urlTemplate: url).tileProvider;
    for (var i = 0; i < 200; i++) {
      basemapTileLayer(urlTemplate: url);
    }
    final later = basemapTileLayer(urlTemplate: url).tileProvider;

    expect(identical(first, later), isTrue);
  });

  test('rebuilds do not stack cache interceptors on the tile client', () {
    for (var i = 0; i < 200; i++) {
      basemapTileLayer(urlTemplate: url);
    }
    final provider =
        basemapTileLayer(urlTemplate: url).tileProvider as CachedTileProvider;

    expect(
      provider.dio.interceptors.whereType<DioCacheInterceptor>().length,
      1,
      reason: 'each tile request walks every interceptor in sequence, each '
          'one a cache-store lookup; one per rebuild makes a tile request '
          'cost O(rebuilds) before it ever reaches the network',
    );
  });

  test('a tile fetched after many rebuilds hits the network once, then cache',
      () async {
    for (var i = 0; i < 200; i++) {
      basemapTileLayer(urlTemplate: url);
    }
    final provider =
        basemapTileLayer(urlTemplate: url).tileProvider as CachedTileProvider;
    final adapter = _CountingAdapter();
    final original = provider.dio.httpClientAdapter;
    provider.dio.httpClientAdapter = adapter;
    addTearDown(() => provider.dio.httpClientAdapter = original);

    const tile = 'http://localhost:8080/styles/basic/14/8185/5448.png';
    final opts = Options(responseType: ResponseType.bytes);
    final a = await provider.dio.get<List<int>>(tile, options: opts);
    final b = await provider.dio.get<List<int>>(tile, options: opts);

    expect(a.statusCode, 200);
    expect(b.data, a.data);
    expect(adapter.calls, 1);
  });

  test('a disposed layer leaves the shared provider usable for the next one',
      () async {
    // TileLayer.dispose disposes its provider; with one provider shared
    // across every map, leaving a screen must not break the next map.
    basemapTileLayer(urlTemplate: url).tileProvider.dispose();
    final provider =
        basemapTileLayer(urlTemplate: url).tileProvider as CachedTileProvider;
    final adapter = _CountingAdapter();
    final original = provider.dio.httpClientAdapter;
    provider.dio.httpClientAdapter = adapter;
    addTearDown(() => provider.dio.httpClientAdapter = original);

    final res = await provider.dio.get<List<int>>(
      'http://localhost:8080/styles/basic/14/8186/5448.png',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(res.statusCode, 200);
    expect(adapter.calls, 1);
  });

  group('offline pack read-through (decisions § 170)', () {
    const routeId = 'pinned-route';
    late Directory packDir;
    late List<String> logs;
    late DebugPrintCallback originalDebugPrint;
    late HttpClientAdapter originalAdapter;
    late _CountingAdapter network;

    File packTile(TileCoordinates c) =>
        File('${packDir.path}/${c.z}/${c.x}/${c.y}.png')
          ..parent.createSync(recursive: true);

    setUp(() async {
      packDir = Directory('${cacheRoot.path}/$kOfflinePacksDirName/$routeId')
        ..createSync(recursive: true);
      logs = [];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      final shared = TileCache.tileProvider as CachedTileProvider;
      originalAdapter = shared.dio.httpClientAdapter;
      network = _CountingAdapter(await _png(5, 5));
      shared.dio.httpClientAdapter = network;
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
      (TileCache.tileProvider as CachedTileProvider).dio.httpClientAdapter =
          originalAdapter;
      PaintingBinding.instance.imageCache.clear();
      if (packDir.existsSync()) packDir.deleteSync(recursive: true);
    });

    test('a map showing a route reads its pack, then the shared provider', () {
      final provider =
          basemapTileLayer(urlTemplate: url, offlinePackRouteId: routeId)
              .tileProvider;

      expect(provider, isA<OfflinePackTileProvider>());
      expect(
        identical(
          (provider as OfflinePackTileProvider).fallback,
          TileCache.tileProvider,
        ),
        isTrue,
      );
      expect(provider.supportsCancelLoading, isTrue);
      expect(
        identical(
          basemapTileLayer(urlTemplate: url, offlinePackRouteId: routeId)
              .tileProvider,
          provider,
        ),
        isTrue,
        reason: 'a map rebuilding at 45 Hz must keep one provider per route',
      );
      expect(
        identical(
          basemapTileLayer(urlTemplate: url).tileProvider,
          TileCache.tileProvider,
        ),
        isTrue,
      );
    });

    test('a tile inside the pack is served from disk, not the network',
        () async {
      const coords = TileCoordinates(8190, 5450, 14);
      packTile(coords).writeAsBytesSync(await _png(2, 2));
      final layer =
          basemapTileLayer(urlTemplate: url, offlinePackRouteId: routeId);

      final image = await _resolveTile(layer, coords);

      expect(image.width, 2);
      expect(network.calls, 0);
    });

    test('a tile outside the pack falls back to the shared cached provider',
        () async {
      const coords = TileCoordinates(8191, 5450, 14);
      final layer =
          basemapTileLayer(urlTemplate: url, offlinePackRouteId: routeId);

      final image = await _resolveTile(layer, coords);

      expect(image.width, 5);
      expect(network.calls, 1);
    });

    test('an unreadable pack tile falls back instead of failing the tile',
        () async {
      // A crash mid-write leaves a truncated file that the downloader's retry
      // skips as already present, so the read path has to survive it.
      const coords = TileCoordinates(8192, 5450, 14);
      packTile(coords).writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D]);
      final layer =
          basemapTileLayer(urlTemplate: url, offlinePackRouteId: routeId);

      final image = await _resolveTile(layer, coords);

      expect(image.width, 5);
      expect(network.calls, 1);
      expect(
        logs.where((l) => l.contains('OfflinePackTileProvider')),
        hasLength(1),
      );
    });
  });

  group('a failing cache store', () {
    late List<String> logs;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logs = [];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
    });

    tearDown(() => debugPrint = originalDebugPrint);

    Future<Response<List<int>>> fetchTile(CachedTileProvider provider) =>
        provider.dio
            .get<List<int>>(
              'http://localhost:8080/styles/basic/14/8200/5448.png',
              options: Options(responseType: ResponseType.bytes),
            )
            // A store error the interceptor does not handle never calls its
            // handler, so the request neither completes nor fails.
            .timeout(const Duration(seconds: 5));

    test('a read that throws is a miss: the tile still comes from the network',
        () async {
      final provider =
          TileCache.buildTileProvider(_FailingStore(failGet: true));
      final adapter = _CountingAdapter();
      provider.dio.httpClientAdapter = adapter;

      final res = await fetchTile(provider);

      expect(res.statusCode, 200);
      expect(res.data, adapter.body);
      expect(adapter.calls, 1);
      expect(
        logs.where((l) => l.contains('cache store get failed')),
        hasLength(1),
      );
    });

    test('a write that throws is skipped: the tile is still returned',
        () async {
      final provider =
          TileCache.buildTileProvider(_FailingStore(failSet: true));
      final adapter = _CountingAdapter();
      provider.dio.httpClientAdapter = adapter;

      final res = await fetchTile(provider);

      expect(res.statusCode, 200);
      expect(res.data, adapter.body);
      expect(
        logs.where((l) => l.contains('cache store set failed')),
        hasLength(1),
      );
    });
  });
}
