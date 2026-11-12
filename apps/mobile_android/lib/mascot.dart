/// Grisnir, the Threkir goat, as the phone draws him. The images are renders
/// of his Blender model (apps/web/static/brand/grisnir/README.md); he never
/// appears in an error, sync, payment or lost-GPS state.
library;

import 'package:api_client/api_client.dart' show SettingsKeys;
import 'package:core_models/core_models.dart' show Run;

import 'l10n/gen/app_localizations.dart';
import 'pr_card.dart' show PrCardKind;
import 'settings_sync.dart';

/// Standing, a front 3/4 view, for a corner of a share card.
const kGrisnirBadgeAsset = 'assets/brand/grisnir/grisnir-badge-256.png';

/// Lying down, head up, one foreleg stretched forward, for rest days.
const kGrisnirRestAsset = 'assets/brand/grisnir/grisnir-rest-384.png';

/// A goat's hop, all four hooves off the ground, for a run's milestone.
const kGrisnirProudAsset = 'assets/brand/grisnir/grisnir-proud-384.png';

/// Standing by a trail sign, for a "nothing yet" empty state and onboarding.
const kGrisnirWaitAsset = 'assets/brand/grisnir/grisnir-wait-384.png';

/// Whether the runner shows Grisnir: the universal `show_mascot`, on unless
/// it is literally `false`, as web reads it.
bool mascotShown() => activeSetting(SettingsKeys.showMascot) != false;

enum MilestoneKind { firstRun, first5k, badge, best, longest }

/// The one moment a run earns, most notable first, or null. A new best is an
/// improved time at a PR distance (a faster pace over it); "first" at 5K is
/// the first time the runner covered one. The longest run needs an earlier
/// run to be longer than. Parity pair with web `pickMilestone`
/// (apps/web/src/lib/mascot/mascot.ts).
MilestoneKind? pickMilestone({
  required int totalRuns,
  required double runDistanceM,
  required double longestRunM,
  required Iterable<(String, PrCardKind)> records,
  required bool badgeEarned,
}) {
  if (totalRuns == 1) return MilestoneKind.firstRun;
  if (records.any((r) => r.$1 == '5k' && r.$2 == PrCardKind.first)) {
    return MilestoneKind.first5k;
  }
  if (badgeEarned) return MilestoneKind.badge;
  if (records.any((r) => r.$2 == PrCardKind.improved)) {
    return MilestoneKind.best;
  }
  if (totalRuns > 1 && runDistanceM > 0 && runDistanceM >= longestRunM) {
    return MilestoneKind.longest;
  }
  return null;
}

String milestoneLine(AppLocalizations l10n, MilestoneKind kind) =>
    switch (kind) {
      MilestoneKind.firstRun => l10n.mascotMilestoneFirstRun,
      MilestoneKind.first5k => l10n.mascotMilestoneFirst5k,
      MilestoneKind.badge => l10n.mascotMilestoneBadge,
      MilestoneKind.best => l10n.mascotMilestoneBest,
      MilestoneKind.longest => l10n.mascotMilestoneLongest,
    };

/// The milestone a just-finished run earns from what the phone already holds,
/// for the post-run summary, before the server has scored its records or
/// badges: the first run, the first 5K, or the longest yet. [all] is the
/// local store, with or without [run] in it.
MilestoneKind? localMilestone(Run run, Iterable<Run> all) {
  var others = 0;
  var longest = run.distanceMetres;
  var hadFiveK = false;
  for (final r in all) {
    if (r.id == run.id) continue;
    others++;
    if (r.distanceMetres > longest) longest = r.distanceMetres;
    if (r.distanceMetres >= 5000) hadFiveK = true;
  }
  return pickMilestone(
    totalRuns: others + 1,
    runDistanceM: run.distanceMetres,
    longestRunM: longest,
    records: [
      if (run.distanceMetres >= 5000 && !hadFiveK) ('5k', PrCardKind.first),
    ],
    badgeEarned: false,
  );
}
