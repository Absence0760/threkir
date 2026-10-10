import 'dart:math' as math;

/// GPS distance estimator, spec v1.3 — a port of
/// `scripts/gps_distance/reference.py`, which is the spec. See
/// `docs/features/gps_distance.md`. Every operation mirrors the reference so
/// `fixtures/gps_distance_vectors.json` replays to 1e-3 m; do not tune a
/// constant here without changing the reference and every other port.
///
/// Two entry points: this class is the forward (causal) filter the live
/// screen runs; [smoothDistance] is the saved / recomputed figure, a forward
/// pass plus a Rauch-Tung-Striebel backward pass over the whole run.
class GpsDistanceEstimator {
  GpsDistanceEstimator({
    double maxSpeedMps = 10.0,
    double expectedIntervalS = 1.0,
    double? initialStrideM,
  }) : this._(
         maxSpeedMps: maxSpeedMps,
         expectedIntervalS: expectedIntervalS,
         initialStrideM: initialStrideM,
         record: false,
       );

  GpsDistanceEstimator._({
    required this.maxSpeedMps,
    required double expectedIntervalS,
    required double? initialStrideM,
    required bool record,
  }) : _gapS = gapS * _intervalScale(expectedIntervalS),
       _freshFixS = freshFixS * _intervalScale(expectedIntervalS),
       _strideM =
           (_valid(initialStrideM) &&
               minStrideM <= initialStrideM! &&
               initialStrideM <= maxStrideM)
           ? initialStrideM
           : null,
       _records = record ? <_FixRecord>[] : null;

  static const String specVersion = '1.3';

  static const double earthRadiusM = 6371008.8;
  static const double qAccel = 0.6;
  static const double minPosSigmaM = 3.0;
  static const double initVelVar = 25.0;
  static const double minSpeedSigmaMps = 0.3;
  static const double defaultSpeedSigmaMps = 0.5;
  static const double maxSpeedSigmaMps = 1.5;
  static const double stationarySpeedMps = 0.4;
  static const double posOnlyStationarySpeedMps = 0.8;
  static const double gapS = 10.0;
  static const double freshFixS = 2.0;
  static const int strideWindowSteps = 50;
  static const double minStrideM = 0.4;
  static const double maxStrideM = 2.5;
  static const double strideEmaAlpha = 0.2;

  static const double gateChi2 = 13.8155;
  static const int gateMaxRejects = 5;
  static const double rScaleAlpha = 0.05;
  static const double rScaleMin = 1.0;
  static const double rScaleMax = 9.0;
  static const double xcheckTauS = 60.0;
  static const double xcheckMinS = 120.0;
  static const double xcheckEnterAbsMps = 0.4;
  static const double xcheckEnterRel = 0.15;
  static const double xcheckExitAbsMps = 0.2;
  static const double xcheckExitRel = 0.08;
  static const double xcheckPersistS = 60.0;
  static const double xcheckMaxSpanS = 5.0;
  static const double debiasFullMps = 0.5;
  static const double debiasZeroMps = 1.0;
  static const double dscaleTauS = 600.0;
  static const double dscaleMinS = 60.0;
  static const double dscaleMin = 0.8;
  static const double dscaleMax = 1.25;
  static const double dscaleMinSpeedMps = 1.5;
  static const double dscaleMaxTurnDeg = 45.0;
  static const double zuptNoStepS = 6.0;
  static const double zuptVelSigmaMps = 0.1;
  static const double zuptDopplerOverrideMps = 1.0;
  static const double zuptReleaseM = 40.0;
  static const double stopHalfWindowS = 20.0;
  static const int stopMinHalfFixes = 3;
  static const double stopSpeedMps = 0.5;
  static const double stopRadiusM = 10.0;

  final double maxSpeedMps;
  final double _gapS;
  final double _freshFixS;

  double _gpsDistanceM = 0.0;
  double _stepDistanceM = 0.0;
  double? _strideM;
  double? _lat0;
  double? _lng0;
  _Axis? _x;
  _Axis? _y;
  double? _t;
  int _winSteps = 0;
  double _winM = 0.0;
  int? _lastSteps;
  double? _lastStepT;
  double _pendingStepM = 0.0;

  double _rScale = 1.0;
  int _rejectedFixes = 0;
  int _rejectStreak = 0;
  bool _dopplerTrusted = true;
  double _xcDoppler = 0.0;
  double _xcPos = 0.0;
  double _xcTime = 0.0;
  double _xcPersistS = 0.0;
  // (x, y, t) of the last fix whose position the filter took.
  double? _xcLastX;
  double? _xcLastY;
  double? _xcLastT;
  double _dopplerScale = 1.0;
  double _dsPos = 0.0;
  double _dsDop = 0.0;
  double _dsTime = 0.0;
  // (x, y, t, dop, bearing) of the last fix whose position the filter took.
  double? _dsLastX;
  double? _dsLastY;
  double? _dsLastT;
  double? _dsLastDop;
  double? _dsLastBearing;
  bool _stepsSeen = false;
  double? _lastStepIncT;
  bool _zuptReleased = false;
  double? _zuptAnchorX;
  double? _zuptAnchorY;
  int _zuptFixes = 0;
  final List<_FixRecord>? _records;

  double get distanceM => _gpsDistanceM + _stepDistanceM;
  double get gpsDistanceM => _gpsDistanceM;
  double get stepDistanceM => _stepDistanceM;
  double? get strideM => _strideM;
  double get rScale => _rScale;
  int get rejectedFixes => _rejectedFixes;
  int get zuptFixes => _zuptFixes;
  bool get dopplerTrusted => _dopplerTrusted;
  double get dopplerScale => _dopplerScale;

  static bool _valid(double? x) => x != null && x.isFinite;

  void _setDsLast(double x, double y, double t, double? dop, double? bearing) {
    _dsLastX = x;
    _dsLastY = y;
    _dsLastT = t;
    _dsLastDop = dop;
    _dsLastBearing = bearing;
  }

  static double _intervalScale(double it) =>
      (_valid(it) && it > 1.0) ? it : 1.0;

  static double _radians(double deg) => deg * (math.pi / 180.0);

  static double _degrees(double rad) => rad * (180.0 / math.pi);

  static double _wrapLng(double d) {
    if (d >= 180.0) return d - 360.0;
    if (d < -180.0) return d + 360.0;
    return d;
  }

  /// Inverse of the tangent-plane projection the first fix fixed.
  ({double lat, double lng}) unproject(double x, double y) {
    final lat0 = _lat0!;
    final lng0 = _lng0!;
    final lat = lat0 + _degrees(y / earthRadiusM);
    final lng = lng0 + _degrees(x / (earthRadiusM * math.cos(_radians(lat0))));
    return (lat: lat, lng: _wrapLng(lng));
  }

  /// Pedometer says stationary: steps seen this run, none for
  /// [zuptNoStepS], Doppler not contradicting.
  bool _zuptDue(double t, double? dop) {
    if (!_stepsSeen || _zuptReleased || t - _lastStepIncT! <= zuptNoStepS) {
      return false;
    }
    return !(dop != null && _dopplerTrusted && dop >= zuptDopplerOverrideMps);
  }

  void _record({
    required bool anchor,
    required bool chainBreak,
    required double dt,
    required _AxisState? predX,
    required _AxisState? predY,
    required bool zupt,
    required double? dop,
    required double? chord,
  }) {
    final records = _records;
    if (records == null) return;
    records.add(
      _FixRecord(
        anchor: anchor,
        chainBreak: chainBreak,
        dt: dt,
        predX: predX,
        predY: predY,
        x: _x!.state(),
        y: _y!.state(),
        zupt: zupt,
        dop: dop,
        chord: chord,
        stepDistanceM: _stepDistanceM,
      ),
    );
  }

  /// [t] is seconds on a clock monotonic within the run. Returns the metres
  /// credited by this fix. [stoppedHint]: the caller knows the runner is
  /// stationary (post-hoc stop detection); live recorders always pass false.
  double addFix({
    required double t,
    required double lat,
    required double lng,
    double? accuracyM,
    double? speedMps,
    double? speedAccuracyMps,
    double? bearingDeg,
    bool stoppedHint = false,
  }) {
    if (!(_valid(t) && _valid(lat) && _valid(lng))) return 0.0;
    if (_lat0 == null) {
      _lat0 = lat;
      _lng0 = lng;
    }
    final zx =
        _radians(_wrapLng(lng - _lng0!)) *
        earthRadiusM *
        math.cos(_radians(_lat0!));
    final zy = _radians(lat - _lat0!) * earthRadiusM;
    final sigma = (_valid(accuracyM) && accuracyM! > 0)
        ? accuracyM
        : minPosSigmaM;
    final rStated = _sq(math.max(sigma, minPosSigmaM));
    final r = math.max(rStated * _rScale, minPosSigmaM * minPosSigmaM);
    final prevT = _t;
    if (prevT != null && t <= prevT) return 0.0;
    final doppler = _dopplerSpeed(speedMps, speedAccuracyMps, maxSpeedMps);
    final dop = doppler?.s;
    if (prevT == null || t - prevT > _gapS) {
      // (Re-)anchor. Steps buffered across a real gap are committed now.
      if (prevT != null) _stepDistanceM += _pendingStepM;
      _pendingStepM = 0.0;
      _x = _Axis(zx, r);
      _y = _Axis(zy, r);
      _t = t;
      _xcLastX = zx;
      _xcLastY = zy;
      _xcLastT = t;
      _setDsLast(zx, zy, t, dop, bearingDeg);
      _rejectStreak = 0;
      _zuptAnchorX = null;
      _zuptAnchorY = null;
      final zupt = stoppedHint || _zuptDue(t, dop);
      _record(
        anchor: true,
        chainBreak: true,
        dt: 0.0,
        predX: null,
        predY: null,
        zupt: zupt,
        dop: (dop != null && _dopplerTrusted) ? dop * _dopplerScale : null,
        chord: null,
      );
      return 0.0;
    }
    // The gap closed inside the gap window, so the filter integrates it: drop the buffer.
    _pendingStepM = 0.0;
    final dt = t - prevT;
    _t = t;
    final x = _x!;
    final y = _y!;
    x.predict(dt);
    y.predict(dt);
    final predX = x.state();
    final predY = y.state();

    // 1. Innovation gate on the predicted position.
    final yx = zx - x.p;
    final yy = zy - y.p;
    final ax = x.a;
    final ay = y.a;
    final nis = yx * yx / (ax + r) + yy * yy / (ay + r);
    var chainBreak = false;
    final accepted = nis <= gateChi2;
    if (accepted) {
      _rejectStreak = 0;
      x.updatePos(zx, r);
      y.updatePos(zy, r);
      // 2. Adaptive R: covariance matching, sample clamped, EMA, bounded.
      var sample = ((yx * yx - ax) + (yy * yy - ay)) / (2.0 * rStated);
      sample = math.min(math.max(sample, 0.0), rScaleMax);
      final ema = (1.0 - rScaleAlpha) * _rScale + rScaleAlpha * sample;
      _rScale = math.min(math.max(ema, rScaleMin), rScaleMax);
    } else {
      _rejectedFixes += 1;
      _rejectStreak += 1;
      if (_rejectStreak > gateMaxRejects) {
        x.resetPos(zx, r);
        y.resetPos(zy, r);
        _rejectStreak = 0;
        _xcLastX = zx;
        _xcLastY = zy;
        _xcLastT = t;
        _setDsLast(zx, zy, t, dop, bearingDeg);
        chainBreak = true;
      }
    }

    // 3. Zero-velocity update (pedometer, or the caller's stop hint).
    var pedZupt = _zuptDue(t, dop);
    double? chord;
    if (pedZupt) {
      final anchorX = _zuptAnchorX;
      final anchorY = _zuptAnchorY;
      if (anchorX == null || anchorY == null) {
        _zuptAnchorX = x.p;
        _zuptAnchorY = y.p;
      } else {
        final moved = _hypot(x.p - anchorX, y.p - anchorY);
        if (moved > zuptReleaseM) {
          // The pedometer stalled while the runner moved: stop trusting it until it counts again.
          _zuptReleased = true;
          _zuptAnchorX = null;
          _zuptAnchorY = null;
          pedZupt = false;
          chord = moved;
        }
      }
    } else {
      _zuptAnchorX = null;
      _zuptAnchorY = null;
    }
    final zupt = stoppedHint || pedZupt;
    if (zupt) {
      chord = null;
      _zuptFixes += 1;
      const rz = zuptVelSigmaMps * zuptVelSigmaMps;
      x.updateVel(0.0, rz);
      y.updateVel(0.0, rz);
    }

    // 4. Doppler-vs-position cross-check, on the raw fixes' displacement
    //    projected on the Doppler bearing.
    if (accepted) {
      final lx = _xcLastX!;
      final ly = _xcLastY!;
      final span = t - _xcLastT!;
      if (dop != null &&
          !zupt &&
          _valid(bearingDeg) &&
          dop >= posOnlyStationarySpeedMps &&
          span <= xcheckMaxSpanS) {
        final b = _radians(bearingDeg!);
        final u = ((zx - lx) * math.sin(b) + (zy - ly) * math.cos(b)) / span;
        if (_xcTime == 0.0) {
          _xcDoppler = dop;
          _xcPos = dop;
        } else {
          final alpha = math.min(1.0, span / xcheckTauS);
          _xcDoppler += alpha * (dop - _xcDoppler);
          _xcPos += alpha * (u - _xcPos);
        }
        _xcTime += span;
        if (_xcTime >= xcheckMinS) {
          final diff = (_xcDoppler - _xcPos).abs();
          final refSpeed = _xcPos.abs();
          final flip = _dopplerTrusted
              ? diff > math.max(xcheckEnterAbsMps, xcheckEnterRel * refSpeed)
              : diff < math.max(xcheckExitAbsMps, xcheckExitRel * refSpeed);
          _xcPersistS = flip ? _xcPersistS + span : 0.0;
          if (_xcPersistS >= xcheckPersistS) {
            _dopplerTrusted = !_dopplerTrusted;
            _xcPersistS = 0.0;
          }
        }
      }
      _xcLastX = zx;
      _xcLastY = zy;
      _xcLastT = t;

      // 4b. Doppler scale (v1.3): exponentially forgotten integrals of the
      //     fixes' displacement along the span's mean Doppler bearing and of
      //     the trapezoid Doppler distance over the same span.
      final ldop = _dsLastDop;
      final lb = _dsLastBearing;
      final dsSpan = t - _dsLastT!;
      final turn = (_valid(bearingDeg) && _valid(lb))
          ? (bearingDeg! - lb!).abs() % 360.0
          : null;
      if (!zupt &&
          dop != null &&
          ldop != null &&
          turn != null &&
          dop >= dscaleMinSpeedMps &&
          ldop >= dscaleMinSpeedMps &&
          dsSpan <= xcheckMaxSpanS &&
          math.min(turn, 360.0 - turn) <= dscaleMaxTurnDeg) {
        final b0 = _radians(lb!);
        final b1 = _radians(bearingDeg!);
        final ux = math.sin(b0) + math.sin(b1);
        final uy = math.cos(b0) + math.cos(b1);
        final n = _hypot(ux, uy);
        final w = math.exp(-dsSpan / dscaleTauS);
        _dsPos =
            w * _dsPos + ((zx - _dsLastX!) * ux + (zy - _dsLastY!) * uy) / n;
        _dsDop = w * _dsDop + 0.5 * (ldop + dop) * dsSpan;
        _dsTime += dsSpan;
        if (_dsTime >= dscaleMinS && _dsDop > 0.0) {
          _dopplerScale = math.min(
            math.max(_dsPos / _dsDop, dscaleMin),
            dscaleMax,
          );
        }
      }
      _setDsLast(zx, zy, t, dop, bearingDeg);
    }

    // 5. Doppler velocity update.
    final useDop = (doppler != null && _dopplerTrusted)
        ? doppler.s * _dopplerScale
        : null;
    if (useDop != null &&
        !zupt &&
        _valid(bearingDeg) &&
        useDop >= stationarySpeedMps) {
      final rv = _sq(math.max(doppler!.sa, minSpeedSigmaMps));
      final b = _radians(bearingDeg!);
      x.updateVel(useDop * math.sin(b), rv);
      y.updateVel(useDop * math.cos(b), rv);
    }

    // 6. Credit.
    final double inc;
    if (chord != null) {
      inc = chord;
    } else if (zupt) {
      inc = 0.0;
    } else {
      final double speed;
      final double floor;
      if (useDop != null) {
        speed = useDop;
        floor = stationarySpeedMps;
      } else {
        speed = _hypot(x.v, y.v);
        floor = posOnlyStationarySpeedMps;
      }
      inc = speed < floor ? 0.0 : math.min(speed, maxSpeedMps) * dt;
    }
    _gpsDistanceM += inc;
    _winM += inc;
    _record(
      anchor: false,
      chainBreak: chainBreak,
      dt: dt,
      predX: predX,
      predY: predY,
      zupt: zupt,
      dop: useDop,
      chord: chord,
    );
    return inc;
  }

  /// Cumulative pedometer count. Learns a stride while GPS is good; buffers
  /// steps x stride while it is not (committed only if the gap exceeds the gap window).
  void addSteps(double t, int cumulativeSteps) {
    if (!_valid(t)) return;
    final prev = _lastSteps;
    final prevT = _lastStepT;
    _lastSteps = cumulativeSteps;
    _lastStepT = t;
    if (prev == null || cumulativeSteps < prev || prevT == null || t <= prevT) {
      return;
    }
    final d = cumulativeSteps - prev;
    if (d > 0) {
      _stepsSeen = true;
      _lastStepIncT = t;
      _zuptReleased = false;
    }
    final fixT = _t;
    if (fixT != null && t - fixT <= _freshFixS) {
      _winSteps += d;
      if (_winSteps >= strideWindowSteps) {
        final stride = _winM / _winSteps;
        if (minStrideM <= stride && stride <= maxStrideM) {
          final current = _strideM;
          _strideM = current == null
              ? stride
              : (1 - strideEmaAlpha) * current + strideEmaAlpha * stride;
        }
        _winSteps = 0;
        _winM = 0.0;
      }
      return;
    }
    _winSteps = 0;
    _winM = 0.0;
    final stride = _strideM;
    if (stride == null) return;
    _pendingStepM += math.min(d * stride, maxSpeedMps * (t - prevT));
  }

  /// End of run: commit buffered steps if the trailing gap exceeds the gap window.
  void finish(double t) {
    final fixT = _t;
    if (fixT != null && _valid(t) && t - fixT > _gapS) {
      _stepDistanceM += _pendingStepM;
    }
    _pendingStepM = 0.0;
  }

  /// Usable, debiased Doppler speed and its sigma, or null.
  static ({double s, double sa})? _dopplerSpeed(
    double? speedMps,
    double? speedAccuracyMps,
    double maxSpeedMps,
  ) {
    if (!(_valid(speedMps) && 0.0 <= speedMps! && speedMps <= maxSpeedMps)) {
      return null;
    }
    final reported = _valid(speedAccuracyMps) && speedAccuracyMps! > 0;
    final sa = reported ? speedAccuracyMps : defaultSpeedSigmaMps;
    if (sa > maxSpeedSigmaMps) return null;
    var s = speedMps;
    if (reported && s < debiasZeroMps) {
      final w = s <= debiasFullMps
          ? 1.0
          : (debiasZeroMps - s) / (debiasZeroMps - debiasFullMps);
      s = math.sqrt(math.max(0.0, s * s - w * sa * sa));
    }
    return (s: s, sa: sa);
  }

  static double _sq(double v) => v * v;

  // Python's math.hypot scales to avoid overflow; at running speeds the plain
  // form agrees far inside the 1e-3 m vector tolerance.
  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);
}

/// One input to [smoothDistance], in arrival order.
sealed class GpsEvent {
  const GpsEvent(this.t);

  final double t;
}

class GpsFixEvent extends GpsEvent {
  const GpsFixEvent({
    required double t,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.speedMps,
    this.speedAccuracyMps,
    this.bearingDeg,
  }) : super(t);

  final double lat;
  final double lng;
  final double? accuracyM;
  final double? speedMps;
  final double? speedAccuracyMps;
  final double? bearingDeg;
}

class GpsStepsEvent extends GpsEvent {
  const GpsStepsEvent({required double t, required this.count}) : super(t);

  final int count;
}

class GpsFinishEvent extends GpsEvent {
  const GpsFinishEvent({required double t}) : super(t);
}

/// What [smoothDistance] returns.
class SmoothedDistance {
  const SmoothedDistance({
    required this.distanceM,
    required this.gpsDistanceM,
    required this.stepDistanceM,
    required this.cumulativeM,
    required this.positions,
    required this.stoppedFixes,
  });

  final double distanceM;
  final double gpsDistanceM;
  final double stepDistanceM;

  /// Per event: smoothed GPS credit through it plus the step distance
  /// committed by then.
  final List<double> cumulativeM;

  /// Per event: the smoothed position of a fix the filter took, else null.
  final List<({double lat, double lng})?> positions;

  /// How many fixes post-hoc stop detection flagged.
  final int stoppedFixes;
}

/// Post-hoc stop flags for a track with no Doppler. [fixes]: (t, x, y) in
/// strictly increasing t. Fix j is stopped when both half-windows around it
/// hold >= [GpsDistanceEstimator.stopMinHalfFixes] fixes, the net speed
/// between the halves' mean positions is < [GpsDistanceEstimator.stopSpeedMps],
/// and the RMS distance of the whole window from its mean is <
/// [GpsDistanceEstimator.stopRadiusM].
List<bool> detectStops(
  List<({double t, double x, double y})> fixes, {
  double expectedIntervalS = 1.0,
}) {
  final half =
      GpsDistanceEstimator.stopHalfWindowS *
      GpsDistanceEstimator._intervalScale(expectedIntervalS);
  final n = fixes.length;
  final out = List<bool>.filled(n, false);
  var lo = 0;
  var hi = 0;
  for (var j = 0; j < n; j++) {
    final tj = fixes[j].t;
    while (fixes[lo].t < tj - half) {
      lo += 1;
    }
    while (hi + 1 < n && fixes[hi + 1].t <= tj + half) {
      hi += 1;
    }
    final na = j - lo;
    final nb = hi - j + 1;
    if (na < GpsDistanceEstimator.stopMinHalfFixes ||
        nb < GpsDistanceEstimator.stopMinHalfFixes) {
      continue;
    }
    var ta = 0.0, xa = 0.0, ya = 0.0;
    for (var k = lo; k < j; k++) {
      ta += fixes[k].t;
      xa += fixes[k].x;
      ya += fixes[k].y;
    }
    var tb = 0.0, xb = 0.0, yb = 0.0;
    for (var k = j; k <= hi; k++) {
      tb += fixes[k].t;
      xb += fixes[k].x;
      yb += fixes[k].y;
    }
    final net =
        GpsDistanceEstimator._hypot(xb / nb - xa / na, yb / nb - ya / na) /
        (tb / nb - ta / na);
    if (net >= GpsDistanceEstimator.stopSpeedMps) continue;
    final mx = (xa + xb) / (na + nb);
    final my = (ya + yb) / (na + nb);
    var ss = 0.0;
    for (var k = lo; k <= hi; k++) {
      final dx = fixes[k].x - mx;
      final dy = fixes[k].y - my;
      ss += dx * dx + dy * dy;
    }
    out[j] = math.sqrt(ss / (na + nb)) < GpsDistanceEstimator.stopRadiusM;
  }
  return out;
}

/// The saved / recomputed distance: the forward filter over every event, then
/// a backward (RTS) pass per unbroken chain, credited along the smoothed
/// velocities. A track with no Doppler at all first runs post-hoc stop
/// detection, whose verdicts reach the filter as `stoppedHint`.
SmoothedDistance smoothDistance(
  List<GpsEvent> events, {
  double maxSpeedMps = 10.0,
  double expectedIntervalS = 1.0,
  double? initialStrideM,
}) {
  bool valid(double? v) => v != null && v.isFinite;
  double rad(double d) => d * (math.pi / 180.0);
  const earthR = GpsDistanceEstimator.earthRadiusM;

  // Fixes exactly as the estimator would take them.
  final keptEvent = <int>[];
  final kept = <({double t, double x, double y})>[];
  double? lat0;
  double? lng0;
  double? lastT;
  var hasDoppler = false;
  for (var i = 0; i < events.length; i++) {
    final ev = events[i];
    if (ev is! GpsFixEvent) continue;
    if (!(valid(ev.t) && valid(ev.lat) && valid(ev.lng))) continue;
    lat0 ??= ev.lat;
    lng0 ??= ev.lng;
    if (lastT != null && ev.t <= lastT) continue;
    lastT = ev.t;
    if (valid(ev.speedMps)) hasDoppler = true;
    final x =
        rad(GpsDistanceEstimator._wrapLng(ev.lng - lng0)) *
        earthR *
        math.cos(rad(lat0));
    final y = rad(ev.lat - lat0) * earthR;
    keptEvent.add(i);
    kept.add((t: ev.t, x: x, y: y));
  }
  final hints = <int>{};
  if (!hasDoppler) {
    final flags = detectStops(kept, expectedIntervalS: expectedIntervalS);
    for (var j = 0; j < flags.length; j++) {
      if (flags[j]) hints.add(keptEvent[j]);
    }
  }

  final est = GpsDistanceEstimator._(
    maxSpeedMps: maxSpeedMps,
    expectedIntervalS: expectedIntervalS,
    initialStrideM: initialStrideM,
    record: true,
  );
  final recs = est._records!;
  final recEvent = <int>[];
  for (var i = 0; i < events.length; i++) {
    switch (events[i]) {
      case final GpsFixEvent ev:
        final n = recs.length;
        est.addFix(
          t: ev.t,
          lat: ev.lat,
          lng: ev.lng,
          accuracyM: ev.accuracyM,
          speedMps: ev.speedMps,
          speedAccuracyMps: ev.speedAccuracyMps,
          bearingDeg: ev.bearingDeg,
          stoppedHint: hints.contains(i),
        );
        if (recs.length > n) recEvent.add(i);
      case final GpsStepsEvent ev:
        est.addSteps(ev.t, ev.count);
      case final GpsFinishEvent ev:
        est.finish(ev.t);
    }
  }

  // Backward pass per unbroken chain (a gap re-anchor or a gate lock-out starts a new one).
  final smX = List<double>.filled(recs.length, 0);
  final smY = List<double>.filled(recs.length, 0);
  final smVx = List<double>.filled(recs.length, 0);
  final smVy = List<double>.filled(recs.length, 0);
  var s = 0;
  for (var k = 1; k <= recs.length; k++) {
    if (k == recs.length || recs[k].chainBreak) {
      _rts(recs, s, k - 1, true, smX, smVx);
      _rts(recs, s, k - 1, false, smY, smVy);
      s = k;
    }
  }

  // Credit along the smoothed velocities: trapezoid per interval, gap re-anchors not credited.
  final effs = List<double>.filled(recs.length, 0);
  for (var k = 0; k < recs.length; k++) {
    final r = recs[k];
    if (r.zupt) continue;
    final double speed;
    final double floor;
    final dop = r.dop;
    if (dop != null) {
      speed = dop;
      floor = GpsDistanceEstimator.stationarySpeedMps;
    } else {
      speed = GpsDistanceEstimator._hypot(smVx[k], smVy[k]);
      floor = GpsDistanceEstimator.posOnlyStationarySpeedMps;
    }
    effs[k] = speed < floor ? 0.0 : math.min(speed, maxSpeedMps);
  }
  final credit = List<double>.filled(recs.length, 0);
  for (var k = 0; k < recs.length; k++) {
    final r = recs[k];
    if (r.anchor) continue;
    credit[k] = r.chord ?? 0.5 * (effs[k - 1] + effs[k]) * r.dt;
  }

  final byEvent = <int, int>{
    for (var k = 0; k < recEvent.length; k++) recEvent[k]: k,
  };
  final cumulative = List<double>.filled(events.length, 0);
  final positions = List<({double lat, double lng})?>.filled(
    events.length,
    null,
  );
  var gps = 0.0;
  var stepM = 0.0;
  for (var i = 0; i < events.length; i++) {
    final k = byEvent[i];
    if (k != null) {
      gps += credit[k];
      stepM = recs[k].stepDistanceM;
      positions[i] = est.unproject(smX[k], smY[k]);
    } else if (events[i] is GpsFinishEvent) {
      stepM = est.stepDistanceM;
    }
    cumulative[i] = gps + stepM;
  }
  return SmoothedDistance(
    distanceM: gps + est.stepDistanceM,
    gpsDistanceM: gps,
    stepDistanceM: est.stepDistanceM,
    cumulativeM: cumulative,
    positions: positions,
    stoppedFixes: hints.length,
  );
}

/// RTS backward pass over one unbroken chain recs[s..e] for one axis, writing
/// the smoothed position and velocity into [outP] / [outV] at the same index.
void _rts(
  List<_FixRecord> recs,
  int s,
  int e,
  bool xAxis,
  List<double> outP,
  List<double> outV,
) {
  final last = xAxis ? recs[e].x : recs[e].y;
  outP[e] = last.p;
  outV[e] = last.v;
  for (var k = e - 1; k >= s; k--) {
    final f = xAxis ? recs[k].x : recs[k].y;
    final nxt = recs[k + 1];
    final dt = nxt.dt;
    final pr = xAxis ? nxt.predX! : nxt.predY!;
    final a = f.a, b = f.b, c = f.c;
    final bigA = pr.a, bigB = pr.b, bigC = pr.c;
    final det = bigA * bigC - bigB * bigB;
    final g00 = ((a + dt * b) * bigC - b * bigB) / det;
    final g01 = (b * bigA - (a + dt * b) * bigB) / det;
    final g10 = ((b + dt * c) * bigC - c * bigB) / det;
    final g11 = (c * bigA - (b + dt * c) * bigB) / det;
    final dp = outP[k + 1] - pr.p;
    final dv = outV[k + 1] - pr.v;
    outP[k] = f.p + g00 * dp + g01 * dv;
    outV[k] = f.v + g10 * dp + g11 * dv;
  }
}

typedef _AxisState = ({double p, double v, double a, double b, double c});

/// What the backward pass needs from each fix the filter took.
class _FixRecord {
  const _FixRecord({
    required this.anchor,
    required this.chainBreak,
    required this.dt,
    required this.predX,
    required this.predY,
    required this.x,
    required this.y,
    required this.zupt,
    required this.dop,
    required this.chord,
    required this.stepDistanceM,
  });

  final bool anchor;
  final bool chainBreak;
  final double dt;
  final _AxisState? predX;
  final _AxisState? predY;
  final _AxisState x;
  final _AxisState y;
  final bool zupt;
  final double? dop;
  final double? chord;
  final double stepDistanceM;
}

/// 1-D constant-velocity Kalman filter: state [p, v], covariance
/// [[a, b], [b, c]].
class _Axis {
  _Axis(this.p, double posVar)
    : a = posVar,
      b = 0.0,
      c = GpsDistanceEstimator.initVelVar;

  double p;
  double v = 0.0;
  double a;
  double b;
  double c;

  void predict(double dt) {
    const q = GpsDistanceEstimator.qAccel;
    p += v * dt;
    final na = a + 2.0 * dt * b + dt * dt * c + q * math.pow(dt, 3) / 3.0;
    final nb = b + dt * c + q * dt * dt / 2.0;
    final nc = c + q * dt;
    a = na;
    b = nb;
    c = nc;
  }

  void updatePos(double z, double r) {
    final s = a + r;
    final k0 = a / s;
    final k1 = b / s;
    final y = z - p;
    p += k0 * y;
    v += k1 * y;
    final oa = a, ob = b, oc = c;
    a = (1 - k0) * oa;
    b = (1 - k0) * ob;
    c = oc - k1 * ob;
  }

  void updateVel(double z, double r) {
    final s = c + r;
    final k0 = b / s;
    final k1 = c / s;
    final y = z - v;
    p += k0 * y;
    v += k1 * y;
    final oa = a, ob = b, oc = c;
    a = oa - k0 * ob;
    b = (1 - k1) * ob;
    c = (1 - k1) * oc;
  }

  /// Lock-out re-anchor: position jumps to z, velocity is kept.
  void resetPos(double z, double r) {
    p = z;
    a = r;
    b = 0.0;
  }

  _AxisState state() => (p: p, v: v, a: a, b: b, c: c);
}
