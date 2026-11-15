/// Pure race auto-match scoring. Twin of
/// `apps/web/src/lib/integrations/race_match.ts` — keep in lockstep
/// (algorithm, gates, weights, thresholds, edge cases, test count). No I/O.
///
/// The auto-match-on-record seam (race_calendar.md) offers, after a run is
/// saved, to import the official race result when the recorded run looks like
/// a listed race. INFORM-tier — nothing writes without confirmation.
/// Candidates come from the `race_match_candidates` RPC.
///
/// Three gates exclude a listing outright (issue #1389): a run that did not
/// start on the race's calendar day in any time zone, a start more than
/// [raceMatchMaxAwayM] from the race, and a distance more than
/// [raceMatchDistanceTolerance] off the race's. The date is necessary but
/// never enough: a listing is offered only when its location, its distance or
/// its course also agrees with the run. A listing that passes is scored, and a
/// run that crosses its course's start line and then its finish line ranks
/// above every listing it did not cross.
library;

import 'package:core_models/core_models.dart' show Waypoint, trackLine;

import 'gate_crossing.dart';
import 'run_stats.dart' show haversineMetres;

/// Confidence at or above which a candidate is worth offering.
const double raceMatchThreshold = 0.5;

/// Start within this radius of the listing's location scores on proximity,
/// falling off linearly to nothing at the edge.
const double raceMatchRadiusM = 5000;

/// A start further than this from the listing's location is not that race.
/// The RPC filters at the same distance.
const double raceMatchMaxAwayM = 50000;

/// The largest relative difference between the run's distance and the race's
/// that still counts: GPS overshoot plus a recording started or stopped a
/// little away from the lines, well short of a half against a full.
const double raceMatchDistanceTolerance = 0.15;

/// The race's calendar day, in the earliest and latest time zones there are
/// (UTC+14 and UTC-12): `race_date` carries no zone, so this is the widest day
/// a run on it can have started in.
const int raceMatchEarliestUtcOffsetH = 14;
const int raceMatchLatestUtcOffsetH = 12;

const double _hourMs = 3600000;
const double _dayMs = 24 * _hourMs;

/// One timed fix of the run, epoch ms.
class RaceMatchFix {
  final double lat;
  final double lng;
  final double tMs;

  const RaceMatchFix({required this.lat, required this.lng, required this.tMs});

  @override
  bool operator ==(Object other) =>
      other is RaceMatchFix &&
      other.lat == lat &&
      other.lng == lng &&
      other.tMs == tMs;

  @override
  int get hashCode => Object.hash(lat, lng, tMs);
}

class RunMatchInput {
  /// Run start as an ISO timestamp with its offset (UTC `Z` is fine).
  final String startedAt;
  final num? distanceM;

  /// The run's timed fixes, in order; null or empty when it has no track.
  final List<RaceMatchFix>? track;

  const RunMatchInput({
    required this.startedAt,
    required this.distanceM,
    this.track,
  });
}

class RaceCourseLines {
  final Gate? start;
  final Gate? finish;

  const RaceCourseLines({this.start, this.finish});
}

class RaceMatchLocation {
  final double lat;
  final double lng;

  const RaceMatchLocation({required this.lat, required this.lng});
}

class ListingMatchInput {
  final String raceDate; // ISO date (YYYY-MM-DD)
  final num? distanceM;

  /// The linked course's distance, read when the listing has none.
  final num? courseDistanceM;
  final RaceMatchLocation? location;

  /// The linked course's timing lines, when it has a public course.
  final RaceCourseLines? lines;

  const ListingMatchInput({
    required this.raceDate,
    required this.distanceM,
    this.courseDistanceM,
    this.location,
    this.lines,
  });
}

class RaceMatch {
  final double score;

  /// Whether the run crossed the course's lines in order; null when the
  /// listing has no usable line or the run has no track.
  final bool? crossesCourse;

  const RaceMatch({required this.score, required this.crossesCourse});
}

/// A stored track as timed line fixes: off-track fixes dropped, each at its
/// line position, untimed fixes skipped.
List<RaceMatchFix> raceMatchFixes(List<Waypoint>? track) {
  if (track == null) return const [];
  final out = <RaceMatchFix>[];
  for (final p in trackLine(track)) {
    final ts = p.timestamp;
    if (ts == null) continue;
    final lat = p.lineLat;
    final lng = p.lineLng;
    if (!lat.isFinite || !lng.isFinite) continue;
    out.add(RaceMatchFix(
      lat: lat,
      lng: lng,
      tMs: ts.millisecondsSinceEpoch.toDouble(),
    ));
  }
  return out;
}

final RegExp _raceDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Whether the run's start instant falls on the race's calendar day in some
/// time zone.
bool startedOnRaceDay(String startedAt, String raceDate) {
  final m = _raceDate.firstMatch(raceDate.trim());
  if (m == null) return false;
  final start = DateTime.tryParse(startedAt);
  if (start == null) return false;
  final startMs = start.millisecondsSinceEpoch.toDouble();
  final dayMs = DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  ).millisecondsSinceEpoch.toDouble();
  return startMs >= dayMs - raceMatchEarliestUtcOffsetH * _hourMs &&
      startMs < dayMs + _dayMs + raceMatchLatestUtcOffsetH * _hourMs;
}

bool _usable(Gate? gate) =>
    gate != null && gateUsable(gate) && gate.halfWidthM > 0;

/// Whether the run crossed the course's start line forward and later its
/// finish line forward (either alone when the course has only that one), by
/// `gate_crossing v1`. Null when there is no usable line or no track.
bool? runCrossesCourse(List<RaceMatchFix>? track, RaceCourseLines? lines) {
  final start = _usable(lines?.start) ? lines!.start! : null;
  final finish = _usable(lines?.finish) ? lines!.finish! : null;
  if ((start == null && finish == null) || track == null || track.length < 2) {
    return null;
  }
  // Only the crossing instants are read, so covered distance is not tracked.
  final fixes = [
    for (final f in track)
      GateFix(lat: f.lat, lng: f.lng, tMs: f.tMs, coveredM: 0),
  ];
  List<double> forward(Gate gate) => [
        for (final c in crossingsOf(fixes, gate))
          if (c.direction == GateDirection.forward) c.tMs,
      ];
  final starts = start != null ? forward(start) : null;
  final finishes = finish != null ? forward(finish) : null;
  if (starts != null && finishes != null) {
    if (starts.isEmpty || finishes.isEmpty) return false;
    return finishes.last > starts.first;
  }
  return (starts ?? finishes)!.isNotEmpty;
}

/// The match of [run] against [listing], or null when a gate excludes it.
RaceMatch? raceMatch(RunMatchInput run, ListingMatchInput listing) {
  if (!startedOnRaceDay(run.startedAt, listing.raceDate)) return null;

  final track = run.track;
  final first = track != null && track.isNotEmpty ? track.first : null;
  final loc = listing.location;
  final away = first != null && loc != null && loc.lat.isFinite && loc.lng.isFinite
      ? haversineMetres(first.lat, first.lng, loc.lat, loc.lng)
      : null;
  if (away != null && away > raceMatchMaxAwayM) return null;

  final raceM = listing.distanceM ?? listing.courseDistanceM;
  final runM = run.distanceM;
  final runMeasured = runM != null && runM.isFinite && runM > 0;
  final off = raceM != null && raceM > 0 && runMeasured
      ? (runM / raceM - 1).abs().toDouble()
      : null;
  if (off != null && off > raceMatchDistanceTolerance) return null;

  final crossesCourse = runCrossesCourse(track, listing.lines);

  final near = away != null && away <= raceMatchRadiusM;
  if (!near && off == null && crossesCourse != true) return null;

  // Proximity and distance weigh in whenever the run can be measured on
  // them, so a listing that leaves one unknown earns nothing for it rather
  // than being normalised up to the listings that agree. The course weighs
  // in only when both sides have it: a listing without lines is not evidence
  // against the run.
  double score = 0.5;
  double weight = 0.5;
  if (first != null) {
    weight += 0.3;
    if (near) score += 0.3 * (1 - away / raceMatchRadiusM);
  }
  if (runMeasured) {
    weight += 0.2;
    if (off != null) score += 0.2 * (1 - off / raceMatchDistanceTolerance);
  }
  if (crossesCourse != null) {
    weight += 0.5;
    if (crossesCourse) score += 0.5;
  }
  return RaceMatch(score: score / weight, crossesCourse: crossesCourse);
}

/// 0..1 confidence that [run] is the race in [listing]; 0 when excluded.
double raceMatchScore(RunMatchInput run, ListingMatchInput listing) =>
    raceMatch(run, listing)?.score ?? 0;

/// Whether a listing is a confident-enough candidate to offer.
bool isRaceMatchCandidate(RunMatchInput run, ListingMatchInput listing) =>
    raceMatchScore(run, listing) >= raceMatchThreshold;

/// The listing to offer: a candidate whose course the run crossed first, then
/// the highest score; on a tie the earlier listing (the RPC's nearest first).
T? bestRaceMatch<T>(
  RunMatchInput run,
  List<T> listings,
  ListingMatchInput Function(T listing) input,
) {
  T? best;
  RaceMatch? bestMatch;
  for (final l in listings) {
    final m = raceMatch(run, input(l));
    if (m == null || m.score < raceMatchThreshold) continue;
    if (bestMatch == null || _ranksAbove(m, bestMatch)) {
      best = l;
      bestMatch = m;
    }
  }
  return best;
}

bool _ranksAbove(RaceMatch a, RaceMatch b) {
  final ac = a.crossesCourse == true;
  final bc = b.crossesCourse == true;
  if (ac != bc) return ac;
  return a.score > b.score;
}
