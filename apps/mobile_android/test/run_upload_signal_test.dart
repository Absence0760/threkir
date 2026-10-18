import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/local_run_store.dart';
import '../lib/run_upload_signal.dart';
import '../lib/training_service.dart';

// The server links a run to today's plan workout as the row is written
// (decisions § 2079). These pin the chain that tells every plan surface to
// re-read: a run reaching the server fires the store's `landed`, and the
// training service turns that into a notify its screens already refresh on.

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('run_upload_signal_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Run makeRun(String id) => Run(
    id: id,
    startedAt: DateTime(2026, 10, 18, 7),
    duration: const Duration(minutes: 40),
    distanceMetres: 6437,
    source: RunSource.app,
  );

  Future<LocalRunStore> openStore() async {
    final store = LocalRunStore();
    await store.init(overrideDirectory: tempDir);
    return store;
  }

  group('LocalRunStore.landed', () {
    test('does not fire for a local save the server has not seen', () async {
      final store = await openStore();
      var fired = 0;
      store.landed.addListener(() => fired++);
      await store.save(makeRun('local'));
      expect(fired, 0);
    });

    test('fires when one run is marked synced', () async {
      final store = await openStore();
      await store.save(makeRun('a'));
      var fired = 0;
      store.landed.addListener(() => fired++);
      await store.markSynced('a');
      expect(fired, 1);
    });

    test('fires once for a pushed batch', () async {
      final store = await openStore();
      await store.save(makeRun('a'));
      await store.save(makeRun('b'));
      var fired = 0;
      store.landed.addListener(() => fired++);
      await store.markManySynced(store.runs);
      expect(fired, 1);
    });

    test('stays quiet when nothing in the batch was marked', () async {
      final store = await openStore();
      var fired = 0;
      store.landed.addListener(() => fired++);
      await store.markManySynced([makeRun('never-saved')]);
      expect(fired, 0);
    });

    test('fires for a run pulled from the server', () async {
      final store = await openStore();
      var fired = 0;
      store.landed.addListener(() => fired++);
      await store.saveFromRemote(makeRun('from-watch'));
      expect(fired, 1);
      await store.saveManyFromRemote([makeRun('from-web')]);
      expect(fired, 2);
    });
  });

  group('TrainingService.followRunsLanded', () {
    test('notifies listeners each time the source fires', () {
      final training = TrainingService();
      final signal = RunUploadSignal();
      training.followRunsLanded(signal);
      var notified = 0;
      training.addListener(() => notified++);
      signal.fire();
      signal.fire();
      expect(notified, 2);
      training.dispose();
    });

    test('a store sync reaches the training service', () async {
      final store = await openStore();
      await store.save(makeRun('a'));
      final training = TrainingService()..followRunsLanded(store.landed);
      var notified = 0;
      training.addListener(() => notified++);
      await store.markSynced('a');
      expect(notified, 1);
      training.dispose();
    });

    test('follows every source of a merged listenable', () {
      final phone = RunUploadSignal();
      final watch = RunUploadSignal();
      final training = TrainingService()
        ..followRunsLanded(Listenable.merge([phone, watch]));
      var notified = 0;
      training.addListener(() => notified++);
      phone.fire();
      watch.fire();
      expect(notified, 2);
      training.dispose();
    });

    test('replacing the source stops the old one', () {
      final first = RunUploadSignal();
      final second = RunUploadSignal();
      final training = TrainingService()..followRunsLanded(first);
      training.followRunsLanded(second);
      var notified = 0;
      training.addListener(() => notified++);
      first.fire();
      expect(notified, 0);
      second.fire();
      expect(notified, 1);
      training.dispose();
    });

    test('dispose detaches from the source', () {
      final signal = RunUploadSignal();
      TrainingService()
        ..followRunsLanded(signal)
        ..dispose();
      // A disposed notifier asserts when notified, so a listener left
      // attached would throw here.
      expect(signal.fire, returnsNormally);
    });
  });
}
