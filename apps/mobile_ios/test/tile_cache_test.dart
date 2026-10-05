import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/tile_cache.dart';
import '../lib/widgets/live_run_map.dart';

/// The basemap tile path must cost the same on the thousandth rebuild of a
/// map as on the first. `LiveRunMap` rebuilds at ~45 Hz while following
/// the runner, and every rebuild calls [basemapTileLayer]; a stall that
/// grows with rebuild count is what "the map stops loading tiles partway
/// through a session and only a relaunch fixes it" looks like.
class _CountingAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromBytes(
      const [0x89, 0x50, 0x4E, 0x47],
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._root);
  final Directory _root;

  @override
  Future<String?> getApplicationCachePath() async => _root.path;
}

void main() {
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
}
