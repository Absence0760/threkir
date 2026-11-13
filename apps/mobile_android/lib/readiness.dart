/// Readiness-to-run score. Combines training balance (form / TSB),
/// last night's sleep, and resting-HR drift vs a baseline into a
/// single 0–100 number the dashboard can show.
///
/// TS↔Dart parity pair with `apps/web/src/lib/training/readiness.ts`. Keep in
/// lockstep — the shared-library-syncer agent watches the pair.
library;

import 'l10n/gen/app_localizations.dart';

class ReadinessInputs {
  /// Training Stress Balance (Form). Positive = fresh, negative = fatigued.
  final double? tsb;
  final double? sleepHours;
  final int? restingHrBpm;
  final int? baselineRestingHrBpm;

  const ReadinessInputs({
    this.tsb,
    this.sleepHours,
    this.restingHrBpm,
    this.baselineRestingHrBpm,
  });
}

enum ReadinessBand { low, moderate, high }

/// Which input a contribution came from. The UI names it in the reader's
/// locale. The form input is deliberately not labelled like the TSB stat it is
/// derived from: this is the POINTS form added to the score, not the TSB value,
/// and one name over two different numbers read as a contradiction (#902).
enum ReadinessContributorKind { form, sleep, restingHr }

/// Why an input moved the score. The words live in the reader's catalogue
/// (`readinessReason*`), read by `readinessAdviceText`.
enum ReadinessReason {
  heavyFatigue,
  fatigued,
  slightFatigue,
  formNeutral,
  fresh,
  veryFresh,
  overTapered,
  veryLittleSleep,
  shortSleep,
  underSleep,
  wellRested,
  extendedSleep,
  hrWellAbove,
  hrAbove,
  hrSlightlyHigh,
  hrBaseline,
  hrBelow,
}

class ReadinessContribution {
  final ReadinessContributorKind kind;
  final int delta;
  final ReadinessReason reason;

  /// Resting HR above baseline, for the reasons that name it.
  final int? diffBpm;
  const ReadinessContribution({
    required this.kind,
    required this.delta,
    required this.reason,
    this.diffBpm,
  });
}

class Readiness {
  final int score;
  final ReadinessBand band;

  /// The contributor the advice line names; null when there are no inputs.
  final ReadinessContribution? dominant;
  final List<ReadinessContribution> contributors;
  const Readiness({
    required this.score,
    required this.band,
    required this.dominant,
    required this.contributors,
  });
}

const int _baselineScore = 75;

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

ReadinessBand _bandFor(int score) {
  if (score >= 70) return ReadinessBand.high;
  if (score >= 40) return ReadinessBand.moderate;
  return ReadinessBand.low;
}

ReadinessContribution? _scoreTsb(double? tsb) {
  // A non-finite TSB is no signal: every comparison below is false for NaN,
  // so it used to land on the final "over-tapered" branch.
  if (tsb == null || !tsb.isFinite) return null;
  int delta;
  ReadinessReason reason;
  if (tsb < -20) {
    delta = -20;
    reason = ReadinessReason.heavyFatigue;
  } else if (tsb < -10) {
    delta = -12;
    reason = ReadinessReason.fatigued;
  } else if (tsb < -5) {
    delta = -6;
    reason = ReadinessReason.slightFatigue;
  } else if (tsb <= 5) {
    delta = 0;
    reason = ReadinessReason.formNeutral;
  } else if (tsb <= 15) {
    delta = 8;
    reason = ReadinessReason.fresh;
  } else if (tsb <= 25) {
    delta = 5;
    reason = ReadinessReason.veryFresh;
  } else {
    delta = -3;
    reason = ReadinessReason.overTapered;
  }
  return ReadinessContribution(
      kind: ReadinessContributorKind.form, delta: delta, reason: reason);
}

ReadinessContribution? _scoreSleep(double? hours) {
  if (hours == null || !hours.isFinite) return null;
  int delta;
  ReadinessReason reason;
  if (hours < 5) {
    delta = -25;
    reason = ReadinessReason.veryLittleSleep;
  } else if (hours < 6.5) {
    delta = -12;
    reason = ReadinessReason.shortSleep;
  } else if (hours < 7.5) {
    delta = -3;
    reason = ReadinessReason.underSleep;
  } else if (hours <= 9) {
    delta = 5;
    reason = ReadinessReason.wellRested;
  } else {
    delta = 0;
    reason = ReadinessReason.extendedSleep;
  }
  return ReadinessContribution(
      kind: ReadinessContributorKind.sleep, delta: delta, reason: reason);
}

ReadinessContribution? _scoreRestingHr(int? resting, int? baseline) {
  if (resting == null || baseline == null) return null;
  final diff = resting - baseline;
  int delta;
  ReadinessReason reason;
  if (diff > 10) {
    delta = -18;
    reason = ReadinessReason.hrWellAbove;
  } else if (diff > 5) {
    delta = -10;
    reason = ReadinessReason.hrAbove;
  } else if (diff > 2) {
    delta = -4;
    reason = ReadinessReason.hrSlightlyHigh;
  } else if (diff >= -2) {
    delta = 0;
    reason = ReadinessReason.hrBaseline;
  } else {
    delta = 3;
    reason = ReadinessReason.hrBelow;
  }
  return ReadinessContribution(
      kind: ReadinessContributorKind.restingHr,
      delta: delta,
      reason: reason,
      diffBpm: reason == ReadinessReason.hrWellAbove ||
              reason == ReadinessReason.hrAbove
          ? diff
          : null);
}

ReadinessContribution? _dominantContributor(
    List<ReadinessContribution> contributors) {
  if (contributors.isEmpty) return null;
  // Ties in |delta| are common — a TSB of -12 and six hours of sleep both
  // score -12, and the two carry DIFFERENT advice. Dart's List.sort is
  // unstable where JS's is stable, so without the index fallback the
  // dominant contributor here would be whichever the sort happened to land
  // on rather than the first one added, and the two platforms would show
  // different sentences for the same inputs.
  final indexed = <(int, ReadinessContribution)>[
    for (var i = 0; i < contributors.length; i++) (i, contributors[i]),
  ]..sort((a, b) {
      final c = b.$2.delta.abs().compareTo(a.$2.delta.abs());
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return indexed.first.$2;
}

/// The advice line in the reader's language: the dominant input's reason and
/// what the band suggests, or, with no inputs, a band-aware suggestion.
/// Mirrors `readinessAdviceText` in `readiness.ts`.
String readinessAdviceText(Readiness r, AppLocalizations l10n) {
  final d = r.dominant;
  if (d == null) {
    return r.band == ReadinessBand.high
        ? l10n.readinessAdviceNoSignalHigh
        : l10n.readinessAdviceNoSignal;
  }
  final bpm = d.diffBpm ?? 0;
  final reason = switch (d.reason) {
    ReadinessReason.heavyFatigue => l10n.readinessReasonHeavyFatigue,
    ReadinessReason.fatigued => l10n.readinessReasonFatigued,
    ReadinessReason.slightFatigue => l10n.readinessReasonSlightFatigue,
    ReadinessReason.formNeutral => l10n.readinessReasonFormNeutral,
    ReadinessReason.fresh => l10n.readinessReasonFresh,
    ReadinessReason.veryFresh => l10n.readinessReasonVeryFresh,
    ReadinessReason.overTapered => l10n.readinessReasonOverTapered,
    ReadinessReason.veryLittleSleep => l10n.readinessReasonVeryLittleSleep,
    ReadinessReason.shortSleep => l10n.readinessReasonShortSleep,
    ReadinessReason.underSleep => l10n.readinessReasonUnderSleep,
    ReadinessReason.wellRested => l10n.readinessReasonWellRested,
    ReadinessReason.extendedSleep => l10n.readinessReasonExtendedSleep,
    ReadinessReason.hrWellAbove => l10n.readinessReasonHrWellAbove(bpm),
    ReadinessReason.hrAbove => l10n.readinessReasonHrAbove(bpm),
    ReadinessReason.hrSlightlyHigh => l10n.readinessReasonHrSlightlyHigh,
    ReadinessReason.hrBaseline => l10n.readinessReasonHrBaseline,
    ReadinessReason.hrBelow => l10n.readinessReasonHrBelow,
  };
  final next = switch (r.band) {
    ReadinessBand.low => l10n.readinessNextLow,
    ReadinessBand.moderate => l10n.readinessNextModerate,
    ReadinessBand.high => l10n.readinessNextHigh,
  };
  return l10n.readinessAdviceLine(reason, next);
}

Readiness computeReadiness(ReadinessInputs inputs) {
  final contributors = <ReadinessContribution>[];
  final tsb = _scoreTsb(inputs.tsb);
  if (tsb != null) contributors.add(tsb);
  final sleep = _scoreSleep(inputs.sleepHours);
  if (sleep != null) contributors.add(sleep);
  final hr = _scoreRestingHr(inputs.restingHrBpm, inputs.baselineRestingHrBpm);
  if (hr != null) contributors.add(hr);

  final sum = contributors.fold<int>(0, (s, c) => s + c.delta);
  final score = _clamp(_baselineScore + sum, 0, 100);
  final band = _bandFor(score);
  return Readiness(
    score: score,
    band: band,
    dominant: _dominantContributor(contributors),
    contributors: contributors,
  );
}
