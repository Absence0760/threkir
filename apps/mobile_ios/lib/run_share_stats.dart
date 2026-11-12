import 'package:core_models/core_models.dart';

import 'l10n/gen/app_localizations.dart';
import 'preferences.dart';
import 'privacy.dart';
import 'run_altitude.dart';
import 'run_stats.dart';

/// The part of [run]'s track every share image draws: the stored track with
/// its leading and trailing fixes inside any of the owner's [zones] trimmed, by
/// the rule `clip_track_for_user` applies before a non-owner is served the same
/// run (raw OR smoothed position in a zone, interior passes kept). Always
/// applied when the owner has zones, with no opt-out: the PNG leaves the device
/// and is posted where anyone can read it, so it must withhold exactly what the
/// public run page withholds. Drawn from [trackLine]: an off-track fix is
/// distance input the recorder stored for the server replay, and the public
/// run page never serves one either.
List<Waypoint> runShareCardTrack(Run run, List<PrivacyZone> zones) =>
    clipPointsToZones<Waypoint>(
      trackLine(run.track),
      zones,
      latOf: (w) => w.lat,
      lngOf: (w) => w.lng,
      smoothedLatOf: (w) => w.smoothedLat,
      smoothedLngOf: (w) => w.smoothedLng,
    );

/// Whether the share card for [run] draws a basemap at all, and therefore
/// whether a capture has any tiles to wait for. A clipped track that short
/// renders the activity glyph instead.
bool runShareCardHasMap(Run run, List<PrivacyZone> zones) =>
    runShareCardTrack(run, zones).length >= 2;

/// The moving time every share image prints: [movingTimeOf] the stored track
/// to the nearest second, or the elapsed duration when there is no track to
/// measure it from. Rounded rather than truncated, as web's
/// `movingTimeSeconds` is, so a track stamped to the millisecond prints the
/// same seconds on both platforms.
Duration runShareMovingTime(Run run) {
  if (run.track.length < 2) return run.duration;
  final seconds = (movingTimeOf(run.track).inMilliseconds / 1000).round();
  if (seconds == 0) return run.duration;
  return Duration(seconds: seconds);
}

/// Seconds per km over [movingTime], or null when the run is too short to
/// carry a pace.
double? runShareMovingPace(Run run, Duration movingTime) {
  if (run.distanceMetres < 10) return null;
  final seconds = movingTime.inSeconds;
  if (seconds < 1) return null;
  return seconds / (run.distanceMetres / 1000);
}

/// `h:mm:ss`, or `mm:ss` under an hour.
String formatShareDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// A number a share image can print. [pace] prints as speed for an activity
/// measured in speed (a ride), so a runner never has to pick between them.
enum RunShareStatKind { distance, pace, time, climb, heartRate }

/// One headline stat as the share images print it.
typedef RunShareStat = ({
  RunShareStatKind kind,
  String label,
  String value,
  String? unit,
});

/// The climb a share image prints for [run], or null when it has none worth
/// printing: no track, or under a metre of gain. The shared helper, so the
/// number matches run detail and save-as-route.
double? runShareClimbMetres(Run run) {
  if (run.track.length < 2) return null;
  final gain = computeRunElevationGain(run.track, run.source);
  return gain >= 1 ? gain : null;
}

/// The run's average heart rate, or null when it was not measured. A
/// suppressed or absent average is absent, never zero.
int? runShareAvgBpm(Run run) {
  final v = run.metadata?[MetadataKeys.avgBpm];
  final bpm = v is num ? v.round() : null;
  return bpm != null && bpm > 0 ? bpm : null;
}

/// The kinds [run] actually has a number for, in display order. Distance,
/// pace and time always; climb and heart rate only when measured, so a chip
/// for a number the run cannot print is never offered.
List<RunShareStatKind> availableShareStats(Run run) => [
      RunShareStatKind.distance,
      RunShareStatKind.pace,
      RunShareStatKind.time,
      if (runShareClimbMetres(run) != null) RunShareStatKind.climb,
      if (runShareAvgBpm(run) != null) RunShareStatKind.heartRate,
    ];

/// The stats a share image prints for [run], in display order: the [kinds]
/// asked for that the run has a number for. Never empty — a look whose every
/// pick is unavailable on this run falls back to distance.
List<RunShareStat> runShareStats(
  AppLocalizations l10n,
  Run run,
  DistanceUnit unit, {
  List<RunShareStatKind> kinds = const [
    RunShareStatKind.distance,
    RunShareStatKind.pace,
    RunShareStatKind.time,
  ],
}) {
  final available = availableShareStats(run);
  var chosen = [
    for (final k in RunShareStatKind.values)
      if (kinds.contains(k) && available.contains(k)) k,
  ];
  if (chosen.isEmpty) chosen = const [RunShareStatKind.distance];

  final activity =
      ActivityType.fromName(run.metadata?['activity_type'] as String?);
  final moving = runShareMovingTime(run);
  final pace = runShareMovingPace(run, moving);
  RunShareStat stat(RunShareStatKind kind) {
    switch (kind) {
      case RunShareStatKind.distance:
        return (
          kind: kind,
          label: l10n.shareCardStatDistance,
          value: UnitFormat.distanceValue(run.distanceMetres, unit),
          unit: UnitFormat.distanceLabel(unit),
        );
      case RunShareStatKind.pace:
        return activity.usesSpeed
            ? (
                kind: kind,
                label: l10n.shareCardStatSpeed,
                value: UnitFormat.speed(pace, unit),
                unit: UnitFormat.speedLabel(unit),
              )
            : (
                kind: kind,
                label: l10n.shareCardStatPace,
                value: UnitFormat.pace(pace, unit),
                unit: UnitFormat.paceLabel(unit),
              );
      case RunShareStatKind.time:
        return (
          kind: kind,
          label: l10n.shareCardStatTime,
          value: formatShareDuration(moving),
          unit: null,
        );
      case RunShareStatKind.climb:
        return (
          kind: kind,
          label: l10n.shareCardStatClimb,
          value: UnitFormat.elevationValue(runShareClimbMetres(run)!, unit),
          unit: UnitFormat.elevationLabel(unit),
        );
      case RunShareStatKind.heartRate:
        return (
          kind: kind,
          label: l10n.shareCardStatHeartRate,
          value: '${runShareAvgBpm(run)!}',
          unit: l10n.runUnitBpm,
        );
    }
  }

  return [for (final k in chosen) stat(k)];
}
