import 'package:api_client/api_client.dart';

import 'local_run_store.dart';

/// The owned server runs this device has never stored.
///
/// The Runs tab's delta pull keys on `metadata.last_modified_at`, a clock only
/// this app's [LocalRunStore] stamps. A row written by anything else — a web
/// manual entry, a Garmin or Strava import, a backup restore that carries the
/// archive's metadata — has no such stamp or an old one, so no delta pull ever
/// returns it; and the first-load pull is a single page. Membership is the
/// clock-free signal: an id the server says the caller owns that the device
/// does not hold is missing, whatever its timestamps say.
///
/// A queued remote delete is excluded: the device dropped that row on purpose
/// and the server copy is waiting to be deleted, not missing.
Set<String> planMissingRunIds({
  required Set<String> ownedIds,
  required Set<String> localIds,
  Set<String> pendingDeleteIds = const <String>{},
}) => ownedIds.difference(localIds).difference(pendingDeleteIds);

/// Fetch every owned run [store] lacks and fold it in through
/// [LocalRunStore.saveManyFromRemote]. Returns how many rows landed.
///
/// One ids-only walk of the owned set, then full rows only for the gap, so a
/// device already in step pays one light read. Throws on a failed read; the
/// caller decides how loudly to report it.
Future<int> pullMissingRuns(ApiClient api, LocalRunStore store) async {
  final userId = api.userId;
  if (userId == null || userId.isEmpty) return 0;
  final owned = await api.fetchOwnedRunIds();
  final missing = planMissingRunIds(
    ownedIds: owned,
    localIds: store.knownIds,
    pendingDeleteIds: store.pendingRemoteDeleteIds,
  );
  if (missing.isEmpty) return 0;
  final runs = await api.getRunsByIds(missing);
  // A sign-out or account switch during the reads would otherwise write the
  // previous account's rows into the next one's store.
  if (api.userId != userId) return 0;
  // Re-read: a delete queued while the rows were in flight must win.
  final pending = store.pendingRemoteDeleteIds;
  final fresh = [
    for (final r in runs)
      if (!pending.contains(r.id)) r,
  ];
  await store.saveManyFromRemote(fresh);
  return fresh.length;
}
