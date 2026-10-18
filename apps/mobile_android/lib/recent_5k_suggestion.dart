// The "build a plan from your recent 5K" suggestion a runner with no plan
// sees on Home. It picks the one measured 5K worth offering; the plan wizard
// then pre-fills its recent-5K field with it and leaves the "this reflects my
// fitness today" box unticked, so the time anchors no paces until the runner
// confirms it (the wizard's `_recent5kConfirmed` gate).
//
// Web twin: `apps/web/src/lib/training/recent_5k_suggestion.ts`.

/// How far back a measured 5K still counts as recent: eight weeks, the span a
/// plan's base phase assumes fitness holds over. Older times are what the
/// wizard's confirm box warns about, so they are not offered at all.
const int kRecent5kWindowDays = 56;

/// The wizard's own bounds for a 5K time: 12:00 to 59:59, the range its
/// minutes field and the plan-request parser accept. A time outside it could
/// not be put in the field, so it is not offered.
const int kRecent5kMinS = 12 * 60;
const int kRecent5kMaxS = 60 * 60 - 1;

class Recent5kCandidate {
  final String id;

  /// The run's start, as an ISO-8601 instant.
  final String startedAt;

  /// `runs.fastest_5k_s`: the fastest 5 km window measured inside the run.
  final num? fastest5kS;
  final String? activityType;
  final bool? isDnf;

  const Recent5kCandidate({
    required this.id,
    required this.startedAt,
    required this.fastest5kS,
    this.activityType,
    this.isDnf,
  });
}

class Recent5kSuggestion {
  final String runId;
  final String startedAt;
  final int seconds;

  const Recent5kSuggestion({
    required this.runId,
    required this.startedAt,
    required this.seconds,
  });

  @override
  bool operator ==(Object other) =>
      other is Recent5kSuggestion &&
      other.runId == runId &&
      other.startedAt == startedAt &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(runId, startedAt, seconds);

  @override
  String toString() => 'Recent5kSuggestion($runId, $startedAt, $seconds)';
}

/// Whether a value is a 5K time the wizard can take.
bool isPlausibleRecent5k(Object? seconds) =>
    seconds is num &&
    seconds.isFinite &&
    seconds == seconds.truncate() &&
    seconds >= kRecent5kMinS &&
    seconds <= kRecent5kMaxS;

/// The 5K to suggest, or null. The fastest plausible `fastest_5k_s` among
/// runs started in the last [kRecent5kWindowDays] days (not in the future),
/// ties going to the more recent run. Walks, hikes, rides and stroller runs
/// are left out, as is a DNF. [dismissedAt] is the moment the runner last
/// dismissed the suggestion: only a run started after it can bring the
/// suggestion back, so a newer 5K re-offers it and the one they waved away
/// does not. An unreadable stamp is treated as no dismissal.
Recent5kSuggestion? pickRecent5k(
  List<Recent5kCandidate> runs,
  int nowMs,
  String? dismissedAt,
) {
  final windowStartMs =
      nowMs - kRecent5kWindowDays * Duration.millisecondsPerDay;
  final dismissedMs = dismissedAt == null
      ? null
      : DateTime.tryParse(dismissedAt)?.millisecondsSinceEpoch;
  Recent5kSuggestion? best;
  var bestMs = 0;
  for (final r in runs) {
    if (r.activityType != null && r.activityType != 'run') continue;
    if (r.isDnf == true) continue;
    final raw = r.fastest5kS;
    if (!isPlausibleRecent5k(raw)) continue;
    final ms = DateTime.tryParse(r.startedAt)?.millisecondsSinceEpoch;
    if (ms == null || ms < windowStartMs || ms > nowMs) continue;
    if (dismissedMs != null && ms <= dismissedMs) continue;
    final seconds = raw!.toInt();
    if (best == null ||
        seconds < best.seconds ||
        (seconds == best.seconds && ms > bestMs)) {
      best = Recent5kSuggestion(
        runId: r.id,
        startedAt: r.startedAt,
        seconds: seconds,
      );
      bestMs = ms;
    }
  }
  return best;
}
