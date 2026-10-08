import 'dart:math' as math;

/// GPS distance estimator, spec v1.1 — a port of
/// `scripts/gps_distance/reference.py`, which is the spec. See
/// `docs/features/gps_distance.md`. Every operation mirrors the reference so
/// `fixtures/gps_distance_vectors.json` replays to 1e-3 m; do not tune a
/// constant here without changing the reference and every other port.
class GpsDistanceEstimator {
  GpsDistanceEstimator({
    this.maxSpeedMps = 10.0,
    double expectedIntervalS = 1.0,
    double? initialStrideM,
  })  : _gapS = gapS * _intervalScale(expectedIntervalS),
        _freshFixS = freshFixS * _intervalScale(expectedIntervalS),
        _strideM = (_valid(initialStrideM) &&
                minStrideM <= initialStrideM! &&
                initialStrideM <= maxStrideM)
            ? initialStrideM
            : null;

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

  double get distanceM => _gpsDistanceM + _stepDistanceM;
  double get gpsDistanceM => _gpsDistanceM;
  double get stepDistanceM => _stepDistanceM;
  double? get strideM => _strideM;

  static bool _valid(double? x) => x != null && x.isFinite;

  static double _intervalScale(double it) =>
      (_valid(it) && it > 1.0) ? it : 1.0;

  static double _radians(double deg) => deg * (math.pi / 180.0);

  /// [t] is seconds on a clock monotonic within the run. Returns the metres
  /// credited by this fix.
  double addFix({
    required double t,
    required double lat,
    required double lng,
    double? accuracyM,
    double? speedMps,
    double? speedAccuracyMps,
    double? bearingDeg,
  }) {
    if (!(_valid(t) && _valid(lat) && _valid(lng))) return 0.0;
    if (_lat0 == null) {
      _lat0 = lat;
      _lng0 = lng;
    }
    final zx = _radians(lng - _lng0!) *
        earthRadiusM *
        math.cos(_radians(_lat0!));
    final zy = _radians(lat - _lat0!) * earthRadiusM;
    final sigma = (_valid(accuracyM) && accuracyM! > 0) ? accuracyM : minPosSigmaM;
    final r = math.pow(math.max(sigma, minPosSigmaM), 2).toDouble();
    final prevT = _t;
    if (prevT != null && t <= prevT) return 0.0;
    if (prevT == null || t - prevT > _gapS) {
      if (prevT != null) _stepDistanceM += _pendingStepM;
      _pendingStepM = 0.0;
      _x = _Axis(zx, r);
      _y = _Axis(zy, r);
      _t = t;
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
    x.updatePos(zx, r);
    y.updatePos(zy, r);

    double? doppler;
    if (_valid(speedMps) && 0.0 <= speedMps! && speedMps <= maxSpeedMps) {
      final sa = (_valid(speedAccuracyMps) && speedAccuracyMps! > 0)
          ? speedAccuracyMps
          : defaultSpeedSigmaMps;
      if (sa <= maxSpeedSigmaMps) {
        doppler = speedMps;
        if (_valid(bearingDeg) && speedMps >= stationarySpeedMps) {
          final rv = math.pow(math.max(sa, minSpeedSigmaMps), 2).toDouble();
          final b = _radians(bearingDeg!);
          x.updateVel(speedMps * math.sin(b), rv);
          y.updateVel(speedMps * math.cos(b), rv);
        }
      }
    }

    final double speed;
    final double floor;
    if (doppler != null) {
      speed = doppler;
      floor = stationarySpeedMps;
    } else {
      speed = _hypot(x.v, y.v);
      floor = posOnlyStationarySpeedMps;
    }
    if (speed < floor) return 0.0;
    final inc = math.min(speed, maxSpeedMps) * dt;
    _gpsDistanceM += inc;
    _winM += inc;
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

  // Python's math.hypot scales to avoid overflow; at running speeds the plain
  // form agrees far inside the 1e-3 m vector tolerance.
  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);
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
}
