import 'dart:math' as math;

/// Levels a phone barometer's relative altitude against GPS altitude.
///
/// A barometer resolves altitude CHANGE to well under a metre, but its level
/// is arbitrary (iOS `CMAltimeter` starts at 0; Android's pressure-to-altitude
/// conversion assumes a standard sea-level pressure) and drifts with the
/// weather. GPS altitude has the opposite profile: right on average, wrong by
/// metres to tens of metres fix to fix, and worst under tree cover. The fused
/// altitude is `barometer + offset`, where the offset is a slow average of
/// `gps - barometer`, so the shape is the barometer's and the level follows
/// GPS (docs/features/run_recording.md § Barometric altitude).
///
/// The offset is the plain mean of every sample until [timeConstantS] of
/// samples have arrived, then an exponential average with that time
/// constant. The mean makes the first minutes as steady as they can be; the
/// exponential lets the level follow weather drift (a front moves sea-level
/// pressure ~1 hPa, ~8 m of altitude, per hour) while GPS error that wanders
/// over a few minutes is averaged away. Any change in the offset reaches the
/// fused altitude one for one, which is why it has to be this slow.
///
/// Times are seconds on one monotonic clock the caller owns; only their
/// differences matter.
class BaroAltitudeAnchor {
  BaroAltitudeAnchor({
    this.timeConstantS = defaultTimeConstantS,
    this.maxGpsVerticalAccuracyM = defaultMaxGpsVerticalAccuracyM,
    this.baroStaleAfterS = defaultBaroStaleAfterS,
  });

  /// Ten minutes: about 8x shorter than the hour over which weather moves
  /// pressure by a metre-scale amount, about 10x longer than the minutes over
  /// which GPS altitude error stays correlated.
  static const double defaultTimeConstantS = 600;

  /// A GPS altitude the platform itself rates worse than this is not averaged
  /// in. Under canopy the vertical estimate degrades first; leaving it out
  /// keeps one bad stretch from walking the level.
  static const double defaultMaxGpsVerticalAccuracyM = 25;

  /// A barometer reading older than this is not a reading for "now": no fused
  /// altitude is stamped and no GPS sample is paired with it. Sensors report
  /// at 1 Hz or faster, so this only trips when the sensor has stalled.
  static const double defaultBaroStaleAfterS = 5;

  final double timeConstantS;
  final double maxGpsVerticalAccuracyM;
  final double baroStaleAfterS;

  double? _baroM;
  double? _baroT;
  double? _offsetM;
  double? _lastGpsT;
  int _gpsSamples = 0;

  /// Whether a GPS altitude has levelled the barometer yet.
  bool get anchored => _offsetM != null;

  /// The current `gps - barometer` offset, metres, or null before any GPS.
  double? get offsetM => _offsetM;

  /// A barometric altitude reading, metres on the sensor's own datum.
  void addBarometer(double tS, double relativeAltitudeM) {
    if (!tS.isFinite || !relativeAltitudeM.isFinite) return;
    _baroM = relativeAltitudeM;
    _baroT = tS;
  }

  /// A GPS altitude with the platform's vertical accuracy (1-sigma metres).
  /// An unrated altitude (accuracy zero, negative or non-finite) is ignored:
  /// that is how the platforms report "no vertical fix".
  void addGps(double tS, double altitudeM, double verticalAccuracyM) {
    if (!tS.isFinite || !altitudeM.isFinite) return;
    if (!verticalAccuracyM.isFinite ||
        verticalAccuracyM <= 0 ||
        verticalAccuracyM > maxGpsVerticalAccuracyM) {
      return;
    }
    final baro = _freshBaro(tS);
    if (baro == null) return;
    final sample = altitudeM - baro;
    _gpsSamples++;
    final offset = _offsetM;
    final lastT = _lastGpsT;
    _lastGpsT = tS;
    if (offset == null || lastT == null) {
      _offsetM = sample;
      return;
    }
    final dt = math.max(0.0, tS - lastT);
    final alpha = math.max(1 / _gpsSamples, 1 - math.exp(-dt / timeConstantS));
    _offsetM = offset + alpha * (sample - offset);
  }

  /// The fused altitude at [tS], metres, or null before the first GPS
  /// altitude or while the barometer is stale.
  double? altitudeAt(double tS) {
    final baro = _freshBaro(tS);
    final offset = _offsetM;
    if (baro == null || offset == null) return null;
    return baro + offset;
  }

  double? _freshBaro(double tS) {
    final t = _baroT;
    if (t == null || (tS - t).abs() > baroStaleAfterS) return null;
    return _baroM;
  }
}
