/// Timing-line ("gate") crossing detection, spec `gate_crossing v1` (issue
/// #1304, decisions § 2362). Pure: no Flutter, no clock, no I/O.
///
/// Web twin: `apps/web/src/lib/geo/gate_crossing.ts`; Kotlin twin:
/// `apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/GateCrossing.kt`
/// (the `gate_crossing` pairs in `docs/architecture/parity_pairs.md`). All
/// three read `fixtures/gate_crossing_cases.json`, so a rule changes there or
/// nowhere.
library;

import 'dart:math' as math;

const double kGateEarthRadiusM = 6371008.8;

// Provisional until the #1304 calibration session measures them.
const double kGateMaxGapS = 10;
const double kGateMaxHopM = 50;
const double kGateRejectGapS = 60;
const double kGateHalfWidthRaceM = 15;
const double kGateHalfWidthSegmentM = 15;

/// A line through ([lat], [lng]), perpendicular to the direction of travel
/// [bearingDeg] (clockwise from north), reaching [halfWidthM] either side.
class Gate {
  const Gate({
    required this.lat,
    required this.lng,
    required this.bearingDeg,
    required this.halfWidthM,
  });

  final double lat;
  final double lng;
  final double bearingDeg;
  final double halfWidthM;
}

/// One distinct, trusted fix, timed at its own fix instant ([tMs], epoch
/// milliseconds), with the distance the recording had covered by then.
class GateFix {
  const GateFix({
    required this.lat,
    required this.lng,
    required this.tMs,
    required this.coveredM,
  });

  final double lat;
  final double lng;
  final double tMs;
  final double coveredM;
}

enum GateDirection { forward, backward }

class GateCrossing {
  const GateCrossing({
    required this.direction,
    required this.fraction,
    required this.tMs,
    required this.coveredM,
    required this.offsetM,
    required this.gapped,
  });

  final GateDirection direction;

  /// Where between the two fixes the line was crossed, 0..1.
  final double fraction;
  final double tMs;
  final double coveredM;

  /// Lateral offset from the centre, positive to the right of travel.
  final double offsetM;

  /// The pair was more than maxGapS apart or hopped more than maxHopM.
  final bool gapped;
}

class GateCrossingOptions {
  const GateCrossingOptions({
    this.maxGapS = kGateMaxGapS,
    this.maxHopM = kGateMaxHopM,
    this.rejectGapS = kGateRejectGapS,
  });

  final double maxGapS;
  final double maxHopM;
  final double rejectGapS;
}

/// [s]: signed distance past the line along travel. [u]: lateral offset.
typedef GateProjection = ({double s, double u});

double _rad(double deg) => deg * math.pi / 180;

double _wrapLng(double d) {
  if (d >= 180) return d - 360;
  if (d < -180) return d + 360;
  return d;
}

bool _gateUsable(Gate gate) =>
    gate.lat.isFinite &&
    gate.lng.isFinite &&
    gate.bearingDeg.isFinite &&
    gate.halfWidthM.isFinite &&
    gate.halfWidthM >= 0;

/// ([lat], [lng]) on the tangent plane at the gate centre, on the gate's axes.
GateProjection gateProjection(Gate gate, double lat, double lng) {
  final x = _rad(_wrapLng(lng - gate.lng)) *
      kGateEarthRadiusM *
      math.cos(_rad(gate.lat));
  final y = _rad(lat - gate.lat) * kGateEarthRadiusM;
  final sinB = math.sin(_rad(gate.bearingDeg));
  final cosB = math.cos(_rad(gate.bearingDeg));
  return (s: x * sinB + y * cosB, u: x * cosB - y * sinB);
}

class _Projected {
  const _Projected(this.fix, this.s, this.u);
  final GateFix fix;
  final double s;
  final double u;
}

/// Streaming form: [offer] each fix as it arrives; the call that completes a
/// crossing returns it. [settle] ends the stream and returns every crossing.
class GateCrossingDetector {
  GateCrossingDetector(this.gate, [this.options = const GateCrossingOptions()])
      : _usable = _gateUsable(gate);

  final Gate gate;
  final GateCrossingOptions options;
  final bool _usable;
  _Projected? _prev;
  final List<GateCrossing> _found = [];
  bool _settled = false;

  List<GateCrossing> get crossings => List.unmodifiable(_found);

  GateCrossing? offer(GateFix fix) {
    if (_settled || !_usable) return null;
    if (!fix.lat.isFinite ||
        !fix.lng.isFinite ||
        !fix.tMs.isFinite ||
        !fix.coveredM.isFinite) {
      return null;
    }
    final prev = _prev;
    if (prev != null && fix.tMs <= prev.fix.tMs) return null;

    final p = gateProjection(gate, fix.lat, fix.lng);
    final cur = _Projected(fix, p.s, p.u);
    _prev = cur;
    if (prev == null) return null;

    final crossing = _cross(prev, cur);
    if (crossing != null) _found.add(crossing);
    return crossing;
  }

  List<GateCrossing> settle() {
    _settled = true;
    return List.of(_found);
  }

  GateCrossing? _cross(_Projected a, _Projected b) {
    final GateDirection direction;
    if (a.s < 0 && b.s >= 0) {
      direction = GateDirection.forward;
    } else if (a.s >= 0 && b.s < 0) {
      direction = GateDirection.backward;
    } else {
      return null;
    }

    final dtS = (b.fix.tMs - a.fix.tMs) / 1000;
    if (dtS > options.rejectGapS) return null;

    final f = -a.s / (b.s - a.s);
    final offsetM = a.u + f * (b.u - a.u);
    if (offsetM.abs() > gate.halfWidthM) return null;

    final ds = b.s - a.s;
    final du = b.u - a.u;
    final hopM = math.sqrt(ds * ds + du * du);
    return GateCrossing(
      direction: direction,
      fraction: f,
      tMs: a.fix.tMs + f * (b.fix.tMs - a.fix.tMs),
      coveredM: a.fix.coveredM + f * (b.fix.coveredM - a.fix.coveredM),
      offsetM: offsetM,
      gapped: dtS > options.maxGapS || hopM > options.maxHopM,
    );
  }
}

/// Batch form: every crossing of [track] through [gate], in order.
List<GateCrossing> crossingsOf(
  List<GateFix> track,
  Gate gate, [
  GateCrossingOptions options = const GateCrossingOptions(),
]) {
  final detector = GateCrossingDetector(gate, options);
  for (final fix in track) {
    detector.offer(fix);
  }
  return detector.settle();
}
