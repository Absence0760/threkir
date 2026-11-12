// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';
import '../lib/missing_run_pull.dart';

Run _run(String id, DateTime startedAt, {Map<String, dynamic>? metadata}) =>
    Run(
      id: id,
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.app,
      metadata: metadata,
    );

/// The server as the reconcile sees it: an owned id set, and full rows on
/// request. [switchTo] simulates a sign-out landing mid-read.
class _ServerApi extends ApiClient {
  _ServerApi(this.rows);

  final List<Run> rows;
  String? session = 'me';
  String? switchTo;
  bool failOwnedRead = false;
  final List<Set<String>> fetched = [];

  @override
  String? get userId => session;

  @override
  Future<Set<String>> fetchOwnedRunIds() async {
    if (failOwnedRead) throw Exception('network down');
    return {for (final r in rows) r.id};
  }

  @override
  Future<List<Run>> getRunsByIds(Iterable<String> ids) async {
    final want = ids.toSet();
    fetched.add(want);
    if (switchTo != null) session = switchTo;
    return [
      for (final r in rows)
        if (want.contains(r.id)) r,
    ];
  }
}

void main() {
  group('planMissingRunIds', () {
    test('is the owned ids the device does not hold', () {
      expect(planMissingRunIds(ownedIds: {'a', 'b', 'c'}, localIds: {'a'}), {
        'b',
        'c',
      });
    });

    test('never re-pulls a run whose remote delete is queued', () {
      expect(
        planMissingRunIds(
          ownedIds: {'a', 'b'},
          localIds: const {},
          pendingDeleteIds: {'b'},
        ),
        {'a'},
      );
    });

    test(
      'a local-only run (recorded offline) is not the planner\'s concern',
      () {
        expect(
          planMissingRunIds(ownedIds: {'a'}, localIds: {'a', 'offline'}),
          isEmpty,
        );
      },
    );
  });

  group('pullMissingRuns', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('missing_run_pull_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('a server row whose clocks predate the delta watermark still arrives '
        '(restored backup, Garmin import, web manual entry)', () async {
      final held = _run('held', DateTime.utc(2026, 10, 9));
      // No last_modified_at at all, and a February start: invisible to the
      // `metadata->>last_modified_at > since` delta and below no cursor.
      final restored = _run('restored', DateTime.utc(2026, 2, 14));
      final stale = _run(
        'stale',
        DateTime.utc(2026, 7, 14),
        metadata: {'last_modified_at': '2026-07-14T08:00:00.000Z'},
      );
      final store = LocalRunStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed([held], dir: dir);
      final api = _ServerApi([held, restored, stale]);

      final pulled = await pullMissingRuns(api, store);

      expect(pulled, 2);
      expect(api.fetched.single, {
        'restored',
        'stale',
      }, reason: 'only the gap is fetched in full');
      expect(store.knownIds, {'held', 'restored', 'stale'});
      expect(
        store.isSynced('restored'),
        isTrue,
        reason: 'a pulled row is the server copy, not unsynced work',
      );
      expect(
        store.summaries.map((s) => s.id).toList(),
        ['held', 'stale', 'restored'],
        reason: 'the index stays newest-first',
      );
    });

    test('a device already in step makes no row read', () async {
      final held = _run('held', DateTime.utc(2026, 10, 9));
      final store = LocalRunStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed([held], dir: dir);
      final api = _ServerApi([held]);

      expect(await pullMissingRuns(api, store), 0);
      expect(api.fetched, isEmpty);
    });

    test('a session change mid-read writes nothing', () async {
      final store = LocalRunStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(const [], dir: dir);
      final api = _ServerApi([_run('theirs', DateTime.utc(2026, 5, 1))])
        ..switchTo = 'someone-else';

      expect(await pullMissingRuns(api, store), 0);
      expect(store.knownIds, isEmpty);
    });

    test(
      'signed out is a no-op, and a failed read throws to the caller',
      () async {
        final store = LocalRunStore()
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(const [], dir: dir);
        final api = _ServerApi([_run('a', DateTime.utc(2026, 5, 1))])
          ..session = null;
        expect(await pullMissingRuns(api, store), 0);

        api
          ..session = 'me'
          ..failOwnedRead = true;
        await expectLater(pullMissingRuns(api, store), throwsException);
        expect(store.knownIds, isEmpty);
      },
    );
  });
}
