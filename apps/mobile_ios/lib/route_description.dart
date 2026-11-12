import 'dart:math' as math;

import 'package:core_models/core_models.dart' show DistanceUnit, kMetresPerMile;

import 'distance_bands.dart' show bandForDistance;
import 'run_stats.dart' show haversineMetres;

/// Templated route describer — turns a route's stored stats into a short,
/// human-readable description without calling any model. This is the
/// always-works L1 baseline for the "Describe this route" affordance: it
/// runs offline, costs nothing, and is the fallback the LLM-enhancement
/// path (a Pro perk) degrades to whenever the model call fails, refuses,
/// the user isn't Pro, or the endpoint is unconfigured.
///
/// The helper is deliberately unit-agnostic and locale-agnostic: it emits
/// a structured [RouteDescriptionParts] (named facts) rather than a baked
/// English sentence, so the render layer can format distance in km/mi per
/// the viewer's preference and translate each clause. [assembleEnglish]
/// is the canonical English assembler used by the LLM prompt and tests.
///
/// Twin of `apps/web/src/lib/routes/route_description.ts` — keep the
/// classification thresholds, clause set, ordering, edge cases, and test
/// count in lockstep.

enum RouteShape { loop, outAndBack, pointToPoint }

/// Elevation character bucketed from total gain over distance (m/km).
enum ElevationProfile { flat, rolling, hilly, mountainous }

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

class RouteDescriptionInput {
  final String name;
  final double distanceM;
  final double? elevationM;
  final String? surface;
  final LatLng? start;
  final LatLng? end;
  const RouteDescriptionInput({
    required this.name,
    required this.distanceM,
    this.elevationM,
    this.surface,
    this.start,
    this.end,
  });
}

class ElevationResult {
  final ElevationProfile profile;
  final int gainPerKm;
  const ElevationResult(this.profile, this.gainPerKm);
}

class RouteDescriptionParts {
  /// Named race-distance band ('5k', '10k', …) or null if between bands.
  final String? band;
  final double distanceM;
  final String? surface;
  final double elevationM;
  final ElevationProfile elevation;
  final int gainPerKm;
  final RouteShape shape;
  const RouteDescriptionParts({
    required this.band,
    required this.distanceM,
    required this.surface,
    required this.elevationM,
    required this.elevation,
    required this.gainPerKm,
    required this.shape,
  });
}

/// Two endpoints within this distance are treated as the same point — the
/// route returns to where it started, so it's a loop. Matches the
/// route-loop builder's near-point threshold.
const double loopCloseM = 75;

/// m/km thresholds for the elevation buckets. Inclusive lower bound.
const int elevationRollingThreshold = 10;
const int elevationHillyThreshold = 30;
const int elevationMountainousThreshold = 70;

/// Bucket total gain (m) over distance into a coarse elevation character.
ElevationResult elevationProfile(double distanceM, double elevationM) {
  if (distanceM <= 0 || elevationM <= 0) {
    return const ElevationResult(ElevationProfile.flat, 0);
  }
  final gainPerKm = (elevationM / distanceM * 1000).round();
  var profile = ElevationProfile.flat;
  if (gainPerKm >= elevationMountainousThreshold) {
    profile = ElevationProfile.mountainous;
  } else if (gainPerKm >= elevationHillyThreshold) {
    profile = ElevationProfile.hilly;
  } else if (gainPerKm >= elevationRollingThreshold) {
    profile = ElevationProfile.rolling;
  }
  return ElevationResult(profile, gainPerKm);
}

/// Infer route shape from endpoints. Without endpoints we can't tell, so
/// default to [RouteShape.pointToPoint] (the most conservative claim).
/// When start ≈ end the route closes on itself; report [RouteShape.loop].
RouteShape routeShape(RouteDescriptionInput input) {
  final start = input.start;
  final end = input.end;
  if (start == null || end == null) return RouteShape.pointToPoint;
  return haversineMetres(start.lat, start.lng, end.lat, end.lng) <= loopCloseM
      ? RouteShape.loop
      : RouteShape.pointToPoint;
}

/// Compute the structured facts the UI + LLM prompt build on.
RouteDescriptionParts describeRoute(RouteDescriptionInput input) {
  final distanceM =
      input.distanceM.isFinite ? math.max(0.0, input.distanceM) : 0.0;
  final elevationM = (input.elevationM != null && input.elevationM!.isFinite)
      ? math.max(0.0, input.elevationM!)
      : 0.0;
  final elev = elevationProfile(distanceM, elevationM);
  final band = bandForDistance(distanceM);
  return RouteDescriptionParts(
    band: band?.key,
    distanceM: distanceM,
    surface: input.surface,
    elevationM: elevationM,
    elevation: elev.profile,
    gainPerKm: elev.gainPerKm,
    shape: routeShape(input),
  );
}

const _shapeWord = <RouteShape, String>{
  RouteShape.loop: 'loop',
  RouteShape.outAndBack: 'out-and-back',
  RouteShape.pointToPoint: 'point-to-point',
};

const _surfaceWord = <String, String>{
  'road': 'road',
  'trail': 'trail',
  'mixed': 'mixed-surface',
};

const _elevationWord = <ElevationProfile, String>{
  ElevationProfile.flat: 'flat',
  ElevationProfile.rolling: 'gently rolling',
  ElevationProfile.hilly: 'hilly',
  ElevationProfile.mountainous: 'mountainous',
};

const double _metresPerFoot = 0.3048;

/// Gain per mile in feet, from the unrounded totals rather than `gainPerKm`.
int _feetPerMile(RouteDescriptionParts parts) {
  if (parts.distanceM <= 0) return 0;
  return (parts.elevationM / _metresPerFoot / (parts.distanceM / kMetresPerMile))
      .round();
}

/// Canonical English assembler. Used to seed the LLM prompt (plain prose
/// the model enhances) and as the literal fallback string in tests. The
/// route-detail UI does NOT call this — it builds a localised, unit-aware
/// sentence from [RouteDescriptionParts]. English-only by contract, but in
/// the viewer's [unit]: a miles runner's prompt states miles and feet, so the
/// model is never handed kilometres to repeat back to them.
String assembleEnglish(RouteDescriptionParts parts, String name,
    [DistanceUnit unit = DistanceUnit.km]) {
  final mi = unit == DistanceUnit.mi;
  final perUnitM = mi ? kMetresPerMile : 1000.0;
  final distance = (parts.distanceM / perUnitM)
      .toStringAsFixed(parts.distanceM >= perUnitM ? 1 : 2);
  final shape = _shapeWord[parts.shape];
  final surface =
      parts.surface != null ? '${_surfaceWord[parts.surface] ?? parts.surface} ' : '';
  final clauses = <String>[];
  clauses.add('$name is a $distance ${unit.name} $surface${shape} route');
  if (parts.elevationM > 0) {
    final climb = mi
        ? '${(parts.elevationM / _metresPerFoot).round()} ft of climbing (${_elevationWord[parts.elevation]}, about ${_feetPerMile(parts)} ft per mile)'
        : '${parts.elevationM.round()} m of climbing (${_elevationWord[parts.elevation]}, about ${parts.gainPerKm} m per km)';
    clauses.add('with $climb');
  } else {
    clauses.add('with little to no elevation change');
  }
  return '${clauses.join(' ')}.';
}

/// The text the route-detail screen shows once the enhancement endpoint has
/// answered. Only a model-written paragraph ([source] `'ai'`) replaces the
/// viewer's localised template: the server's own fallback is
/// [assembleEnglish], which is English by contract, so taking it would hand a
/// non-English viewer an English sentence in place of the one already
/// rendered in their language.
String shownDescription(
  String localised, {
  required String description,
  required String source,
}) =>
    source == 'ai' ? description : localised;
