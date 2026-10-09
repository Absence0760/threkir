import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'watch_ingest_queue.dart';

/// Receives runs from the paired Apple Watch via a method channel owned
/// by `Runner/AppDelegate.swift` + `Runner/WatchIngestBridge.swift` on
/// iOS. Android doesn't register the channel, so the `setMethodCallHandler`
/// installation is a harmless no-op and the bridge never fires.
///
/// Each call carries: `{id, started_at, duration_s, distance_m, source,
/// avg_bpm?, hr_coverage?, activity_type?, last_modified_at?, track}` —
/// `track` as the JSON TEXT of the file the watch wrote. Decoding is
/// [runFromWatchPayload]'s, not this class's: the same payload is decoded by
/// the queue's drain on every path, so a second copy of the decode could only
/// ever be a divergence waiting to happen, and was one.
///
/// **The reply is a hand-off, not an upload result** (decisions § 1801). Every
/// run is written to the [WatchIngestQueue] on disk FIRST and the bridge is
/// answered `true` the moment that write lands — signed in or not, online or
/// not. The upload is then the queue's job, retried on its own triggers. The
/// Swift side holds a run only until it hears `true`, so `true` has to mean
/// "this survives the process dying", and only a disk write can promise that.
class WatchIngest {
  static const _channel = MethodChannel('run_app/watch_ingest');

  /// Install the handler and tell the bridge Dart can now take runs.
  ///
  /// Installed once at bootstrap whatever the auth state, because the handler
  /// reads it per call: a run that lands before sign-in is a queued run, not an
  /// unanswered channel. [api] is null when Supabase is not configured; runs
  /// still land on disk.
  static void attach(ApiClient? api, WatchIngestQueue queue) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'run') return null;
      final args = call.arguments as Map<Object?, Object?>?;
      if (args == null) return false;

      // One payload, ONE decoder. This handler used to carry a second
      // hand-written copy of the decode for the signed-in branch, and the two
      // copies had already drifted in both directions over the same bridge
      // payload: this one never learned the per-point `bpm` that
      // `docs/backend/metadata.md` says the watch-ingest decoder reads, and
      // `runFromWatchPayload` never learned that this bridge sends `track` as
      // JSON TEXT — so an Apple Watch run that arrived while signed out was
      // enqueued and later replayed with no track at all. Whether the runner
      // happened to be signed in is not something a decoder should be able to
      // change about the run.
      final payload = <String, dynamic>{
        for (final e in args.entries)
          if (e.key is String) e.key as String: e.value,
      };
      return handle(payload, queue: queue, api: api);
    });
    // The bridge holds every run until this lands: a run it dispatched before
    // the handler above existed would have been answered "not implemented".
    _channel.invokeMethod<void>('ready').catchError((Object e) {
      // MissingPluginException on Android, where nothing owns the channel.
      debugPrint('Watch ingest ready signal not delivered: $e');
    });
  }

  /// The channel's answer for one run: `true` when Dart owns it, `false` when
  /// the bridge must keep holding it.
  ///
  /// Owned means on disk, or — only when the disk write itself failed — saved
  /// to the server directly. Not signed in, offline and a server that refuses
  /// the row all answer `true`, because the queue has the run and every one of
  /// those is the queue's to retry. `false` is left for the one case nothing on
  /// this side can hold the run.
  @visibleForTesting
  static Future<bool> handle(
    Map<String, dynamic> payload, {
    required WatchIngestQueue queue,
    required ApiClient? api,
  }) async {
    final owner = api?.userId;
    if (await queue.enqueue(payload, owner: owner)) {
      if (api != null && owner != null) {
        queue.drain(api).catchError((Object e) {
          debugPrint('Watch ingest drain failed: $e');
        });
      }
      return true;
    }
    if (api == null || owner == null) return false;
    try {
      await api.saveRun(
        runFromWatchPayload(payload),
        isPublic: isPublicFromWatchPayload(payload),
      );
      return true;
    } catch (e) {
      debugPrint('Watch ingest direct save failed: $e');
      return false;
    }
  }
}
