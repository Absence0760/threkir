/// Finish-line detection and race timing for a live race.
///
/// Pure: no Flutter, no clock, no I/O. Every instant is handed in, so the
/// same fixes always produce the same finish. The run screen feeds one
/// [RaceFix] per fresh GPS fix through [RaceFinishDetector.offer]; the
/// controller turns the detected instant into a gun time with
/// [raceGunTimeS] and a [ServerClockOffset].
///
/// Spec `race_finish v3` (issue #1304, decisions § 2472): with a start or finish line
/// ([Gate]) the start and finish are line crossings from `gate_crossing`;
/// a course with neither line, in a gun mode, behaves exactly as v1.
///
/// Kotlin twin: `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/RaceFinish.kt`;
/// web twin: `apps/web/src/lib/races/race_finish.ts` (the `race_finish`
/// pairs in `docs/architecture/parity_pairs.md`). All three read their cases
/// from `fixtures/race_finish_cases.json` at the repo root, so a rule changes
/// there or nowhere.
library;

import 'gate_crossing.dart';
import 'run_stats.dart' show haversineMetres;

/// A fix within this distance of the course's last point can be the finish.
const double kRaceFinishZoneM = 30;

/// Share of the course distance a runner must have covered before a pass
/// through the finish zone counts. It is what stops the start of a loop or
/// out-and-back course — where start and finish are the same place — from
/// finishing the race in its first second.
const double kRaceFinishMinCoverage = 0.9;

/// Share of the course distance a LINE finish needs when coverage is
/// measured from a committed start (a start-line crossing, or GO for a
/// runner already past the line). Provisional until the #1304 calibration
/// session: #1303 gives 50-60 %, and this takes the cautious end.
const double kRaceFinishMinCoverageWithStart = 0.6;

/// Covered distance a forward start-line crossing after GO must be followed
/// by, with no backward crossing, before it is the runner's start. Covered
/// distance, not distance past the line, so a course turning within it still
/// commits. Provisional until the #1304 calibration session.
const double kRaceStartCommitM = 50;

/// A recording that starts this long after GO is flagged as a late start.
const Duration kRaceLateStartAfter = Duration(minutes: 5);

/// A first fix this far from the course start is flagged as a late start.
const double kRaceLateStartFarM = 200;

/// Great-circle distance in metres.
double raceDistanceM(double lat1, double lng1, double lat2, double lng2) =>
    haversineMetres(lat1, lng1, lat2, lng2);

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

/// How the race's clock started for this runner. Host GO and Scheduled GO
/// are both [gun]: the server's GO exists. [selfTimed] has no GO; each
/// runner's start line crossing starts their clock.
enum RaceStartMode { gun, selfTimed }

/// Where a line-detected start came from: a forward start-line crossing, or
/// GO itself for a runner already past the line at GO. Both are
/// `start_detection = 'gate'`; no [RaceStart] at all is `'device'` (the
/// runner's own Start press).
enum RaceStartKind { line, go }

/// The committed start a finish is measured from.
class RaceStart {
  const RaceStart({
    required this.at,
    required this.coveredM,
    required this.kind,
    this.gapped = false,
  });

  final DateTime at;
  final double coveredM;
  final RaceStartKind kind;

  /// The crossing came from a pair of fixes far apart in time or space.
  final bool gapped;
}

/// What decided a finish: the finish line, or the 30 m zone around the
/// course's last point.
enum RaceFinishDetection {
  zone('zone'),
  gate('gate');

  const RaceFinishDetection(this.wire);
  final String wire;
}

/// The detected finish: the closest-approach fix in the zone, or the
/// interpolated finish-line crossing. For a line finish
/// [distanceToFinishM] is the crossing's lateral offset from the line's
/// centre.
class RaceFinish {
  const RaceFinish({
    required this.at,
    required this.distanceToFinishM,
    required this.coveredM,
    this.detection = RaceFinishDetection.zone,
    this.start,
    this.gapped = false,
  });

  final DateTime at;
  final double distanceToFinishM;
  final double coveredM;
  final RaceFinishDetection detection;

  /// The committed start coverage was measured from; null when it was the
  /// runner's own Start press.
  final RaceStart? start;

  /// A line finish crossed between fixes far apart in time or space.
  final bool gapped;
}

/// Whether [gate] can time a race: one `gate_crossing` can use, with a
/// positive half-width. Anything else is treated as no line.
bool raceLineUsable(Gate? gate) =>
    gate != null && gateUsable(gate) && gate.halfWidthM > 0;

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

/// Finish detection over a stream of fixes, spec `race_finish v2`.
///
/// **Without a line** (gun mode, no usable start or finish line) it is v1:
/// closest approach. A fix is a candidate when it is inside the finish zone
/// ([raceInFinishZone]) AND its covered distance clears the coverage gate
/// (inclusive). The best candidate is the closest one (the earlier on a
/// tie). Once there is one, the first fix that is strictly farther from the
/// finish than the best, or that no longer qualifies, finalises the finish
/// at the best candidate's time. A fix that jitters out of the zone
/// therefore ends the approach on the closest fix so far. A fix with a
/// non-finite position or covered distance is ignored outright: it is no
/// evidence the runner left the zone.
///
/// **With lines** every fix also goes through a `gate_crossing` detector
/// per line, and a fix timed at or before the last one is skipped.
/// - Start, gun mode with a start line: the runner's side of the line at GO
///   (the start-line distance `s` interpolated to GO) decides. On or past it
///   (`s >= 0`, as `gate_crossing` counts a fix on the line), the start is
///   GO. Behind it, the start is the first forward crossing after GO that is
///   followed by [kRaceStartCommitM] of covered distance with no backward
///   crossing; a backward crossing first voids it, and a later forward
///   crossing before it commits replaces it. Until GO is known every fix is
///   held and replayed by [setGo], so a late GO gives the same answer; a
///   race whose GO never comes holds the whole recording until [settle]
///   drops it and finishes nothing.
/// - Start, self-timed: a forward start-line crossing commits as a gun
///   one does, with no GO. Once committed, a later forward crossing (the
///   next lap) changes nothing, and a backward one (an out-and-back coming
///   home) re-arms it without clearing it: the committed start stays the
///   start until a new forward crossing commits and replaces it. Once the
///   runner has passed the finish line forward since the start, or covered
///   [kRaceFinishMinCoverage] of the course from it, a backward crossing is
///   ignored (a GPS wobble at a lap pass must not restart the clock). A
///   backward crossing inside the commit distance voids the crossing as in
///   a gun race. No committed start, no finish.
/// - Start, no start line (gun mode): the Start press, coverage counted from
///   it as in v1.
/// - Coverage is the covered distance since the start. A gun-mode runner
///   with a start line but no committed start is measured from GO (never
///   from before it, so a warm-up does not count), and one whose crossing is
///   still committing cannot finish.
/// - Finish line: the first forward crossing whose coverage clears
///   [kRaceFinishMinCoverageWithStart] from a committed start, or
///   [kRaceFinishMinCoverage] without one. Once GO is known nothing before
///   it finishes, with or without a start line.
/// - Laps: a lap pass is a forward finish crossing from a committed start
///   at least the lines' separation (centre to centre) plus
///   [kRaceStartCommitM] past it, and [kRaceStartCommitM] past the previous
///   pass. With the lap count the race froze for a lap course ([lapCount],
///   `race_session_courses.finish_lap_count`) the line finish is the pass
///   that brings the count to it, the share kept as a floor. With none, from
///   the second pass on the share's floor rises to the course distance less
///   half the lap just run. [lapsMet] applies the same rule to a stop and
///   to the zone.
/// - The zone with a finish line decides only on [settle], and only for a
///   runner inside it at that moment; leaving it finishes nobody. Without a
///   finish line the zone is v1's closest approach. The zone always needs
///   [kRaceFinishMinCoverage], measured from the start as above.
/// - A crossing between two fixes finishes the race at its interpolated
///   instant, rounded to the millisecond. A start and finish crossing
///   between the same two fixes are taken in time order; on a tie a gun
///   race takes the start first (so the pending start blocks the finish)
///   and a self-timed race the finish first (so the lap is measured from
///   the previous crossing): either way a loop whose two lines coincide is
///   not its own start.
class RaceFinishDetector {
  RaceFinishDetector({
    required this.finishLat,
    required this.finishLng,
    required this.courseDistanceM,
    Gate? startGate,
    Gate? finishGate,
    this.mode = RaceStartMode.gun,
    DateTime? goAt,
    int? lapCount,
  })  : startGate = raceLineUsable(startGate) ? startGate : null,
        finishGate = raceLineUsable(finishGate) ? finishGate : null,
        lapCount = raceLineUsable(finishGate) && lapCount != null && lapCount >= 2
            ? lapCount
            : null {
    if (mode == RaceStartMode.selfTimed) _state = _StartState.seeking;
    final s = this.startGate;
    final f = this.finishGate;
    _sepM = s != null && f != null ? raceDistanceM(s.lat, s.lng, f.lat, f.lng) : 0;
    _startLine = s == null ? null : GateCrossingDetector(s);
    _finishLine = f == null ? null : GateCrossingDetector(f);
    if (goAt != null) setGo(goAt);
  }

  final double finishLat;
  final double finishLng;
  final double courseDistanceM;

  /// The start line, or null when none was given or it is unusable.
  final Gate? startGate;

  /// The finish line, or null when none was given or it is unusable.
  final Gate? finishGate;
  final RaceStartMode mode;

  /// The course's lap count, or null when the race froze none.
  final int? lapCount;

  /// Metres between the two lines' centres; 0 without both.
  late final double _sepM;
  late final GateCrossingDetector? _startLine;
  late final GateCrossingDetector? _finishLine;

  RaceFix? _best;
  double _bestD = double.infinity;
  RaceStart? _bestStart;
  RaceFinish? _result;

  DateTime? _goAt;
  double? _goMs;
  final List<RaceFix> _held = [];
  bool _closed = false;
  _Sampled? _prev;
  _StartState _state = _StartState.preGo;
  GateCrossing? _pending;
  RaceStart? _committed;
  double _goCoveredM = 0;
  int _passes = 0;
  double? _lastPassM;
  double? _lapM;
  bool _finishSeen = false;
  bool _utc = false;

  bool get _v1 =>
      mode == RaceStartMode.gun && startGate == null && finishGate == null;

  bool get _awaitingGo =>
      mode == RaceStartMode.gun && startGate != null && _goMs == null;

  /// The finalised finish, once there is one.
  RaceFinish? get result => _result;

  /// The best in-zone fix so far, while the approach is still open.
  RaceFinish? get candidate {
    final best = _best;
    if (_result != null || _closed || best == null) return null;
    return RaceFinish(
        at: best.at,
        distanceToFinishM: _bestD,
        coveredM: best.coveredM,
        start: _bestStart);
  }

  /// The start a finish would be measured from right now: the committed
  /// start. A self-timed start a backward crossing has re-armed stays it
  /// until a new forward crossing commits. Null for the Start press, and
  /// while the first crossing is still committing.
  RaceStart? get start => _committed;

  /// Feed one fix. Returns the finish on the call that finalises it, and
  /// null on every other call, including every call after it.
  RaceFinish? offer(RaceFix fix) {
    if (_v1) return _offerV1(fix);
    if (_result != null || _closed) return null;
    if (_awaitingGo) {
      _held.add(fix);
      return null;
    }
    return _process(fix);
  }

  /// GO, on the device clock the fixes are timed on. GO is fixed once set,
  /// so a second call changes nothing. In a gun mode with a start line the
  /// fixes held until now are replayed, and the call returns the finish when
  /// that replay finalises one.
  RaceFinish? setGo(DateTime at) {
    if (_goMs != null) return null;
    _goAt = at;
    _goMs = _ms(at);
    if (_held.isEmpty) return null;
    final held = List.of(_held);
    _held.clear();
    if (_result != null || _closed) return null;
    for (final fix in held) {
      final r = _process(fix);
      if (r != null) return r;
    }
    return null;
  }

  /// Finalise on the best candidate now — the recording stopped while the
  /// approach was still open. Null when no fix ever qualified. With lines
  /// the stream is closed either way; a gun race whose GO never arrived
  /// finishes nothing automatically.
  RaceFinish? settle() {
    if (_result != null) return _result;
    if (_v1) {
      final best = _best;
      return best == null ? null : _finalise(best);
    }
    _closed = true;
    _held.clear();
    final best = _best;
    return best == null ? null : _finalise(best);
  }

  RaceFinish? _offerV1(RaceFix fix) {
    if (_result != null) return null;
    if (!fix.lat.isFinite || !fix.lng.isFinite || !fix.coveredM.isFinite) {
      return null;
    }
    final d = raceDistanceM(fix.lat, fix.lng, finishLat, finishLng);
    final qualifies = raceInFinishZone(d) &&
        _covers(0, fix.coveredM, kRaceFinishMinCoverage);
    final best = _best;
    if (best != null && (!qualifies || d > _bestD)) return _finalise(best);
    if (qualifies && (best == null || d < _bestD)) {
      _best = fix;
      _bestD = d;
    }
    return null;
  }

  RaceFinish? _process(RaceFix fix) {
    if (!fix.lat.isFinite || !fix.lng.isFinite || !fix.coveredM.isFinite) {
      return null;
    }
    final t = _ms(fix.at);
    final prev = _prev;
    if (prev != null && t <= prev.tMs) return null;
    final sg = startGate;
    final cur = _Sampled(
        fix, t, sg == null ? 0 : gateProjection(sg, fix.lat, fix.lng).s);
    _prev = cur;
    _utc = fix.at.isUtc;

    final go = _goMs;
    if (mode == RaceStartMode.gun &&
        sg != null &&
        _state == _StartState.preGo &&
        go != null &&
        t >= go) {
      _resolveGo(prev, cur, go);
    }

    final gf =
        GateFix(lat: fix.lat, lng: fix.lng, tMs: t, coveredM: fix.coveredM);
    final sc = _startLine?.offer(gf);
    final fc = _finishLine?.offer(gf);
    if (sc != null &&
        fc != null &&
        (sc.tMs < fc.tMs ||
            (sc.tMs == fc.tMs && mode == RaceStartMode.gun))) {
      _onStartCrossing(sc);
      _onFinishCrossing(fc);
    } else {
      if (fc != null) _onFinishCrossing(fc);
      if (_result == null && sc != null) _onStartCrossing(sc);
    }
    if (_result != null) return _result;

    _advanceCommit(fix.coveredM);
    _zone(fix, t);
    return _result;
  }

  void _resolveGo(_Sampled? prev, _Sampled cur, double go) {
    var sGo = cur.s;
    var cGo = cur.fix.coveredM;
    if (prev != null && prev.tMs < go) {
      final f = (go - prev.tMs) / (cur.tMs - prev.tMs);
      sGo = prev.s + f * (cur.s - prev.s);
      cGo = prev.fix.coveredM + f * (cur.fix.coveredM - prev.fix.coveredM);
    }
    if (sGo >= 0) {
      _committed =
          RaceStart(at: _goAt!, coveredM: cGo, kind: RaceStartKind.go);
      _state = _StartState.committed;
    } else {
      _goCoveredM = cGo;
      _state = _StartState.seeking;
    }
  }

  void _advanceCommit(double coveredM) {
    final p = _pending;
    if (_state != _StartState.pending || p == null) return;
    if (coveredM >= p.coveredM + kRaceStartCommitM) {
      if (_committed != null) _forgetLaps();
      _committed = _lineStart(p);
      _pending = null;
      _state = _StartState.committed;
    }
  }

  void _onStartCrossing(GateCrossing x) {
    _advanceCommit(x.coveredM);
    if (mode == RaceStartMode.selfTimed) {
      if (x.direction == GateDirection.forward) {
        if (_state == _StartState.committed) return;
        _pending = x;
        _state = _StartState.pending;
      } else {
        if (_startHeld(x.coveredM)) return;
        _pending = null;
        _state = _StartState.seeking;
      }
      return;
    }
    switch (_state) {
      case _StartState.seeking:
      case _StartState.pending:
        if (x.direction == GateDirection.forward) {
          _pending = x;
          _state = _StartState.pending;
        } else {
          _pending = null;
          _state = _StartState.seeking;
        }
      case _StartState.preGo:
      case _StartState.committed:
        break;
    }
  }

  void _onFinishCrossing(GateCrossing x) {
    if (x.direction != GateDirection.forward) return;
    _advanceCommit(x.coveredM);
    final base = _base(x.tMs);
    if (base == null) return;
    if (base.start != null) _finishSeen = true;
    final pass = _countPass(base, x.coveredM);
    final k = lapCount;
    if (k != null && base.start != null && (!pass || _passes < k)) return;
    final threshold = base.start != null
        ? kRaceFinishMinCoverageWithStart
        : kRaceFinishMinCoverage;
    if (!_covers(base.fromM, x.coveredM, threshold)) return;
    _result = RaceFinish(
      at: _instant(x.tMs),
      distanceToFinishM: x.offsetM.abs(),
      coveredM: x.coveredM,
      detection: RaceFinishDetection.gate,
      start: base.start,
      gapped: x.gapped,
    );
  }

  void _zone(RaceFix fix, double t) {
    final d = raceDistanceM(fix.lat, fix.lng, finishLat, finishLng);
    final base = _base(t);
    final qualifies = raceInFinishZone(d) &&
        base != null &&
        _covers(base.fromM, fix.coveredM, kRaceFinishMinCoverage) &&
        lapsMet(fix.coveredM) != false;
    final best = _best;
    if (finishGate != null) {
      if (!qualifies) {
        _best = null;
        _bestD = double.infinity;
        _bestStart = null;
      } else if (best == null || d < _bestD) {
        _best = fix;
        _bestD = d;
        _bestStart = base.start;
      }
      return;
    }
    if (best != null && (!qualifies || d > _bestD)) {
      _finalise(best);
      return;
    }
    if (qualifies && (best == null || d < _bestD)) {
      _best = fix;
      _bestD = d;
      _bestStart = base.start;
    }
  }

  /// Where coverage is counted from at [tMs], and the start it belongs to;
  /// null when no finish can count then.
  ({double fromM, RaceStart? start})? _base(double tMs) {
    if (mode == RaceStartMode.selfTimed) {
      final c = _committed;
      return c == null ? null : (fromM: c.coveredM, start: c);
    }
    final go = _goMs;
    if (go != null && tMs < go) return null;
    if (startGate == null) return (fromM: 0, start: null);
    if (go == null) return null;
    switch (_state) {
      case _StartState.committed:
        final c = _committed!;
        return (fromM: c.coveredM, start: c);
      case _StartState.seeking:
        return (fromM: _goCoveredM, start: null);
      case _StartState.preGo:
      case _StartState.pending:
        return null;
    }
  }

  /// A self-timed start a backward crossing may no longer re-arm: the
  /// runner has passed the finish line forward since it, or covered the
  /// no-start share of the course, so they are on a later lap or coming home.
  bool _startHeld(double coveredM) {
    final c = _committed;
    if (c == null) return false;
    if (_finishSeen) return true;
    final d = courseDistanceM;
    return d.isFinite &&
        d > 0 &&
        coveredM - c.coveredM >= d * kRaceFinishMinCoverage;
  }

  /// Whether a forward finish crossing at [coveredM] is a lap pass: from a
  /// committed start, at least the lines' separation plus
  /// [kRaceStartCommitM] past it (so the start's own pass is not one), and
  /// [kRaceStartCommitM] past the last pass (so a wobble across the line is
  /// one pass). Records it.
  bool _countPass(({double fromM, RaceStart? start}) base, double coveredM) {
    if (base.start == null) return false;
    if (coveredM - base.fromM < _sepM + kRaceStartCommitM) return false;
    final last = _lastPassM;
    if (last != null && coveredM - last < kRaceStartCommitM) return false;
    _lapM = last == null ? coveredM - base.fromM - _sepM : coveredM - last;
    _lastPassM = coveredM;
    _passes += 1;
    return true;
  }

  void _forgetLaps() {
    _passes = 0;
    _lastPassM = null;
    _lapM = null;
    _finishSeen = false;
  }

  /// Whether [coveredM] completes the laps, for a stop or a zone finish:
  /// with a lap count, every pass but the last made and half a lap since it
  /// (the lap measured as the runner's own mean), or every pass made; with
  /// none, from the second pass on, the coverage rule scaled by the lap just
  /// run. Null when no lap rule applies (no lap known, or no committed start
  /// to count from).
  bool? lapsMet(double coveredM) {
    final b = _base(double.infinity);
    if (b == null) return null;
    final k = lapCount;
    if (k != null) {
      if (b.start == null) return null;
      if (_passes >= k) return true;
      final last = _lastPassM;
      if (_passes == k - 1 && last != null) {
        final mean = (last - b.fromM - _sepM) / _passes;
        return coveredM - last >= mean / 2;
      }
      return false;
    }
    if (_passes >= 2) {
      return _covers(b.fromM, coveredM, kRaceFinishMinCoverage);
    }
    return null;
  }

  /// Covered distance from the base a finish needs at [share]; null when
  /// nothing can gate. With no lap count frozen, from the second pass on,
  /// the lap just run raises it to the course less half that lap (the
  /// runner's own lap, so a course whose laps differ is judged by the
  /// latest one). A first pass needs no floor: on a course of two or more
  /// laps it is at most half the course, under the share, and a single loop
  /// keeps the share's margin.
  double? _required(double share) {
    final d = courseDistanceM;
    if (!d.isFinite || d <= 0) return null;
    final lap = lapCount == null && _passes >= 2 ? _lapM : null;
    final need = d * share;
    if (lap == null) return need;
    final floor = d - lap / 2;
    return floor > need ? floor : need;
  }

  bool _covers(double fromM, double coveredM, double share) {
    final need = _required(share);
    return need == null || coveredM - fromM >= need;
  }

  RaceFinish _finalise(RaceFix best) => _result = RaceFinish(
      at: best.at,
      distanceToFinishM: _bestD,
      coveredM: best.coveredM,
      start: _bestStart);

  DateTime _instant(double tMs) =>
      DateTime.fromMillisecondsSinceEpoch(tMs.round(), isUtc: _utc);

  RaceStart _lineStart(GateCrossing x) => RaceStart(
        at: _instant(x.tMs),
        coveredM: x.coveredM,
        kind: RaceStartKind.line,
        gapped: x.gapped,
      );
}

enum _StartState { preGo, seeking, pending, committed }

class _Sampled {
  const _Sampled(this.fix, this.tMs, this.s);
  final RaceFix fix;
  final double tMs;
  final double s;
}

double _ms(DateTime at) => at.microsecondsSinceEpoch / 1000;

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
/// runner stopped, not the later tap that confirmed it. [lapsMet] is the
/// detector's [RaceFinishDetector.lapsMet] at the stop: false (a lap course
/// not run to its last lap) is a DNF whatever the distance; null leaves the
/// distance to decide.
RaceOutcome raceStopOutcome({
  required RaceFinish? candidate,
  required double coveredM,
  required double? courseDistanceM,
  required DateTime now,
  bool? lapsMet,
}) {
  if (candidate != null) {
    return RaceOutcome(
      finisherStatus: 'finished',
      method: RaceFinishMethod.auto,
      finishAt: candidate.at,
    );
  }
  if (raceCoverageMet(coveredM, courseDistanceM) && lapsMet != false) {
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
/// gun, chip and [elapsedS] that exists. The chip time never exceeds the gun
/// time: a recording started while the race was armed joins it at GO, and
/// the wait on the line before GO is no part of the runner's race
/// (decisions § 1861). With a committed start ([startAt], device clock: a
/// start-line crossing, or GO for a runner already past the line) the chip
/// time runs from it instead of the Start press, under the same cap. A DNF
/// has no finish instant, so it
/// carries neither time and `duration_s` is [elapsedS] — the recording's own
/// elapsed seconds, the quantity its race pings carry and so the one the
/// server writes on a host-filed DNF (decisions § 1855).
RaceResultTiming raceResultTiming({
  required RaceOutcome outcome,
  required DateTime? gunAt,
  Duration clockOffset = Duration.zero,
  required DateTime? recordingStartedAt,
  DateTime? startAt,
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
  final began = startAt ?? recordingStartedAt;
  final fromStart = began == null
      ? null
      : raceChipTimeS(finishAtDevice: finishAt, recordingStartedAt: began);
  final chip =
      gun != null && fromStart != null && fromStart > gun ? gun : fromStart;
  return RaceResultTiming(
    durationS: gun ?? chip ?? elapsedS,
    gunTimeS: gun,
    chipTimeS: chip,
  );
}
