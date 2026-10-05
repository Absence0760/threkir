import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

import 'offline_tile_pack.dart';

/// Persistent on-disk cache for MapTiler tiles shared by every live map
/// instance in the app. Tiles survive across app launches — so the second
/// run in your neighbourhood renders the basemap with no network and the
/// first run's pre-cached tiles are still available even if the device is
/// offline when you start.
///
/// The store is initialised once from `main.dart` before `runApp`. Before
/// init (tests, hot reload from a cold start) the getters fall back to an
/// in-memory store so the widget still renders without crashing.
class TileCache {
  /// Maximum bytes the on-disk tile cache is allowed to consume. Evicted
  /// in LRU-ish order at startup — a user who explores many areas would
  /// otherwise grow the cache unbounded (tiles at z19 are ~40 KB each;
  /// one long run can touch several thousand). 500 MB is generous enough
  /// to cover a week of commutes plus a city-wide area, while still
  /// bounded enough that storage-pressured devices don't fill up.
  static const _maxDiskBytes = 500 * 1024 * 1024;

  static CacheStore? _store;
  static CacheStore? _fallbackStore;
  static CachedTileProvider? _tileProvider;

  /// Shared cache store. Falls back to an in-memory store with a modest
  /// budget when [init] hasn't run yet — used by widget tests and during
  /// the first frame before `main` finishes plumbing.
  static CacheStore get store =>
      _store ?? (_fallbackStore ??= MemCacheStore(maxSize: 50 * 1024 * 1024));

  /// The one tile provider every basemap layer shares.
  ///
  /// It must be built once, not per layer: `CachedTileProvider` appends a
  /// `DioCacheInterceptor` to the `Dio` it is given, and dio walks its
  /// interceptors in sequence on every request, each one a cache-store
  /// read. A provider per `build()` on a shared client therefore made each
  /// tile request cost one disk lookup per rebuild the process had ever
  /// done — at `LiveRunMap`'s follow-mode rebuild rate, minutes into a
  /// session no tile reached the network, nothing errored, and only a
  /// relaunch cleared it. `TileLayer.dispose` disposes its provider;
  /// `CachedTileProvider`'s dispose is a no-op, which is what makes sharing
  /// it across layers safe.
  static TileProvider get tileProvider => _tileProvider ??= CachedTileProvider(
        store: store,
        dio: Dio(),
        maxStale: const Duration(days: 30),
        // Map raster tiles are content-addressed by z/x/y and are
        // effectively immutable, so serve a cached tile without a
        // revalidation round-trip whenever one exists — this is what
        // keeps the map usable offline and stops every pan/zoom from
        // re-hitting the tile server. _trimToBudget() bounds disk use;
        // maxStale caps how long a never-re-requested tile lingers.
        cachePolicy: CachePolicy.forceCache,
      );

  static String? _offlinePacksRoot;
  static final Map<String, TileProvider> _packProviders = {};

  /// The basemap provider for a map showing [routeId]: tiles from that
  /// route's offline pack (decisions § 170) first, then [tileProvider].
  ///
  /// The pack directory is checked per tile rather than once here, so a pack
  /// downloaded while the map is open is picked up and an un-pinned route
  /// simply misses through to [tileProvider]. One provider per route is
  /// memoised for the same reason [tileProvider] is: a map rebuilding at
  /// 45 Hz must hand `TileLayer` the same object every frame.
  static TileProvider tileProviderForRoute(String? routeId) {
    final root = _offlinePacksRoot;
    if (routeId == null || root == null) return tileProvider;
    return _packProviders[routeId] ??= OfflinePackTileProvider(
      packDir: Directory('$root/$routeId'),
      fallback: tileProvider,
    );
  }

  /// Initialise the disk-backed tile cache. Call from `main()` before
  /// `runApp`. Idempotent — subsequent calls are no-ops.
  static Future<void> init() async {
    if (_store != null) return;
    try {
      final cacheRoot = await getApplicationCacheDirectory();
      _offlinePacksRoot = '${cacheRoot.path}/$kOfflinePacksDirName';
      final tilesDir = Directory('${cacheRoot.path}/map_tiles');
      if (!tilesDir.existsSync()) {
        tilesDir.createSync(recursive: true);
      }
      _store = FileCacheStore(tilesDir.path);
      _tileProvider = null;
      _packProviders.clear();
      // Fire-and-forget LRU trim. Keeps the cache bounded without blocking
      // the first frame — eviction is best-effort and the map works fine
      // whether it runs or not.
      unawaited(_trimToBudget(tilesDir));
    } catch (e) {
      // Fall back to in-memory on any platform issue (corrupt dir, plugin
      // channel failure during early startup). Map still works, just
      // loses persistence across launches.
      debugPrint('TileCache: disk init failed, using in-memory store: $e');
      _store = MemCacheStore(maxSize: 100 * 1024 * 1024);
      _tileProvider = null;
      _packProviders.clear();
    }
  }

  /// Walk the tile cache directory, sum file sizes, and delete oldest
  /// tiles until the total is under [_maxDiskBytes]. Oldest = earliest
  /// mtime (least recently written — dio_cache writes each file on
  /// fetch, so mtime approximates last use). Safe to call on every
  /// startup; typically a no-op because tiles are small and the budget
  /// is generous.
  static Future<void> _trimToBudget(Directory tilesDir) async {
    try {
      final entries = <_TileEntry>[];
      int total = 0;
      await for (final entity in tilesDir.list(recursive: true)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        total += stat.size;
        entries.add(_TileEntry(entity, stat.size, stat.modified));
      }
      if (total <= _maxDiskBytes) return;

      entries.sort((a, b) => a.mtime.compareTo(b.mtime));
      int toFree = total - _maxDiskBytes;
      int deleted = 0;
      for (final e in entries) {
        if (toFree <= 0) break;
        try {
          await e.file.delete();
          toFree -= e.size;
          deleted++;
        } catch (e) {
          debugPrint('[TileCache._trimToBudget] delete failed: $e');
        }
      }
      debugPrint(
        'TileCache: trimmed $deleted files '
        '(was ${total ~/ (1024 * 1024)} MB, budget ${_maxDiskBytes ~/ (1024 * 1024)} MB)',
      );
    } catch (e) {
      debugPrint('TileCache: trim failed: $e');
    }
  }
}

class _TileEntry {
  final File file;
  final int size;
  final DateTime mtime;
  const _TileEntry(this.file, this.size, this.mtime);
}
