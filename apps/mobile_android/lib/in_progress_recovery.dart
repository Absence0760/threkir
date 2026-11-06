/// Pure helper for the crash-resume recovery gate that runs at app
/// start. Separated out of main.dart so the truth table (recover vs
/// discard, with what threshold) is unit-testable.
///
/// Persona-hunt finding Casual #3: pre-fix, a sub-threshold partial
/// was silently `clearInProgress()`-d with zero feedback. A casual
/// runner who tapped Start then was interrupted ~40s later (kid /
/// dog / app-swipe) had no way to know the app saw their attempt and
/// dropped it. "The app ate my run" suspicion.
///
/// This helper decides the outcome and hands back the partial a one-shot
/// banner reports; [inProgressBannerText] words it once a catalogue and the
/// runner's unit exist. The caller still owns `store.save` /
/// `store.clearInProgress`; we just classify.

import 'package:core_models/core_models.dart';

import 'l10n/gen/app_localizations.dart';
import 'preferences.dart';

enum InProgressOutcome { none, recovered, resumable, discarded }

class InProgressEvaluation {
  final InProgressOutcome outcome;

  /// The partial as a Run ready to save. Null unless outcome=recovered.
  final Run? recovered;

  /// The raw partial to hand back to the run screen so it can RE-HYDRATE the
  /// recorder and continue the SAME run. Null unless outcome=resumable. Carries
  /// the full track / laps / elapsed / id so the resumed run keeps continuity.
  final Run? resumablePartial;

  /// The partial a passive banner reports, for [InProgressOutcome.recovered]
  /// and [InProgressOutcome.discarded]. Null otherwise: a resumable partial
  /// gets the interactive Resume / Finish / Discard prompt instead. Kept as a
  /// Run rather than a sentence because this runs before `runApp`, where
  /// neither the catalogue nor the runner's distance unit is in hand —
  /// [inProgressBannerText] words it on the first frame.
  final Run? bannerPartial;

  const InProgressEvaluation({
    required this.outcome,
    this.recovered,
    this.resumablePartial,
    this.bannerPartial,
  });
}

/// A qualifying partial whose last incremental save is within this window of
/// "now" is offered as RESUMABLE — the recorder re-hydrates and continues the
/// SAME run rather than closing it out. Beyond it (or with no recency signal —
/// no `in_progress_saved_at`), a partial is finalized or discarded on the
/// stricter [_clearsFinalizeFloor].
///
/// Wide enough to survive a long process-killed / offline stretch: a 240-mile
/// continuous effort can lose its OS process for 6–30 h in a canyon dead zone,
/// plus a sleep-station nap, and still expect to reopen the app at the next aid
/// station and continue ONE run. Bounded so a genuinely-abandoned partial from
/// days ago still auto-finalizes instead of prompting a stale resume.
const Duration kResumableWindow = Duration(hours: 48);

/// Elapsed time at which a recent partial is worth offering back even with no
/// distance on it — a session that stood still, or ran indoors with the
/// pedometer silent, for a minute or more.
const Duration kResumableMinElapsed = Duration(seconds: 60);

/// Classify an in-progress partial (decisions § 230, amended by § 2354).
///
/// Recent (within [kResumableWindow]): resumable when it has any distance or
/// at least [kResumableMinElapsed] of elapsed time. Only an empty partial — no
/// distance, under a minute — is discarded. The runner decides about anything
/// else, because the app cannot tell an 11-minute stationary session from an
/// accidental tap by its distance.
///
/// Stale or undated: there is nobody to ask, so the partial is finalized only
/// when it clears the old size floor (GPS: ≥ 3 line points and ≥ 50 m; indoor:
/// ≥ 60 s) and discarded otherwise. Either way a banner says so.
InProgressEvaluation evaluateInProgressPartial(Run? partial, {DateTime? now}) {
  if (partial == null) {
    return const InProgressEvaluation(outcome: InProgressOutcome.none);
  }

  if (_isRecent(partial, now ?? DateTime.now())) {
    final hasContent = partial.distanceMetres > 0 ||
        partial.duration >= kResumableMinElapsed;
    if (hasContent) {
      return InProgressEvaluation(
        outcome: InProgressOutcome.resumable,
        resumablePartial: partial,
      );
    }
    return InProgressEvaluation(
      outcome: InProgressOutcome.discarded,
      bannerPartial: partial,
    );
  }

  if (!_clearsFinalizeFloor(partial)) {
    return InProgressEvaluation(
      outcome: InProgressOutcome.discarded,
      bannerPartial: partial,
    );
  }

  final metadata = Map<String, dynamic>.from(partial.metadata ?? {});
  metadata[MetadataKeys.recoveredFromCrash] = true;
  final recovered = Run(
    id: partial.id,
    startedAt: partial.startedAt,
    duration: partial.duration,
    distanceMetres: partial.distanceMetres,
    track: partial.track,
    routeId: partial.routeId,
    source: partial.source,
    externalId: partial.externalId,
    metadata: metadata,
    createdAt: partial.createdAt,
  );
  return InProgressEvaluation(
    outcome: InProgressOutcome.recovered,
    recovered: recovered,
    bannerPartial: partial,
  );
}

/// The floor a partial nobody was asked about must clear to be saved as a run
/// on its own: a stale one lands in the history and syncs without the runner
/// choosing it, so jitter from a phone left on a table stays out.
bool _clearsFinalizeFloor(Run partial) {
  final indoorEstimated =
      partial.metadata?[MetadataKeys.indoorEstimated] == true;
  // Counted on the line, as it was before off-track fixes were stored.
  final hasEnoughGps =
      trackLine(partial.track).length >= 3 && partial.distanceMetres >= 50;
  final hasEnoughIndoor =
      indoorEstimated && partial.duration >= kResumableMinElapsed;
  return hasEnoughGps || hasEnoughIndoor;
}

/// A partial's distance in the runner's unit and its elapsed time as a clock,
/// for the resume prompt and the recovery banners. An indoor partial's
/// distance is a pedometer estimate and carries the same `~` the run screen
/// shows for one.
({String distance, String duration}) inProgressStats(
    Run partial, DistanceUnit unit) {
  final estimated = partial.metadata?[MetadataKeys.indoorEstimated] == true;
  final distance = UnitFormat.distance(partial.distanceMetres, unit);
  return (
    distance: estimated ? '~$distance' : distance,
    duration: _formatClock(partial.duration),
  );
}

/// The passive banner for a recovered or discarded partial, or null when the
/// evaluation has nothing to report.
String? inProgressBannerText(
  AppLocalizations l10n,
  InProgressEvaluation evaluation,
  DistanceUnit unit,
) {
  final partial = evaluation.bannerPartial;
  if (partial == null) return null;
  final stats = inProgressStats(partial, unit);
  switch (evaluation.outcome) {
    case InProgressOutcome.recovered:
      return l10n.runRecoveryRecoveredBanner(stats.distance, stats.duration);
    case InProgressOutcome.discarded:
      return l10n.runRecoveryDiscardedBanner(stats.distance, stats.duration);
    case InProgressOutcome.none:
    case InProgressOutcome.resumable:
      return null;
  }
}

/// Whether [partial]'s last incremental save is within [kResumableWindow] of
/// [now]. Recency comes from `metadata.in_progress_saved_at`, stamped on every
/// incremental save by `_saveInProgress`. A missing / unparseable stamp is
/// treated as NOT recent — an unknown-age partial goes to the finalize floor
/// rather than surprising the user with a resume prompt for a run whose age we
/// can't establish. A future-dated stamp (clock skew) counts as
/// recent.
bool _isRecent(Run partial, DateTime now) {
  final raw = partial.metadata?[MetadataKeys.inProgressSavedAt];
  if (raw is! String) return false;
  final savedAt = DateTime.tryParse(raw);
  if (savedAt == null) return false;
  final age = now.toUtc().difference(savedAt.toUtc());
  return age <= kResumableWindow;
}

String _formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final sec = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
