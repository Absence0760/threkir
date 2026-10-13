/// Finish-line detection and race timing for a live race.
///
/// Pure: no Flutter, no clock, no I/O. Every instant is handed in, so the
/// same fixes always produce the same finish. The run screen feeds one
/// [RaceFix] per fresh GPS fix through [RaceFinishDetector.offer]; the
/// controller turns the detected instant into a gun time with
/// [raceGunTimeS] and a [ServerClockOffset].
///
/// Kotlin twin: `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/RaceFinish.kt`
/// (the `race_finish` pair in `docs/architecture/parity_pairs.md`). Both
/// sides read their cases from `fixtures/race_finish_cases.json` at the repo
/// root, so a rule changes there or nowhere.
library;

import 'dart:math' as math;

/// A fix within this distance of the course's last point can be the finish.
const double kRaceFinishZoneM = 30;

/// Share of the course distance a runner must have covered before a pass
/// through the finish zone counts. It is what stops the start of a loop or
/// out-and-back course — where start and finish are the same place — from
/// finishing the race in its first second.
const double kRaceFinishMinCoverage = 0.9;

/// A recording that starts this long after GO is flagged as a late start.
const Duration kRaceLateStartAfter = Duration(minutes: 5);

/// A first fix this far from the course start is flagged as a late start.
const double kRaceLateStartFarM = 200;

const double _earthRadiusM = 6371000;

/// Great-circle distance in metres.
double raceDistanceM(double lat1, double lng1, double lat2, double lng2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180;
  final dl = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * _earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// One GPS fix as the detector sees it: where, when (device clock), and how
/// far the recording had covered at that moment.
class RaceFix {
  const RaceFix({
    required this.lat,
    required this.lng,
    required this.at,
    required this.coveredM,
  });

  final double lat;
  final double lng;
  final DateTime at;
  final double coveredM;
}

/// The detected finish: the closest-approach fix.
class RaceFinish {
  const RaceFinish({
    required this.at,
    required this.distanceToFinishM,
    required this.coveredM,
  });

  final DateTime at;
  final double distanceToFinishM;
  final double coveredM;
}

/// Whether a fix [distanceM] from the finish is inside the zone. Inclusive;
/// a non-finite distance is not.
bool raceInFinishZone(double distanceM) => distanceM <= kRaceFinishZoneM;

/// Whether [coveredM] clears the coverage gate for a course of
/// [courseDistanceM]. An unknown course distance cannot be gated, so it
/// passes: a runner is never marked DNF for data the course never carried.
bool raceCoverageMet(double coveredM, double? courseDistanceM) {
  final d = courseDistanceM;
  if (d == null || !d.isFinite || d <= 0) return true;
  return coveredM >= d * kRaceFinishMinCoverage;
}

/// Closest-approach finish detection over a stream of fixes.
///
/// A fix is a candidate when it is inside the finish zone
/// ([raceInFinishZone]) AND its covered distance clears the coverage gate
/// (inclusive). The best candidate is the closest one (the earlier on a
/// tie). Once there is one, the first fix that is strictly farther from the
/// finish than the best, or that no longer qualifies, finalises the finish
/// at the best candidate's time. A fix that jitters out of the zone
/// therefore ends the approach on the closest fix so far. A fix with a
/// non-finite position or covered distance is ignored outright: it is no
/// evidence the runner left the zone.
class RaceFinishDetector {
  RaceFinishDetector({
    required this.finishLat,
    required this.finishLng,
    required this.courseDistanceM,
  });

  final double finishLat;
  final double finishLng;
  final double courseDistanceM;

  RaceFix? _best;
  double _bestD = double.infinity;
  RaceFinish? _result;

  /// The finalised finish, once there is one.
  RaceFinish? get result => _result;

  /// The best in-zone fix so far, while the approach is still open.
  RaceFinish? get candidate {
    final best = _best;
    if (_result != null || best == null) return null;
    return RaceFinish(
        at: best.at, distanceToFinishM: _bestD, coveredM: best.coveredM);
  }

  /// Feed one fix. Returns the finish on the call that finalises it, and
  /// null on every other call, including every call after it.
  RaceFinish? offer(RaceFix fix) {
    if (_result != null) return null;
    if (!fix.lat.isFinite || !fix.lng.isFinite || !fix.coveredM.isFinite) {
      return null;
    }
    final d = raceDistanceM(fix.lat, fix.lng, finishLat, finishLng);
    final qualifies =
        raceInFinishZone(d) && raceCoverageMet(fix.coveredM, courseDistanceM);
    final best = _best;
    if (best != null && (!qualifies || d > _bestD)) return _finalise(best);
    if (qualifies && (best == null || d < _bestD)) {
      _best = fix;
      _bestD = d;
    }
    return null;
  }

  /// Finalise on the best candidate now — the recording stopped while the
  /// approach was still open. Null when no fix ever qualified.
  RaceFinish? settle() {
    if (_result != null) return _result;
    final best = _best;
    return best == null ? null : _finalise(best);
  }

  RaceFinish _finalise(RaceFix best) => _result = RaceFinish(
      at: best.at, distanceToFinishM: _bestD, coveredM: best.coveredM);
}

/// Whether a racer's start should be flagged: recording began more than
/// [kRaceLateStartAfter] after GO, or the first fix was more than
/// [kRaceLateStartFarM] from the course start. Both instants are on the
/// server clock. An unknown distance does not flag.
bool raceStartFlagged({
  required DateTime gunAt,
  required DateTime recordingStartedAt,
  double? firstFixFromStartM,
}) {
  if (recordingStartedAt.difference(gunAt) > kRaceLateStartAfter) return true;
  final d = firstFixFromStartM;
  return d != null && d.isFinite && d > kRaceLateStartFarM;
}

/// Device-clock-to-server-clock offset, estimated from request round trips.
///
/// Each sample is a write sent at [addSample]'s `sentAt`, answered with the
/// server's own `now()` as `serverAt`, received at `receivedAt`. The server
/// stamped somewhere inside the round trip, so the midpoint is the best
/// device-side estimate of that instant and the error is at most half the
/// round trip. The sample with the shortest round trip wins.
class ServerClockOffset {
  Duration? _offset;
  Duration? _bestRtt;

  /// Whether any sample has landed. Without one, [offset] is zero and the
  /// device clock is trusted as-is.
  bool get known => _offset != null;

  Duration get offset => _offset ?? Duration.zero;

  void addSample({
    required DateTime sentAt,
    required DateTime receivedAt,
    required DateTime serverAt,
  }) {
    final rtt = receivedAt.difference(sentAt);
    if (rtt.isNegative) return;
    final bestRtt = _bestRtt;
    if (bestRtt != null && rtt > bestRtt) return;
    final midpoint = sentAt.add(Duration(microseconds: rtt.inMicroseconds ~/ 2));
    _offset = serverAt.difference(midpoint);
    _bestRtt = rtt;
  }

  DateTime toServer(DateTime device) => device.add(offset);
}

/// Seconds from GO ([gunAt], server clock) to [finishAtDevice] (device
/// clock), correcting the device instant by [clockOffset]. Null when the
/// result would be negative: a gun time before GO is a clock fault, not a
/// time, and is omitted rather than clamped.
int? raceGunTimeS({
  required DateTime finishAtDevice,
  required DateTime gunAt,
  Duration clockOffset = Duration.zero,
}) {
  final ms =
      finishAtDevice.add(clockOffset).difference(gunAt).inMilliseconds;
  return ms < 0 ? null : ms ~/ 1000;
}

/// Seconds from the runner's own Start to [finishAtDevice], both on the
/// device clock, pauses included. Null when negative, like the gun time: a
/// zero would be written as a real time.
int? raceChipTimeS({
  required DateTime finishAtDevice,
  required DateTime recordingStartedAt,
}) {
  final ms = finishAtDevice.difference(recordingStartedAt).inMilliseconds;
  return ms < 0 ? null : ms ~/ 1000;
}

/// How a result was recorded. `host` is written server-side only.
enum RaceFinishMethod {
  auto('auto'),
  manual('manual'),
  host('host');

  const RaceFinishMethod(this.wire);
  final String wire;
}

/// What stopping a race recording amounts to.
class RaceOutcome {
  const RaceOutcome({
    required this.finisherStatus,
    required this.method,
    required this.finishAt,
  });

  /// `finished` or `dnf`.
  final String finisherStatus;

  /// Null for a DNF: no finish was recorded, so there is no method.
  final RaceFinishMethod? method;

  /// Device-clock instant the gun time is measured to; null for a DNF.
  final DateTime? finishAt;

  bool get finished => finisherStatus == 'finished';
}

/// The outcome of a stop: an open in-zone approach is an automatic finish
/// at its closest fix; otherwise a runner who covered enough finishes
/// manually at [now], and one who did not is a DNF. [now] is the instant the
/// runner stopped, not the later tap that confirmed it.
RaceOutcome raceStopOutcome({
  required RaceFinish? candidate,
  required double coveredM,
  required double? courseDistanceM,
  required DateTime now,
}) {
  if (candidate != null) {
    return RaceOutcome(
      finisherStatus: 'finished',
      method: RaceFinishMethod.auto,
      finishAt: candidate.at,
    );
  }
  if (raceCoverageMet(coveredM, courseDistanceM)) {
    return RaceOutcome(
      finisherStatus: 'finished',
      method: RaceFinishMethod.manual,
      finishAt: now,
    );
  }
  return const RaceOutcome(
    finisherStatus: 'dnf',
    method: null,
    finishAt: null,
  );
}

/// The timing columns of a race result row.
class RaceResultTiming {
  const RaceResultTiming({
    required this.durationS,
    required this.gunTimeS,
    required this.chipTimeS,
  });

  final int durationS;
  final int? gunTimeS;
  final int? chipTimeS;
}

/// The timing a result row carries for [outcome].
///
/// A finish carries the gun time (when the race had a GO) and the chip time
/// (when the recording's Start is known), and `duration_s` is the first of
/// gun, chip and [elapsedS] that exists. A DNF has no finish instant, so it
/// carries neither time and `duration_s` is [elapsedS] — the recording's own
/// elapsed seconds, the quantity its race pings carry and so the one the
/// server writes on a host-filed DNF (decisions § R6MOBILE-1).
RaceResultTiming raceResultTiming({
  required RaceOutcome outcome,
  required DateTime? gunAt,
  Duration clockOffset = Duration.zero,
  required DateTime? recordingStartedAt,
  required int elapsedS,
}) {
  final finishAt = outcome.finishAt;
  if (!outcome.finished || finishAt == null) {
    return RaceResultTiming(durationS: elapsedS, gunTimeS: null, chipTimeS: null);
  }
  final gun = gunAt == null
      ? null
      : raceGunTimeS(
          finishAtDevice: finishAt, gunAt: gunAt, clockOffset: clockOffset);
  final began = recordingStartedAt;
  final chip = began == null
      ? null
      : raceChipTimeS(finishAtDevice: finishAt, recordingStartedAt: began);
  return RaceResultTiming(
    durationS: gun ?? chip ?? elapsedS,
    gunTimeS: gun,
    chipTimeS: chip,
  );
}
