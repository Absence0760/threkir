import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/recurrence.dart';

/// The Dart reader of `fixtures/recurrence_vectors.json`, the occurrence
/// vectors generated from web's `expandInstances` and replayed by
/// `apps/web/src/lib/social/recurrence_vectors.test.ts` and by the database's
/// `private.is_event_occurrence` (`event_occurrence_vectors_test.sql`). The
/// event-photo trigger refuses any instant that SQL function rejects, so this
/// expansion offering a different instant is a photo the database refuses
/// (decisions § 1905).
///
/// A series with a timezone expands on the UTC clock and must give the same
/// answer on every host. A legacy series (no timezone) expands in the host's
/// local zone, so it is checked against the fixture's entry for that zone:
/// `TZ=Asia/Kolkata flutter test test/recurrence_vectors_test.dart` runs those
/// against the Kolkata vectors; a host zone the fixture does not carry skips
/// them.
void main() {
  final fixture = jsonDecode(
          File('../../fixtures/recurrence_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final zones = (fixture['viewer_zones'] as List).cast<String>();
  final host = _hostZone(zones);

  for (final s in (fixture['series'] as List).cast<Map<String, dynamic>>()) {
    final event = s['event'] as Map<String, dynamic>;
    final legacy = event['recurrence_freq'] != null && event['timezone'] == null;
    final zone = legacy ? host : zones.first;
    test(
      'recurrence vectors — ${s['name']}: expandInstances reproduces the fixture',
      () {
        final e = _recurrence(event);
        final expected = ((s['expected'] as Map<String, dynamic>)[zone] as List)
            .cast<String>()
            .map((iso) => DateTime.parse(iso).microsecondsSinceEpoch)
            .toList();
        final got = expandInstances(e, DateTime.parse(s['from'] as String),
                DateTime.parse(s['to'] as String),
                max: 1000)
            .map((d) => d.microsecondsSinceEpoch)
            .toList();
        expect(got, expected);

        for (final p in (s['probes'] as List).cast<Map<String, dynamic>>()) {
          final at = DateTime.parse(p['at'] as String);
          final want = (p['occurrence'] as Map<String, dynamic>)[zone] as bool;
          final isOccurrence = expandInstances(e, at, at).any(
              (d) => d.microsecondsSinceEpoch == at.microsecondsSinceEpoch);
          expect(isOccurrence, want, reason: '${p['at']} in $zone');
        }
      },
      skip: zone == null
          ? 'legacy series expand in the host zone, and the fixture carries no '
              'vectors for this one (TZ=${Platform.environment['TZ']})'
          : null,
    );
  }
}

// TZ names the host zone when it is set; otherwise the zone is recognised by
// its January and July offsets, which is enough to tell the fixture's zones
// apart from each other and from anything else.
String? _hostZone(List<String> zones) {
  final tz = Platform.environment['TZ'];
  if (tz != null && zones.contains(tz)) return tz;
  const fingerprints = <String, List<int>>{
    'UTC': [0, 0],
    'America/New_York': [-300, -240],
    'Asia/Kolkata': [330, 330],
  };
  final offsets = [
    DateTime(2026, 1, 15).timeZoneOffset.inMinutes,
    DateTime(2026, 7, 15).timeZoneOffset.inMinutes,
  ];
  for (final zone in zones) {
    final f = fingerprints[zone];
    if (f != null && f[0] == offsets[0] && f[1] == offsets[1]) return zone;
  }
  return null;
}

EventRecurrence _recurrence(Map<String, dynamic> e) {
  final until = e['recurrence_until'] as String?;
  return EventRecurrence(
    startsAt: DateTime.parse(e['starts_at'] as String),
    freq: recurrenceFromString(e['recurrence_freq'] as String?),
    byday: (e['recurrence_byday'] as List?)
        ?.cast<String>()
        .map((c) => weekdayFromCode(c)!)
        .toList(),
    until: until == null ? null : DateTime.parse(until),
    count: e['recurrence_count'] as int?,
    timezone: e['timezone'] as String?,
  );
}
