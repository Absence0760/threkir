import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/dm_drafts.dart';
import '../lib/orphaned_recording.dart';
import '../lib/tile_cache.dart';
import 'hermetic_tile_provider.dart';
import 'store_write_watch.dart';

/// Suite-wide instrumentation for the store write chain, applied to every test
/// under this directory by `flutter_test`'s own configuration hook.
///
/// Both defects it watches for are DYNAMIC properties no source scan can see.
/// A widget test's `tester.tap` runs on the fake clock, so a store write it
/// starts completes on the real event loop the fake clock never turns: if
/// nothing waits for that write, it is still in flight when `tearDown` deletes
/// the temp directory out from under it, and the torn rename is either silent
/// or an unattributable failure in whichever test runs next. Three successive
/// censuses tried to count that population by grepping for helper names —
/// `pumpUntil`, `pumpEventQueue`, a temp directory beside a tap — and all
/// three counted something else (decisions § 1097).
///
/// The second is `storeWritesSettled`'s own diagnosis, which is delivered by
/// completing a future and so reaches its awaiter through the awaiting zone's
/// continuation — never run for a fake-zone await with no pump behind it, so
/// the test hangs to the runner's timeout printing a bare `TimeoutException`
/// that names neither the store nor the call site (decisions § 1093, row 5).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  installStoreWriteWatch();
  // No widget test reaches the tile servers: a real request is a network call
  // the fake clock leaves pending when the test ends.
  TileCache.debugTileProviderOverride = HermeticTileProvider();
  // A test that ends mid-recording disposes its run screen, which hands the
  // run on (decisions § 2352). Left set, it would open the next test's run
  // screen on a Resume prompt for a run that test never recorded.
  tearDown(() => orphanedRecording.value = null);
  // Message drafts live for the app's life; one test's typing must not open
  // the next test's thread with text in it.
  tearDown(DmDrafts.clear);
  await testMain();
}
