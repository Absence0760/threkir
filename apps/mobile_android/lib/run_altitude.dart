import 'package:core_models/core_models.dart';

import 'route_simplify.dart';

/// The band phone GPS altitude is gated on when no barometer recorded the run.
/// GPS vertical error runs at roughly 1.5x the horizontal and wanders over
/// minutes rather than flickering per fix, and under tree cover the low
/// satellites that fix the vertical drop out first, so a 10-20 m vertical
/// error is routine. The 3 m route band integrates that wander as climb; 10 m
/// is the band Strava applies to devices without a barometer, and it costs
/// only rollers under 10 m, which GPS altitude cannot resolve anyway.
const double kElevationGainGpsMinDeltaM = 10;

/// Which altitude a recorded run's climb and elevation profile are read from,
/// and the noise band the climb is gated on. Twin of `runAltitude` in
/// `apps/web/src/lib/runs/run_altitude.ts`; keep in lockstep
/// (docs/architecture/parity_pairs.md).
///
/// Three cases, in order:
///
/// 1. Any point carries [Waypoint.baroElevationMetres] — the phone barometer,
///    anchored to GPS altitude by the recorder (docs/features/run_recording.md
///    § Barometric altitude). The run is read off that series alone at the
///    route band [kElevationGainMinDeltaM]: a barometer resolves well under a
///    metre, so the 3 m band only has to absorb the slow anchor correction. A
///    point without one (before the anchor levelled, or a sensor stall) is a
///    dropout the gain rule carries across; GPS altitude is never spliced in,
///    because the two series sit on different error budgets and a splice
///    would count the step between them as climb.
/// 2. A phone-recorded run ([RunSource.app]) without one — GPS altitude from a
///    phone with no barometer, or a run recorded before the barometer was
///    read. Gated at [kElevationGainGpsMinDeltaM].
/// 3. Anything else — an import or a watch, whose altitude may already be
///    barometric (Garmin, Apple Watch, the custom watch) and whose device we
///    cannot see from here — keeps the route band, exactly as before.
({List<Waypoint> track, double minDeltaM, bool barometric}) runAltitude(
  List<Waypoint> track,
  RunSource? source,
) {
  if (hasBarometricAltitude(track)) {
    return (
      track: [for (final w in track) _withBarometricElevation(w)],
      minDeltaM: kElevationGainMinDeltaM,
      barometric: true,
    );
  }
  return (
    track: track,
    minDeltaM: source == RunSource.app
        ? kElevationGainGpsMinDeltaM
        : kElevationGainMinDeltaM,
    barometric: false,
  );
}

/// True when any point carries a finite barometric altitude.
bool hasBarometricAltitude(List<Waypoint> track) =>
    track.any((w) => w.baroElevationMetres?.isFinite ?? false);

/// The climb of a recorded run, over the series and band [runAltitude] picks.
double computeRunElevationGain(List<Waypoint> track, RunSource? source) {
  final alt = runAltitude(track, source);
  return computeElevationGain(alt.track, minDeltaM: alt.minDeltaM);
}

/// The descent of a recorded run, read the same way as
/// [computeRunElevationGain]. Mobile-only, like [computeElevationLoss].
double computeRunElevationLoss(List<Waypoint> track, RunSource? source) {
  final alt = runAltitude(track, source);
  return computeElevationLoss(alt.track, minDeltaM: alt.minDeltaM);
}

/// Streaming [computeRunElevationGain] for the live recording screen, whose
/// track is always phone-recorded and grows one fix at a time. It cannot know
/// up front whether a barometric altitude will arrive, so it keeps both
/// readings and answers with the barometric one from the first point that
/// carries it — which is the batch rule run to completion, so the live figure
/// and the finished run's agree.
class RunElevationGainAccumulator {
  final ElevationGainAccumulator _gps = ElevationGainAccumulator(
    minDeltaM: kElevationGainGpsMinDeltaM,
  );
  final ElevationGainAccumulator _baro = ElevationGainAccumulator();
  bool _sawBaro = false;

  double get gainMetres => _sawBaro ? _baro.gainMetres : _gps.gainMetres;

  void reset() {
    _gps.reset();
    _baro.reset();
    _sawBaro = false;
  }

  void add(Waypoint point) {
    _gps.add(point);
    final baro = point.baroElevationMetres;
    if (baro != null && baro.isFinite) {
      _sawBaro = true;
      _baro.addElevation(baro);
    }
  }

  void addAll(Iterable<Waypoint> points) {
    for (final p in points) {
      add(p);
    }
  }
}

Waypoint _withBarometricElevation(Waypoint w) {
  final baro = w.baroElevationMetres;
  return Waypoint(
    lat: w.lat,
    lng: w.lng,
    elevationMetres: (baro?.isFinite ?? false) ? baro : null,
    timestamp: w.timestamp,
    bpm: w.bpm,
    accuracyMetres: w.accuracyMetres,
    speedMps: w.speedMps,
    speedAccuracyMps: w.speedAccuracyMps,
    bearingDeg: w.bearingDeg,
    smoothedLat: w.smoothedLat,
    smoothedLng: w.smoothedLng,
    baroElevationMetres: baro,
  );
}
