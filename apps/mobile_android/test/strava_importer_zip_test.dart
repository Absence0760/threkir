import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/import_failures.dart';
import '../lib/run_stats.dart';
import '../lib/strava_importer.dart';

const _gpxOnePoint = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test"><trk><trkseg>
  <trkpt lat="47.37" lon="8.54"><ele>400</ele><time>2026-04-09T07:30:00Z</time></trkpt>
</trkseg></trk></gpx>''';

const _gpxTwoPoint = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test"><trk><trkseg>
  <trkpt lat="47.37" lon="8.54"><ele>400</ele><time>2026-04-09T07:30:00Z</time></trkpt>
  <trkpt lat="47.371" lon="8.541"><ele>405</ele><time>2026-04-09T08:00:00Z</time></trkpt>
</trkseg></trk></gpx>''';

const _gpxNoPoints = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test"><metadata><name>Empty</name></metadata></gpx>''';

String csv(List<List<String>> rows) {
  final buf = StringBuffer();
  for (final row in rows) {
    final cells = row.map((c) {
      if (c.contains(',') || c.contains('"')) {
        return '"${c.replaceAll('"', '""')}"';
      }
      return c;
    });
    buf.writeln(cells.join(','));
  }
  return buf.toString();
}

const _stravaHeader = [
  'Activity ID',
  'Activity Date',
  'Activity Name',
  'Activity Type',
  'Distance',
  'Elapsed Time',
  'Filename',
];

Future<File> writeZip(
  Directory tmpDir, {
  required String csvContent,
  Map<String, String>? gpxFiles,
}) async {
  final archive = Archive()
    ..addFile(ArchiveFile(
      'activities.csv',
      csvContent.length,
      utf8.encode(csvContent),
    ));
  if (gpxFiles != null) {
    for (final entry in gpxFiles.entries) {
      archive.addFile(ArchiveFile(
        entry.key,
        entry.value.length,
        utf8.encode(entry.value),
      ));
    }
  }
  final bytes = ZipEncoder().encode(archive);
  final zip = File('${tmpDir.path}/strava.zip');
  await zip.writeAsBytes(bytes);
  return zip;
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('strava_importer_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('activity_type derivation from Strava type column', () {
    Future<String> activityTypeFor(String stravaType) async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', stravaType, '5', '1500',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, hasLength(1), reason: 'failed for "$stravaType"');
      return r.runs.first.metadata!['activity_type'] as String;
    }

    test('"Run" → "run"', () async {
      expect(await activityTypeFor('Run'), 'run');
    });

    test('"Walk" → "walk"', () async {
      expect(await activityTypeFor('Walk'), 'walk');
    });

    test('"Hike" → "hike"', () async {
      expect(await activityTypeFor('Hike'), 'hike');
    });

    test('"Trail Running" still maps to "run"', () async {
      expect(await activityTypeFor('Trail Running'), 'run');
    });

    test('Case-insensitive match: "WALKING" → "walk"', () async {
      expect(await activityTypeFor('WALKING'), 'walk');
    });

    test('Unknown activity type falls back to "run"', () async {
      expect(await activityTypeFor('Yoga'), 'run');
    });
  });

  group('csv column handling', () {
    test('throws when activities.csv is absent', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 1, utf8.encode('x')));
      final zip = File('${tmpDir.path}/empty.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        StravaImporter.importFromZip(zip),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when filename column is missing', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          ['Activity ID', 'Activity Date', 'Activity Name'],
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X'],
        ]),
      );
      await expectLater(
        StravaImporter.importFromZip(zip),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when activity date column is missing', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          ['Activity ID', 'Activity Name', 'Filename'],
          ['1', 'X', 'activities/1.gpx'],
        ]),
      );
      await expectLater(
        StravaImporter.importFromZip(zip),
        throwsA(isA<FormatException>()),
      );
    });

    test('header-only CSV produces empty result, no errors', () async {
      final zip = await writeZip(tmpDir, csvContent: csv([_stravaHeader]));
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, isEmpty);
      expect(r.failures.items, isEmpty);
    });

    // Strava leaves `Filename` empty for a manually-entered or indoor
    // activity — there is no track file, but the row IS the activity. This
    // used to `continue` before any counter, so a migrating runner's whole
    // treadmill history vanished from an import that reported cleanly; web's
    // importer keeps the same rows, trackless, off the CSV's own numbers.
    test('row with empty filename imports trackless from the CSV row',
        () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5', '1500', ''],
        ]),
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, hasLength(1));
      expect(r.runs.first.track, isEmpty);
      expect(r.runs.first.distanceMetres, 5000);
      expect(r.runs.first.duration, const Duration(seconds: 1500));
      expect(r.failures.items, isEmpty);
    });

    test('"distance (km)" header variant is recognised', () async {
      final header = [..._stravaHeader];
      header[4] = 'Distance (km)';
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          header,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '8.5', '0',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxOnePoint},
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, hasLength(1));
      expect(r.runs.first.distanceMetres, 8500);
    });
  });

  // Strava's activities.csv has two "Distance" columns: a summary-block one in
  // the athlete's display unit (km OR miles) and a raw-block one always in
  // metres. An imperial athlete's export used to import ~1.6x short because
  // the importer treated the display miles value as km. Single-point GPX
  // tracks have a distanceMetres of 0, so the CSV fallback is what's used.
  group('distance unit resolution', () {
    // Header with both Distance columns (summary display unit + raw metres).
    const twoBlock = [
      'Activity ID',
      'Activity Date',
      'Activity Name',
      'Activity Type',
      'Distance', // summary block: display unit
      'Elapsed Time',
      'Filename',
      'Moving Time',
      'Distance', // raw block: always metres
    ];

    Future<double> distanceFor(List<String> header, List<String> row) async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([header, row]),
        gpxFiles: {'activities/1.gpx': _gpxOnePoint},
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, hasLength(1));
      return r.runs.first.distanceMetres;
    }

    test('imperial export imports the raw metric distance, not the miles value',
        () async {
      // 5.00 mi run: summary "Distance" = 5.0 (miles), raw = 8046.72 m.
      final d = await distanceFor(twoBlock, [
        '1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5.0', '3600',
        'activities/1.gpx', '3400', '8046.72',
      ]);
      expect(d.round(), 8047);
    });

    test('metric export is unchanged — raw column is already metres', () async {
      // 8.05 km run: summary "Distance" = 8.05 (km), raw = 8050 m.
      final d = await distanceFor(twoBlock, [
        '1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '8.05', '3600',
        'activities/1.gpx', '3400', '8050',
      ]);
      expect(d.round(), 8050);
    });

    test('pure helper: two-column export prefers the raw metres column', () {
      expect(
        stravaCsvDistanceMetres(
          ['distance', 'x', 'distance'],
          ['5.0', 'y', '8046.72'],
        ).round(),
        8047,
      );
    });

    test('pure helper: single bare Distance falls back to km', () {
      expect(stravaCsvDistanceMetres(['distance'], ['8.5']), 8500);
    });

    test('pure helper: explicit "distance in miles" converts from miles', () {
      expect(
        stravaCsvDistanceMetres(['distance in miles'], ['5']).round(),
        8047,
      );
    });

    test('pure helper: a non-finite cell reads as 0, like the web twin', () {
      // `double.tryParse` returns a VALUE for these three literals, so the
      // old `?? 0` -- which only tested for an unparseable cell -- let them
      // through into the imported run's distance_m, a numeric(10, 2) column
      // with no CHECK whose aggregates then read NaN. The web
      // `stravaDistanceMetres` this function's doc names as its mirror has
      // guarded on Number.isFinite since it was written.
      for (final bad in ['NaN', 'Infinity', '-Infinity']) {
        expect(stravaCsvDistanceMetres(['distance (m)'], [bad]), 0,
            reason: bad);
        expect(
          stravaCsvDistanceMetres(['distance', 'x', 'distance'],
              ['5.0', 'y', bad]),
          0,
          reason: 'raw column $bad',
        );
      }
    });

    test('pure helper: an unparseable cell still reads as 0', () {
      expect(stravaCsvDistanceMetres(['distance (m)'], ['not a number']), 0);
      expect(stravaCsvDistanceMetres(['distance (m)'], ['']), 0);
    });
  });

  group('multi-row imports', () {
    test('imports multiple activities in one zip', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
              'activities/1.gpx'],
          ['2', 'Apr 10, 2026, 8:00:00 AM', 'B', 'Walk', '3', '2000',
              'activities/2.gpx'],
        ]),
        gpxFiles: {
          'activities/1.gpx': _gpxTwoPoint,
          'activities/2.gpx': _gpxTwoPoint,
        },
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, hasLength(2));
      expect(r.runs.map((r) => r.externalId), ['strava:1', 'strava:2']);
      expect(r.runs[0].metadata!['activity_type'], 'run');
      expect(r.runs[1].metadata!['activity_type'], 'walk');
    });

    test('one missing track file errors but the rest still import', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
              'activities/missing.gpx'],
          ['2', 'Apr 10, 2026, 8:00:00 AM', 'B', 'Run', '5', '1500',
              'activities/2.gpx'],
        ]),
        gpxFiles: {'activities/2.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, hasLength(1));
      expect(r.runs.single.externalId, 'strava:2');
      expect(r.failures.items, hasLength(1));
      // The report names the ACTIVITY, not the archive path — the path is
      // carried in the classified detail.
      expect(r.failures.items.single.name, 'A');
      expect(r.failures.items.single.startedAt, isNotNull);
      expect(r.failures.items.single.detail, contains('activities/missing.gpx'));
      // NOT `unknown`: the archive is missing a member its own index named,
      // so re-running the import can never land this run, and the report's
      // reason has to say that rather than shrug.
      expect(r.failures.items.single.reason, ImportFailureReason.unparseable);
    });

    test('unknown track extension is reported as a per-file error', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
              'activities/1.bin'],
        ]),
        gpxFiles: {'activities/1.bin': '<not real>'},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, isEmpty);
      expect(r.failures.items, hasLength(1));
      expect(r.failures.items.single.name, 'A');
      expect(r.failures.items.single.detail, contains('Unsupported'));
      expect(r.failures.items.single.reason, ImportFailureReason.unparseable);
    });
  });

  group('distance and duration fallback', () {
    test('distance falls back to CSV when GPX has no waypoints', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '7.5', '1500',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxNoPoints},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs.single.distanceMetres, 7500);
    });

    test('duration falls back to CSV elapsed when track has <2 waypoints',
        () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5', '1234',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxOnePoint},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs.single.duration, const Duration(seconds: 1234));
    });

    test('duration uses GPX timestamps when CSV elapsed is 0', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5', '0',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs.single.duration, const Duration(minutes: 30));
    });
  });

  group('metadata population', () {
    test('imported_from + strava_activity_type + title are set', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'My Tempo', 'Trail Running', '5',
              '1500', 'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);
      final m = r.runs.single.metadata!;

      expect(m['imported_from'], 'strava');
      expect(m['strava_activity_type'], 'Trail Running');
      expect(m['title'], 'My Tempo');
      expect(m['activity_type'], 'run');
      expect(m.containsKey('imported_at'), isTrue);
    });

    test('blank activity name falls back to "Strava import"', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', '', 'Run', '5', '1500',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs.single.metadata!['title'], 'Strava import');
    });
  });

  group('embedded best efforts', () {
    // A GPX along the equator: `segments` legs of `stepM` metres each,
    // `stepS` seconds apart, so the fastest embedded window is computable.
    String evenGpx(int segments, double stepM, int stepS) {
      const mPerDeg = 6371000 * 3.141592653589793 / 180;
      final stepDeg = stepM / mPerDeg;
      final start = DateTime.utc(2026, 4, 9, 7, 30);
      final buf = StringBuffer('<?xml version="1.0"?>\n<gpx version="1.1" '
          'creator="test"><trk><trkseg>\n');
      for (var i = 0; i <= segments; i++) {
        final t = start.add(Duration(seconds: i * stepS));
        buf.writeln('<trkpt lat="0.0" lon="${i * stepDeg}"><ele>10</ele>'
            '<time>${t.toIso8601String()}</time></trkpt>');
      }
      buf.write('</trkseg></trk></gpx>');
      return buf.toString();
    }

    test('a 6 km imported run gets fastest_5k_s (reaches personal_records)',
        () async {
      // 60 × 100 m @ 30 s = 6 km at 5:00/km → fastest 5 km ≈ 1500 s.
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'Long run', 'Run', '6', '1800',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': evenGpx(60, 100, 30)},
      );

      final r = await StravaImporter.importFromZip(zip);
      final m = r.runs.single.metadata!;
      expect(m.containsKey('fastest_5k_s'), isTrue,
          reason: 'a fast 5 km inside an imported run must reach PRs');
      final secs = m['fastest_5k_s'] as int;
      expect(secs, inInclusiveRange(1495, 1505));
      // No 10 km window fits in a 6 km run.
      expect(m.containsKey('fastest_10k_s'), isFalse);
    });

    test('a sub-5 km imported run writes no embedded bests', () async {
      // 40 × 100 m = 4 km — below the 5 km bracket.
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'Short', 'Run', '4', '1200',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': evenGpx(40, 100, 30)},
      );

      final r = await StravaImporter.importFromZip(zip);
      final m = r.runs.single.metadata!;
      expect(m.containsKey('fastest_5k_s'), isFalse);
    });

    test('a trackless (CSV-only) import writes no fake embedded bests',
        () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '10', '3000',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxNoPoints},
      );

      final r = await StravaImporter.importFromZip(zip);
      final m = r.runs.single.metadata!;
      expect(m.containsKey('fastest_5k_s'), isFalse);
      expect(m.containsKey('fastest_10k_s'), isFalse);
    });
  });

  group('FIT device distance', () {
    // A FIT whose records carry the watch's own distance beside positions
    // that disagree with it: the line zig-zags 3 m either side of the road
    // for the first 600 m (a start among tall buildings), then runs true, at
    // 3.0 m/s throughout (333 s/km). [distance] maps a record's index to the
    // distance it carries, or null to leave the field out.
    Uint8List fitBytes({double? Function(int i, double d)? distance}) {
      List<int> u32(int v) =>
          [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
      const semi = (1 << 31) / 180.0;
      const mPerDeg = 111320.0;
      final body = <int>[
        0x40, 0x00, 0x00, 20, 0, 4, //
        253, 4, 0x86, //
        0, 4, 0x85, //
        1, 4, 0x85, //
        5, 4, 0x86, //
      ];
      for (var i = 0; i <= 617; i++) {
        final d = i * 6.0;
        final latM = d < 600 ? (i.isEven ? 3.0 : -3.0) : 0.0;
        final dist = distance == null ? d : distance(i, d);
        body.addAll([
          0x00,
          ...u32(1000000000 + i * 2),
          ...u32((latM / mPerDeg * semi).round()),
          ...u32((d / mPerDeg * semi).round()),
          ...u32(dist == null ? 0xFFFFFFFF : (dist * 100).round()),
        ]);
      }
      final bytes = Uint8List(14 + body.length);
      bytes[0] = 14;
      bytes[1] = 0x10;
      bytes.setRange(4, 8, u32(body.length));
      bytes.setRange(8, 12, '.FIT'.codeUnits);
      bytes.setRange(14, bytes.length, body);
      return bytes;
    }

    Future<File> fitZip(Uint8List fit) async {
      final csvContent = csv([
        _stravaHeader,
        ['1', 'Apr 9, 2026, 7:30:00 AM', 'Race', 'Run', '3.75', '1234',
            'activities/1.fit'],
      ]);
      final archive = Archive()
        ..addFile(ArchiveFile(
            'activities.csv', csvContent.length, utf8.encode(csvContent)))
        ..addFile(ArchiveFile('activities/1.fit', fit.length, fit));
      final zip = File('${tmpDir.path}/strava.zip');
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      return zip;
    }

    test(
        'every waypoint carries the watch distance, so mile splits match its '
        'auto-laps (#1387)', () async {
      final r = await StravaImporter.importFromZip(await fitZip(fitBytes()));
      final run = r.runs.single;
      expect(run.track, hasLength(618));
      expect(run.track.first.cumulativeDistanceMetres, 0);
      expect(run.track.last.cumulativeDistanceMetres, closeTo(3702, 0.01));
      expect(run.distanceMetres, closeTo(3702, 0.01));

      final splits = computeSplitDurations(
          run.track, 1609.344, run.startedAt,
          totalDistanceMetres: run.distanceMetres);
      expect(splits, hasLength(2));
      for (final s in splits) {
        expect(s.duration.inMilliseconds / 1000, closeTo(536.448, 1),
            reason: 'mile ${s.tick}');
      }

      // On the positions alone the zig-zag at the start reaches the first
      // mile early and reads it far faster than the watch's lap.
      final onPositions = computeSplitDurations(
          [
            for (final w in run.track)
              Waypoint(lat: w.lat, lng: w.lng, timestamp: w.timestamp),
          ],
          1609.344,
          run.startedAt);
      expect(onPositions.first.duration.inSeconds, lessThan(536 - 45));
    });

    test('a stream with a gap leaves the track on its positions', () async {
      final r = await StravaImporter.importFromZip(await fitZip(
          fitBytes(distance: (i, d) => i == 300 ? null : d)));
      final run = r.runs.single;
      expect(run.track.any((w) => w.cumulativeDistanceMetres != null), isFalse);
      expect(run.distanceMetres, greaterThan(3702));
    });
  });

  group('compressed track files', () {
    test('.gpx.gz is decompressed before parsing', () async {
      final gz = GZipEncoder().encode(utf8.encode(_gpxTwoPoint));
      final csvContent = csv([
        _stravaHeader,
        ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
            'activities/1.gpx.gz'],
      ]);
      final archive = Archive()
        ..addFile(ArchiveFile(
          'activities.csv',
          csvContent.length,
          utf8.encode(csvContent),
        ))
        ..addFile(
            ArchiveFile('activities/1.gpx.gz', gz.length, gz));
      final bytes = ZipEncoder().encode(archive);
      final zip = File('${tmpDir.path}/gz.zip')..writeAsBytesSync(bytes);

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, hasLength(1));
      expect(r.runs.single.track, hasLength(2));
    });
  });
}
