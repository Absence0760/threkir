import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';
import '../lib/sync_service.dart';

/// No device clock decides a run edit conflict (decisions § 2120). A pulled
/// server row replaces a synced copy unless that copy has a pending edit, in
/// which case the edit's fields are laid on top of it; the edit is pushed as
/// a compare-and-swap on the server `updated_at` it was made on.

const _base1 = '2026-09-02T08:00:00.123456+00:00';
const _base2 = '2026-09-02T09:30:00.654321+00:00';
const _base3 = '2026-09-02T10:45:00.000001+00:00';

Run _server({
  String id = 'run-1',
  String? updatedAt = _base1,
  double distance = 5000,
  Map<String, dynamic> metadata = const {'title': 'Easy', 'notes': 'flat'},
}) => Run(
  id: id,
  startedAt: DateTime.utc(2026, 9, 1, 7),
  duration: const Duration(minutes: 30),
  distanceMetres: distance,
  track: const [],
  source: RunSource.app,
  metadata: {
    ...metadata,
    if (updatedAt != null) MetadataKeys.serverUpdatedAt: updatedAt,
  },
);

Run _edited(Run copy, Map<String, dynamic> changes) => Run(
  id: copy.id,
  startedAt: copy.startedAt,
  duration: copy.duration,
  distanceMetres: copy.distanceMetres,
  track: copy.track,
  routeId: copy.routeId,
  source: copy.source,
  externalId: copy.externalId,
  metadata: {...?copy.metadata, ...changes},
  createdAt: copy.createdAt,
);

/// Plays the server for the push: each compare-and-swap either matches the
/// base it is told the row holds, or loses.
class _CasApi extends ApiClient {
  _CasApi(this.row);

  /// The row as the server holds it; null once deleted.
  Run? row;
  final List<({Set<String> fields, String? base, Run sent})> swaps = [];
  int reads = 0;

  /// Moves the row behind the push's back just before each swap lands.
  final List<Run> interleave = [];

  @override
  String? get userId => 'user-1';

  @override
  Future<List<Run>> getRunsByIds(Iterable<String> ids) async {
    reads++;
    final r = row;
    return r == null ? const [] : [r];
  }

  @override
  Future<Run?> updateRunFieldsIfUnchanged(
    Run run, {
    required Set<String> fields,
    required String? baseUpdatedAt,
  }) async {
    swaps.add((fields: fields, base: baseUpdatedAt, sent: run));
    if (interleave.isNotEmpty) row = interleave.removeAt(0);
    final current = row;
    if (current == null || serverUpdatedAtOf(current) != baseUpdatedAt) {
      return null;
    }
    final next = applyRunEditFields(
      local: run,
      server: current,
      fields: fields,
    );
    row = _edited(next, {
      MetadataKeys.serverUpdatedAt: '2026-09-03T00:00:0${swaps.length}.5+00:00',
    });
    return row;
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('run_edit_sync_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<LocalRunStore> open() async {
    final store = LocalRunStore();
    await store.init(overrideDirectory: dir);
    return store;
  }

  group('the pull merge decides by pending edit, never by clock', () {
    test(
      'no pending edit: the server row wins over a "later" local stamp',
      () async {
        // Written straight to disk: every write the store makes stamps its own
        // write clock, so only a planted file can hold a stamp from a device
        // clock running decades fast.
        File('${dir.path}/run-1.json').writeAsStringSync(
          jsonEncode({
            kLocalStoreVersionKey: kLocalStoreSchemaVersion,
            'run': _server(
              metadata: {
                'title': 'Stale phone copy',
                MetadataKeys.lastModifiedAt: '2099-01-01T00:00:00.000Z',
              },
            ).toJson(),
            'synced': true,
          }),
        );
        File('${dir.path}/synced_ids.json').writeAsStringSync(
          jsonEncode({
            kLocalStoreVersionKey: kLocalStoreSchemaVersion,
            'ids': ['run-1'],
          }),
        );
        final store = await open();

        await store.saveManyFromRemote([
          _server(updatedAt: _base2, metadata: {'title': 'Edited on web'}),
        ]);

        final run = (await store.runById('run-1'))!;
        expect(
          run.metadata?['title'],
          'Edited on web',
          reason: 'a device clock running fast must not keep a stale copy',
        );
        expect(serverUpdatedAtOf(run), _base2);
      },
    );

    test(
      'a pending edit keeps its fields and takes every other server change',
      () async {
        final store = await open();
        await store.saveFromRemote(_server());
        await store.update(
          _edited((await store.runById('run-1'))!, {'title': 'Phone title'}),
        );

        await store.saveManyFromRemote([
          _server(
            updatedAt: _base2,
            distance: 5400,
            metadata: {'title': 'Web title', 'notes': 'Web notes'},
          ),
        ]);

        final run = (await store.runById('run-1'))!;
        expect(run.metadata?['title'], 'Phone title');
        expect(run.metadata?['notes'], 'Web notes');
        expect(run.distanceMetres, 5400);
        final pending = store.pendingEdit('run-1')!;
        expect(pending.fields, {RunEditField.metadata('title')});
        expect(
          pending.baseUpdatedAt,
          _base2,
          reason:
              'the local copy now reflects that row, so the push swaps '
              'against it',
        );
      },
    );

    test(
      'a copy the server never confirmed is kept for its own upsert',
      () async {
        final store = await open();
        await store.save(
          _server(updatedAt: null, metadata: {'title': 'Local'}),
        );

        await store.saveManyFromRemote([
          _server(updatedAt: _base2, metadata: {'title': 'Server'}),
        ]);

        expect((await store.runById('run-1'))!.metadata?['title'], 'Local');
        expect(store.unsyncedRuns.map((r) => r.id), ['run-1']);
      },
    );
  });

  group('an edit to a synced run is a pending field edit', () {
    test(
      'records the fields and the base, stays synced, survives a reload',
      () async {
        final store = await open();
        await store.saveFromRemote(_server());
        await store.update(
          _edited((await store.runById('run-1'))!, {
            'title': 'Tempo',
            'notes': 'x',
          }),
        );

        expect(
          store.unsyncedRuns,
          isEmpty,
          reason:
              'the whole-row upsert would re-upload the track and write '
              'every other field back over the server',
        );
        final reloaded = await open();
        final pending = reloaded.pendingEdit('run-1')!;
        expect(pending.fields, {
          RunEditField.metadata('title'),
          RunEditField.metadata('notes'),
        });
        expect(pending.baseUpdatedAt, _base1);
      },
    );

    test('a second edit adds its fields and keeps the first base', () async {
      final store = await open();
      await store.saveFromRemote(_server());
      await store.update(
        _edited((await store.runById('run-1'))!, {'title': 'Tempo'}),
      );
      await store.update(
        _edited((await store.runById('run-1'))!, {'notes': 'windy'}),
      );

      final pending = store.pendingEdit('run-1')!;
      expect(pending.fields, {
        RunEditField.metadata('title'),
        RunEditField.metadata('notes'),
      });
      expect(pending.baseUpdatedAt, _base1);
    });

    test('an edit to a run never pushed stays a whole-row write', () async {
      final store = await open();
      await store.save(_server(updatedAt: null));
      await store.update(
        _edited((await store.runById('run-1'))!, {'title': 'Tempo'}),
      );
      expect(store.pendingEdit('run-1'), isNull);
      expect(store.unsyncedRuns.map((r) => r.id), ['run-1']);
    });
  });

  group('the push is a compare-and-swap', () {
    Future<LocalRunStore> withEdit() async {
      final store = await open();
      await store.saveFromRemote(_server());
      await store.update(
        _edited((await store.runById('run-1'))!, {'title': 'Phone title'}),
      );
      return store;
    }

    test('a returned row clears the edit and is adopted', () async {
      final store = await withEdit();
      final api = _CasApi(_server());

      expect(await pushPendingRunEdit(api, store, 'run-1'), isTrue);

      expect(api.swaps.single.base, _base1);
      expect(api.swaps.single.fields, {RunEditField.metadata('title')});
      expect(store.pendingEdit('run-1'), isNull);
      final run = (await store.runById('run-1'))!;
      expect(run.metadata?['title'], 'Phone title');
      expect(serverUpdatedAtOf(run), serverUpdatedAtOf(api.row!));
      expect(
        await open().then((s) => s.pendingEdit('run-1')),
        isNull,
        reason: 'the clear is durable',
      );
    });

    test(
      'zero rows: re-read, re-base onto the moved row, retry once',
      () async {
        final store = await withEdit();
        final api = _CasApi(
          _server(
            updatedAt: _base2,
            metadata: {'title': 'Easy', 'notes': 'Web notes'},
          ),
        );

        expect(await pushPendingRunEdit(api, store, 'run-1'), isTrue);

        expect(api.swaps.map((s) => s.base), [_base1, _base2]);
        expect(api.reads, 1);
        expect(
          api.row!.metadata?['title'],
          'Phone title',
          reason: 'same-field edits resolve to the later arrival',
        );
        expect(
          api.row!.metadata?['notes'],
          'Web notes',
          reason: 'the other device\'s change is not overwritten',
        );
        expect(store.pendingEdit('run-1'), isNull);
      },
    );

    test(
      'losing again leaves the edit pending, re-based, without throwing',
      () async {
        final store = await withEdit();
        final api = _CasApi(_server(updatedAt: _base2))
          ..interleave.addAll([
            _server(updatedAt: _base2),
            _server(updatedAt: _base3),
          ]);

        expect(await pushPendingRunEdit(api, store, 'run-1'), isFalse);

        expect(api.swaps, hasLength(2));
        final pending = store.pendingEdit('run-1')!;
        expect(pending.fields, {RunEditField.metadata('title')});
        expect(pending.baseUpdatedAt, _base2);
        expect(
          (await store.runById('run-1'))!.metadata?['title'],
          'Phone title',
        );
      },
    );

    test('a row gone from the server drops the copy and the edit', () async {
      final store = await withEdit();
      final api = _CasApi(null);

      expect(await pushPendingRunEdit(api, store, 'run-1'), isTrue);

      expect(await store.runById('run-1'), isNull);
      expect(store.pendingEdit('run-1'), isNull);
    });

    test('an edit with no base reads the row before its first swap', () async {
      final store = await open();
      await store.saveFromRemote(_server(updatedAt: null));
      await store.update(
        _edited((await store.runById('run-1'))!, {'title': 'Phone title'}),
      );
      expect(store.pendingEdit('run-1')!.baseUpdatedAt, isNull);
      final api = _CasApi(_server(updatedAt: _base2));

      expect(await pushPendingRunEdit(api, store, 'run-1'), isTrue);

      expect(api.reads, 1);
      expect(api.swaps.single.base, _base2);
    });

    test('the SyncService cycle drains pending edits', () async {
      final store = await withEdit();
      final api = _CasApi(_server());
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.swaps, hasLength(1));
      expect(store.pendingEdit('run-1'), isNull);
    });
  });

  group('on-disk format', () {
    test('a store written before pending edits loads with none', () async {
      // The pre-§ 2120 layout: a synced run file with no server stamp in its
      // bag and no pending_edits.json beside it.
      final seed = await open();
      await seed.save(
        Run(
          id: 'legacy',
          startedAt: DateTime.utc(2026, 1, 1),
          duration: const Duration(minutes: 20),
          distanceMetres: 4000,
          track: const [],
          source: RunSource.app,
          metadata: const {'title': 'Old'},
        ),
      );
      await seed.markSynced('legacy');
      expect(File('${dir.path}/pending_edits.json').existsSync(), isFalse);

      final store = await open();
      expect(store.pendingEditIds, isEmpty);
      expect(
        store.runs.map((r) => r.id),
        ['legacy'],
        reason: 'the sidecar name must not be read as a run file',
      );

      await store.update(
        _edited((await store.runById('legacy'))!, {'title': 'New'}),
      );
      expect(
        store.pendingEdit('legacy')!.baseUpdatedAt,
        isNull,
        reason: 'with no base the push reads the row first',
      );
    });

    test('an unreadable sidecar reads as no pending edit', () async {
      final seed = await open();
      await seed.saveFromRemote(_server());
      File('${dir.path}/pending_edits.json').writeAsStringSync('{ not json');

      final store = await open();
      expect(store.pendingEditIds, isEmpty);
      expect(store.runs.map((r) => r.id), ['run-1']);
    });

    test('the base keeps the server string to the microsecond', () async {
      final store = await open();
      await store.saveFromRemote(_server(updatedAt: _base1));
      await store.update(
        _edited((await store.runById('run-1'))!, {'title': 'Tempo'}),
      );

      final raw =
          jsonDecode(File('${dir.path}/pending_edits.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        (raw['edits'] as Map)['run-1']['base_updated_at'],
        '2026-09-02T08:00:00.123456+00:00',
      );
      final reloaded = await open();
      expect(reloaded.pendingEdit('run-1')!.baseUpdatedAt, _base1);
      final api = _CasApi(_server(updatedAt: _base1));
      await pushPendingRunEdit(api, reloaded, 'run-1');
      expect(api.swaps.first.base, '2026-09-02T08:00:00.123456+00:00');
    });
  });
}
