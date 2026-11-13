// Issue #1374 FS-15: a save that had already landed on the phone held its
// spinner for a whole-store drain with no timeout, then said "Saved" whether
// or not it synced. `syncRowBriefly` bounds the wait and answers for the row.

import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_gear_store.dart';
import '../lib/offline_sync_store.dart';

/// Gear writes that hang until [release] completes, or answer at once when it
/// is already complete.
class _GearApi extends ApiClient {
  final release = Completer<void>();

  @override
  Future<GearRow> createGear({
    required String kind,
    required String name,
    String? id,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    int? targetDistanceM,
    String? notes,
  }) async {
    await release.future;
    return GearRow(
      id: id ?? 'server',
      ownerId: 'test-user',
      kind: kind,
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDefault: false,
    );
  }
}

void main() {
  late Directory dir;
  late LocalGearStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sync_row_briefly');
    store = LocalGearStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() async {
    await store.debugWritesSettled();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('answers true once the row has reached the server', () async {
    final row = await store.createLocal(kind: 'shoes', name: 'Pegasus');
    final api = _GearApi()..release.complete();
    expect(await store.syncRowBriefly(api, row.id), isTrue);
  });

  test('stops waiting at the bound and answers false, leaving the drain going',
      () async {
    final row = await store.createLocal(kind: 'shoes', name: 'Pegasus');
    final id = row.id;
    final api = _GearApi();
    final watch = Stopwatch()..start();
    final synced = await store.syncRowBriefly(api, id,
        wait: const Duration(milliseconds: 50));
    expect(synced, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

    // The drain carries on behind the caller and lands when the push does.
    api.release.complete();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (store.debugStored(id)!.syncState != SyncState.synced &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(store.debugStored(id)!.syncState, SyncState.synced);
  });
}
