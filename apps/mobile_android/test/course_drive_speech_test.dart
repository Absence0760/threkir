import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import '../lib/course_drive.dart';
import '../lib/course_drive_speech.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/route_markers.dart' show CutoffParts;

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  DriveCue cue(DriveNote n, DriveCueBand band, double aheadM) =>
      DriveCue(index: 0, note: n, band: band, aheadM: aheadM);

  test('an aid station ahead names its distance, kind, label and services', () {
    const n = DriveNote(
      alongM: 5000,
      kind: 'aid_station',
      label: 'Mile 8',
      services: ['water', 'food', 'sponges'],
    );
    expect(
      driveCueUtterance(
        en,
        cue(n, DriveCueBand.ahead, 412),
        DistanceUnit.km,
        'en',
      ),
      'In 400 metres: Aid station, Mile 8. Services: Water, Food, sponges.',
    );
  });

  test('a climb at the marker reads its length and grade in the unit pref', () {
    const n = DriveNote(
      alongM: 1,
      kind: 'climb',
      label: 'Libbie Hill',
      climb: DriveClimb(lengthM: 965.6, gradePct: 3),
    );
    expect(
      driveCueUtterance(en, cue(n, DriveCueBand.at, 5), DistanceUnit.mi, 'en'),
      'Now: Climb, Libbie Hill. 1056 yards at about 3.0 percent.',
    );
  });

  test('a passed cut-off with no label still says what it was', () {
    const clock = DriveNote(
      alongM: 1,
      kind: 'cutoff',
      label: '',
      cutoff: CutoffParts(clock: '11:30'),
    );
    expect(
      driveCueUtterance(
        en,
        cue(clock, DriveCueBand.passed, -80),
        DistanceUnit.km,
        'en',
      ),
      'Just passed: Cut-off. Cut-off at 11:30.',
    );
    const elapsed = DriveNote(
      alongM: 1,
      kind: 'cutoff',
      label: 'Bridge',
      cutoff: CutoffParts(elapsedS: 5 * 3600 + 5 * 60),
    );
    expect(
      driveCueUtterance(
        en,
        cue(elapsed, DriveCueBand.at, 0),
        DistanceUnit.km,
        'en',
      ),
      'Now: Cut-off, Bridge. Cut-off 5:05 after the start.',
    );
  });

  test('a lead distance is rounded to 50 m, never below it', () {
    expect(roundSpokenAheadM(12), 50);
    expect(roundSpokenAheadM(374), 350);
    expect(roundSpokenAheadM(376), 400);
  });

  test('an unknown kind reads as custom, and a plain note has no detail', () {
    const n = DriveNote(alongM: 1, kind: 'mystery', label: 'Odd');
    expect(driveKindLabel(en, n.kind), 'Custom');
    expect(driveNoteDetailShown(en, n, (m) => '$m m'), isNull);
  });
}
