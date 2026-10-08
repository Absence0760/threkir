// The Apple Watch hand-off contract (decisions § 1801).
//
// `WatchIngestBridge.swift` lets go of a run the moment the channel answers
// `true`, and holds it in memory otherwise. So `true` has to mean "this
// survives the process dying" in every auth and network state, and `false`
// has to be kept for the one case nothing on the Dart side can hold the run.
// These tests pin both halves, and the queue behaviour that makes `true`
// honest: every refusal cause — signed out, offline, server refusal — ends
// on disk, and the one permanent refusal does not loop.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/local_run_store.dart';
import '../lib/sync_service.dart';
import '../lib/watch_ingest.dart';
import '../lib/watch_ingest_queue.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._docsPath);
  final String _docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.fakeUserId});

  String? fakeUserId;
  final List<String> saved = [];
  Object? failWith;
  Completer<void>? gate;

  @override
  String? get userId => fakeUserId;

  @override
  Future<void> saveRun(Run run, {bool? isPublic}) async {
    final wait = gate;
    if (wait != null) await wait.future;
    final error = failWith;
    if (error != null) throw error;
    saved.add(run.id);
  }
}

Map<String, dynamic> _payload(String id) => {
      'id': id,
      'started_at': '2026-10-08T06:00:00.000Z',
      'duration_s': 1800,
      'distance_m': 5000.0,
      'source': 'apple_watch',
      'track': '[]',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late WatchIngestQueue queue;

  Directory queueDir() => Directory('${tempDir.path}/watch_ingest_queue');

  List<Map<String, dynamic>> envelopes() => queueDir()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
      .toList();

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('watch_ingest_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    queue = WatchIngestQueue();
    await queue.init();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('WatchIngest.handle — true means on disk', () {
    test('signed out: the run is queued and the bridge may let go', () async {
      await queue.setLastKnownOwner('user-a');
      final api = _FakeApiClient();

      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: api),
          isTrue,
          reason: 'the queue holds the run; a false would make the bridge '
              'hold a second, in-memory copy that dies with the process');
      expect(queue.pendingCount, 1);
      expect(envelopes().single['intended_owner_user_id'], 'user-a');
      expect(api.saved, isEmpty);
    });

    test('no Supabase configured: still queued, still true', () async {
      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: null),
          isTrue);
      expect(queue.pendingCount, 1);
    });

    test('signed in and online: queued first, then uploaded and deleted',
        () async {
      final api = _FakeApiClient(fakeUserId: 'user-a');

      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: api),
          isTrue);
      await queue.drain(api);

      expect(api.saved, ['r1']);
      expect(queue.pendingCount, 0);
    });

    test('signed in: the stamp is the signed-in user, not a stale cache',
        () async {
      final api = _FakeApiClient(fakeUserId: 'user-b')
        ..gate = Completer<void>();

      await WatchIngest.handle(_payload('r1'), queue: queue, api: api);

      expect(envelopes().single['intended_owner_user_id'], 'user-b',
          reason: 'with no last-known owner cached the file would otherwise '
              'go untagged, and an untagged entry adopts to whoever signs in');
      api.gate!.complete();
      await queue.drain(api);
    });

    test('offline: true, and the run stays queued for the next trigger',
        () async {
      final api = _FakeApiClient(fakeUserId: 'user-a')
        ..failWith = const SocketException('offline');

      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: api),
          isTrue);
      await queue.drain(api);

      expect(queue.pendingCount, 1);
      expect(queue.rejectedCount, 0,
          reason: 'a dropped connection is transient and must be retried');
    });

    test('a track the bucket refused is quarantined, not retried forever',
        () async {
      final api = _FakeApiClient(fakeUserId: 'user-a')
        ..failWith = const TrackTooLargeException(
            runId: 'r1', bytes: 60000000, limitBytes: 52428800, waypoints: 1);

      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: api),
          isTrue);
      await queue.drain(api);

      expect(queue.pendingCount, 0);
      expect(queue.rejectedCount, 1,
          reason: 'kept on disk for the retention window, out of the glob');

      api.failWith = null;
      await queue.drain(api);
      expect(api.saved, isEmpty,
          reason: 'the same bytes gzip to the same size; re-sending them on '
              'every trigger is the loop § 1009 measured');
    });
  });

  group('WatchIngest.handle — false means the bridge must hold it', () {
    // Deleting the queue directory makes every write fail, which is the only
    // way the hand-off can fail now.
    void breakTheDisk() => queueDir().deleteSync(recursive: true);

    test('disk write failed and signed out: false', () async {
      breakTheDisk();
      expect(
          await WatchIngest.handle(_payload('r1'),
              queue: queue, api: _FakeApiClient()),
          isFalse);
    });

    test('disk write failed, signed in and online: saved directly, true',
        () async {
      breakTheDisk();
      final api = _FakeApiClient(fakeUserId: 'user-a');
      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: api),
          isTrue);
      expect(api.saved, ['r1']);
    });

    test('disk write failed and the upload failed: false', () async {
      breakTheDisk();
      final api = _FakeApiClient(fakeUserId: 'user-a')
        ..failWith = const SocketException('offline');
      expect(await WatchIngest.handle(_payload('r1'), queue: queue, api: api),
          isFalse);
    });
  });

  group('WatchIngestQueue.enqueue', () {
    test('reports whether the write landed', () async {
      expect(await queue.enqueue(_payload('r1')), isTrue);
      queueDir().deleteSync(recursive: true);
      expect(await queue.enqueue(_payload('r2')), isFalse);
    });

    test('a non-finite number lands, and the drain quarantines it', () async {
      // jsonEncode refuses NaN outright (§ 986). Before, that made the write
      // fail on every attempt — a run the bridge could never hand off.
      expect(
          await queue.enqueue({..._payload('r1'), 'distance_m': double.nan},
              owner: 'user-a'),
          isTrue);
      expect(queue.pendingCount, 1);

      final api = _FakeApiClient(fakeUserId: 'user-a');
      await queue.drain(api);
      expect(api.saved, isEmpty);
      expect(queue.rejectedCount, 1);
    });
  });

  group('WatchIngestQueue.drain — one at a time', () {
    test('an overlapping call joins the pass and uploads each run once',
        () async {
      final api = _FakeApiClient(fakeUserId: 'user-a')
        ..gate = Completer<void>();
      await queue.enqueue(_payload('r1'), owner: 'user-a');

      final first = queue.drain(api);
      await queue.enqueue(_payload('r2'), owner: 'user-a');
      final second = queue.drain(api);
      api.gate!.complete();
      await Future.wait([first, second]);

      expect(api.saved..sort(), ['r1', 'r2'],
          reason: 'the joining call asked for another pass, which is what '
              'picked up r2; and nothing was uploaded twice');
      expect(queue.pendingCount, 0);
    });
  });

  group('SyncService retries the watch queue', () {
    late Directory storeDir;
    late LocalRunStore store;

    setUp(() async {
      storeDir = Directory.systemTemp.createTempSync('watch_ingest_sync_');
      store = LocalRunStore();
      await store.init(overrideDirectory: storeDir);
    });

    tearDown(() {
      if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
    });

    test('a connectivity trigger drains a run an offline upload left queued',
        () async {
      await queue.enqueue(_payload('r1'), owner: 'user-a');
      final api = _FakeApiClient(fakeUserId: 'user-a');
      final svc =
          SyncService(apiClient: api, runStore: store, watchQueue: queue);

      await svc.debugTrySync('connectivity');
      await queue.drain(api);

      expect(api.saved, ['r1']);
      expect(queue.pendingCount, 0);
    });

    test('signed out, the trigger leaves the queue alone', () async {
      await queue.enqueue(_payload('r1'), owner: 'user-a');
      final api = _FakeApiClient();
      final svc =
          SyncService(apiClient: api, runStore: store, watchQueue: queue);

      await svc.debugTrySync('connectivity');

      expect(api.saved, isEmpty);
      expect(queue.pendingCount, 1);
    });
  });
}
