import 'package:core_models/core_models.dart' show DistanceUnit;

import 'audio_cues.dart' show formatSpokenDistance;
import 'course_drive.dart';
import 'l10n/gen/app_localizations.dart';

/// The marker kind as the screens name it.
String driveKindLabel(AppLocalizations l, String kind) => switch (kind) {
  'aid_station' => l.routeMarkerKindAidStation,
  'cutoff' => l.routeMarkerKindCutoff,
  'crew_access' => l.routeMarkerKindCrewAccess,
  'hazard' => l.routeMarkerKindHazard,
  'note' => l.routeMarkerKindNote,
  'climb' => l.routeMarkerKindClimb,
  _ => l.routeMarkerKindCustom,
};

String _serviceLabel(AppLocalizations l, String s) => switch (s) {
  'water' => l.routeMarkerServiceWater,
  'food' => l.routeMarkerServiceFood,
  'medical' => l.routeMarkerServiceMedical,
  'toilets' => l.routeMarkerServiceToilets,
  'drop_bag' => l.routeMarkerServiceDropBag,
  _ => s,
};

/// An elapsed cut-off as `h:mm`, the form a voice reads as a time.
String driveElapsedClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

/// A lead distance rounded to the nearest 50 m, never below 50 m: "in 210
/// metres" is false precision at 50 km/h.
double roundSpokenAheadM(double aheadM) =>
    aheadM <= 50 ? 50 : (aheadM / 50).round() * 50.0;

/// What the phone says for one cue: the note itself, then its detail (aid
/// services, a cut-off, a climb's length and grade) as a second sentence.
String driveCueUtterance(
  AppLocalizations l,
  DriveCue cue,
  DistanceUnit unit,
  String localeTag,
) {
  final note = cue.note;
  final kind = driveKindLabel(l, note.kind);
  final hasLabel = note.label.isNotEmpty;
  final head = switch (cue.band) {
    DriveCueBand.ahead => () {
      final d = formatSpokenDistance(
        roundSpokenAheadM(cue.aheadM),
        unit,
        localeTag,
      );
      return hasLabel
          ? l.ttsDriveAhead(d, kind, note.label)
          : l.ttsDriveAheadKind(d, kind);
    }(),
    DriveCueBand.at =>
      hasLabel ? l.ttsDriveAt(kind, note.label) : l.ttsDriveAtKind(kind),
    DriveCueBand.passed =>
      hasLabel
          ? l.ttsDrivePassed(kind, note.label)
          : l.ttsDrivePassedKind(kind),
  };
  final detail = driveNoteDetailSpoken(l, note, unit, localeTag);
  return detail == null ? head : '$head $detail';
}

/// The spoken second sentence of a note, or null when it has none.
String? driveNoteDetailSpoken(
  AppLocalizations l,
  DriveNote note,
  DistanceUnit unit,
  String localeTag,
) {
  if (note.services.isNotEmpty) {
    return l.ttsDriveServices(
      note.services.map((s) => _serviceLabel(l, s)).join(', '),
    );
  }
  final cutoff = note.cutoff;
  if (cutoff?.clock != null) return l.ttsDriveCutoffClock(cutoff!.clock!);
  if (cutoff?.elapsedS != null) {
    return l.ttsDriveCutoffElapsed(driveElapsedClock(cutoff!.elapsedS!));
  }
  final climb = note.climb;
  if (climb != null) {
    return l.ttsDriveClimb(
      formatSpokenDistance(climb.lengthM, unit, localeTag),
      climb.gradePct.toStringAsFixed(1),
    );
  }
  return null;
}

/// The on-screen detail line of a note, or null when it has none.
String? driveNoteDetailShown(
  AppLocalizations l,
  DriveNote note,
  String Function(double metres) formatDistance,
) {
  if (note.services.isNotEmpty) {
    return note.services.map((s) => _serviceLabel(l, s)).join(', ');
  }
  final cutoff = note.cutoff;
  if (cutoff?.clock != null) return l.courseDriveCutoffClock(cutoff!.clock!);
  if (cutoff?.elapsedS != null) {
    return l.courseDriveCutoffElapsed(driveElapsedClock(cutoff!.elapsedS!));
  }
  final climb = note.climb;
  if (climb != null) {
    return l.courseDriveClimb(
      formatDistance(climb.lengthM),
      climb.gradePct.toStringAsFixed(1),
    );
  }
  return null;
}
