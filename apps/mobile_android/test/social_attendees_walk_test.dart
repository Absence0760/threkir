import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The event-detail attendee list read one unranged select: PostgREST caps it
/// at `db.max-rows` (1000) with a 200 and no flag, so a big race's list lost
/// everyone past the cap, and its `joined_at`-only order left tied RSVPs in no
/// defined order. It walks the occurrence by keyset cursor now (decisions
/// § 1927); the walk itself is pinned in core_models' `keyset_page_test.dart`.
/// A source guard because the truncation is silent — a capped list renders as
/// a complete one.
void main() {
  test('fetchAttendees walks the occurrence by keyset cursor', () {
    final src = File('lib/social_service.dart').readAsStringSync();
    final start = src.indexOf('Future<List<AttendeeView>> fetchAttendees(');
    expect(start, greaterThan(-1), reason: 'fetchAttendees moved or was renamed');
    final end = src.indexOf('if (attendees.isEmpty)', start);
    expect(end, greaterThan(start), reason: 're-anchor this guard');
    final read = src.substring(start, end);
    expect(read.contains('walkKeyset(\n      ApiClient.eventAttendeeOrder,'),
        isTrue,
        reason: 'an unranged select silently truncates at 1000 attendees');
    expect(read.contains('q.or(after)'), isTrue,
        reason: 'each page must start after the last row of the previous one');
    expect(read.contains('for (final k in ApiClient.eventAttendeeOrder)'),
        isTrue,
        reason: 'the read must sort by the order its cursor is taken in');
    expect(read.contains('.range('), isFalse,
        reason: '.range() is an OFFSET walk, which skips or repeats a row');
  });
}
