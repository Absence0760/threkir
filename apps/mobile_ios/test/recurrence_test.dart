import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/recurrence.dart';

void main() {
  group('expandInstances — weekly recurrence', () {
    test('each weekly instance hour/minute matches the local interpretation of startsAt', () {
      // An event stored in the DB as UTC (e.g. 10:30 UTC).
      // After the fix, each instance carries the *local* hour/minute of that UTC
      // timestamp. Before the fix, it carried the raw UTC hour, which is wrong
      // for any user whose offset != 0.
      final utcStart = DateTime.utc(2026, 4, 1, 10, 30, 0);
      final localStart = utcStart.toLocal();
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);

      final instances = expandInstances(e, from, to);
      expect(instances, isNotEmpty,
          reason: 'at least one weekly instance should fall in April');
      for (final inst in instances) {
        // inst is a local (unzoned) DateTime — its .hour/.minute are local fields.
        expect(inst.hour, localStart.hour,
            reason: 'instance hour should be localStart.hour, not the raw UTC hour');
        expect(inst.minute, localStart.minute);
        expect(inst.second, localStart.second);
      }
    });

    test('instances do not precede the original startsAt', () {
      final utcStart = DateTime.utc(2026, 4, 8, 9, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);

      final instances = expandInstances(e, from, to);
      expect(instances, isNotEmpty);
      for (final inst in instances) {
        expect(inst.isBefore(e.startsAt), isFalse,
            reason: 'no instance should precede the event start');
      }
    });

    test('weekly emits the startsAt week when startsAt carries milliseconds', () {
      // Mirror of web's `expandInstances — weekly emits the starts_at week when
      // starts_at carries milliseconds`. The stamp rebuilds the instant from
      // whole seconds, so a startsAt of ...:18.132Z produced a first candidate
      // of ...:18.000 that lost `stamped < startsAt` — the series' own first
      // occurrence vanished from the picker, the listings and every RSVP key.
      final from = DateTime.utc(2026, 8, 17);
      final to = DateTime.utc(2026, 8, 30, 23, 59, 59);
      final withMs = EventRecurrence(
        startsAt: DateTime.utc(2026, 8, 23, 2, 49, 18, 132),
        freq: RecurrenceFreq.weekly,
        timezone: 'UTC',
      );
      final withoutMs = EventRecurrence(
        startsAt: DateTime.utc(2026, 8, 23, 2, 49, 18),
        freq: RecurrenceFreq.weekly,
        timezone: 'UTC',
      );

      final out = expandInstances(withMs, from, to);
      expect(out.first, DateTime.utc(2026, 8, 23, 2, 49, 18));
      expect(out, expandInstances(withoutMs, from, to));
    });

    test('biweekly event produces fewer instances than weekly in the same window', () {
      final utcStart = DateTime.utc(2026, 4, 1, 8, 0, 0);
      final weekly = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
      );
      final biweekly = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.biweekly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 4, 30);

      final wInstances = expandInstances(weekly, from, to);
      final bInstances = expandInstances(biweekly, from, to);
      // Biweekly should produce at most half as many instances.
      expect(bInstances.length, lessThan(wInstances.length));
    });

    test('biweekly with a weekend-crossing byday matches the web Monday anchor', () {
      // Twin-parity regression: Dart used to anchor the week on Sunday while
      // web anchors on Monday, so a biweekly [SA, SU] event disagreed on which
      // alternating weeks fire. Local (unzoned) start so the byday is the same
      // wall-clock Saturday in every test timezone. Expected dates are the
      // canonical web output (Monday anchor): May 2/3, 16/17, 30/31 2026.
      final e = EventRecurrence(
        startsAt: DateTime(2026, 5, 2, 9, 0), // Sat 09:00 local
        freq: RecurrenceFreq.biweekly,
        byday: const [Weekday.sa, Weekday.su],
      );

      final instances = expandInstances(
        e,
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 31, 23, 59, 59),
      );

      final dates = instances.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      expect(dates, ['2026-5-2', '2026-5-3', '2026-5-16', '2026-5-17', '2026-5-30', '2026-5-31']);
    });

    test('recurrence_count cap limits the number of instances', () {
      final utcStart = DateTime.utc(2026, 4, 1, 8, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
        count: 2,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 12, 31);

      final instances = expandInstances(e, from, to);
      expect(instances, hasLength(2));
    });

    test('a count of 0 yields no instance, weekly as monthly', () {
      // The column admits 0 (20270705000004). The monthly loop and the
      // database's is_event_occurrence both read it as no occurrence; the
      // weekly loop counted after emitting and so offered the first one, an
      // instant the photo trigger then refused.
      for (final freq in RecurrenceFreq.values) {
        final e = EventRecurrence(
          startsAt: DateTime.utc(2026, 4, 1, 8, 0, 0),
          freq: freq,
          count: 0,
          timezone: 'UTC',
        );
        final instances = expandInstances(
            e, DateTime.utc(2026, 4, 1), DateTime.utc(2026, 12, 31, 23, 59, 59));
        expect(instances, isEmpty, reason: freq.name);
      }
    });

    test('count-limited weekly is exhausted before a later window (no phantom occurrences)', () {
      // Regression: count caps TOTAL occurrences, not in-window ones. A
      // 3-occurrence weekly series (Apr 1/8/15) viewed in a LATER window must
      // return nothing — the series ended before the window opened. The old
      // code counted only in-window adds, so it walked past the real end and
      // emitted phantom April-29-onward instances.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 1, 8, 0, 0),
        freq: RecurrenceFreq.weekly,
        count: 3,
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 5, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out, isEmpty);
    });

    test('count-limited weekly partially overlapping a window counts pre-window occurrences', () {
      // Window opens after the 1st occurrence (Apr 1) but before the series
      // end; Apr 1/8/15 with count 3 → only Apr 8 + Apr 15 in [Apr 8, …].
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 1, 8, 0, 0),
        freq: RecurrenceFreq.weekly,
        count: 3,
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 4, 8),
        DateTime.utc(2026, 12, 31),
      );
      final dates = out.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      expect(dates, ['2026-4-8', '2026-4-15']);
    });

    test('nextInstanceAfter — exhausted count-limited series returns null, not a phantom', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 1, 7, 9, 0, 0),
        freq: RecurrenceFreq.weekly,
        count: 3, // Jan 7/14/21
      );
      final next = nextInstanceAfter(e, DateTime.utc(2026, 2, 1));
      expect(next, isNull);
    });

    test('nextInstanceAfter — returns null past recurrence_until', () {
      // The series ended in April; asking in May must report no next
      // occurrence rather than the last one that ever ran. Ported from the web
      // mirror, which was the only rail asserting it (decisions § 1444).
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 1, 8, 0, 0),
        freq: RecurrenceFreq.weekly,
        until: DateTime.utc(2026, 4, 30, 23, 59, 59),
      );
      final next = nextInstanceAfter(e, DateTime.utc(2026, 5, 1));
      expect(next, isNull);
    });

    test('nextInstanceAfter — a years-old weekly series still reports its next occurrence', () {
      // The scan budget used to be derived from `max` (1 here), so the walk gave
      // up 49 days after the series began and a club's long-running Monday-night
      // run reported no next occurrence at all.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2024, 1, 1, 9, 0, 0),
        freq: RecurrenceFreq.weekly,
        byday: const [Weekday.mo],
        timezone: 'UTC',
      );
      final next = nextInstanceAfter(e, DateTime.utc(2026, 8, 9));
      expect(next?.toUtc().toIso8601String(), '2026-08-10T09:00:00.000Z');
    });

    test('nextInstanceAfter — a years-old monthly series still reports its next occurrence', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2024, 1, 15, 9, 0, 0),
        freq: RecurrenceFreq.monthly,
        timezone: 'UTC',
      );
      final next = nextInstanceAfter(e, DateTime.utc(2026, 8, 9));
      expect(next?.toUtc().toIso8601String(), '2026-08-15T09:00:00.000Z');
    });

    test('expandInstances — a small max does not shorten how far the scan reaches', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2024, 1, 1, 9, 0, 0),
        freq: RecurrenceFreq.weekly,
        byday: const [Weekday.mo],
        timezone: 'UTC',
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 8, 31),
        max: 4,
      );
      expect(out.map((d) => d.toUtc().toIso8601String()).toList(), [
        '2026-08-03T09:00:00.000Z',
        '2026-08-10T09:00:00.000Z',
        '2026-08-17T09:00:00.000Z',
        '2026-08-24T09:00:00.000Z',
      ]);
    });

    test('until date stops expansion — no instance falls after until', () {
      final utcStart = DateTime.utc(2026, 4, 1, 8, 0, 0);
      final until = DateTime.utc(2026, 4, 22);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.weekly,
        until: until,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 12, 31);

      final instances = expandInstances(e, from, to);
      expect(instances, isNotEmpty);
      for (final inst in instances) {
        expect(inst.isAfter(until), isFalse,
            reason: 'no instance should fall after the until date');
      }
    });

    test('non-recurring event returns the single instance if in window', () {
      final utcStart = DateTime.utc(2026, 4, 10, 8, 0, 0);
      final e = EventRecurrence(startsAt: utcStart);

      expect(
        expandInstances(e, DateTime.utc(2026, 4, 1), DateTime.utc(2026, 4, 30)),
        hasLength(1),
      );
      expect(
        expandInstances(e, DateTime.utc(2026, 5, 1), DateTime.utc(2026, 5, 31)),
        isEmpty,
      );
    });
  });

  group('expandInstances — monthly recurrence', () {
    test('monthly event produces one instance per month in window', () {
      final utcStart = DateTime.utc(2026, 4, 5, 10, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.monthly,
      );

      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 6, 30);

      final instances = expandInstances(e, from, to);
      expect(instances, hasLength(3)); // Apr 5, May 5, Jun 5
    });

    test('day-31 monthly clamps to the last day of shorter months (no overflow)', () {
      // Jan-31 monthly must land on Feb-28 (2026 is not a leap year), Mar-31,
      // Apr-30 — never overflow into the following month. A naive
      // DateTime(y, 2, 31) rolls into March 3.
      final start = DateTime(2026, 1, 31, 9, 0);
      final e = EventRecurrence(
        startsAt: start,
        freq: RecurrenceFreq.monthly,
      );

      final instances = expandInstances(
        e,
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30, 23, 59, 59),
      );

      final dates = instances.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      expect(dates, ['2026-1-31', '2026-2-28', '2026-3-31', '2026-4-30']);
      // The clamp must not permanently shrink the day-of-month: March is
      // back to 31, proving each instance re-anchors on the original day.
      for (final inst in instances) {
        expect(inst.hour, 9);
        expect(inst.minute, 0);
      }
    });

    test('day-31 monthly hits Feb-29 in a leap year', () {
      final start = DateTime(2024, 1, 31, 8, 0);
      final e = EventRecurrence(
        startsAt: start,
        freq: RecurrenceFreq.monthly,
      );

      final instances = expandInstances(
        e,
        DateTime(2024, 2, 1),
        DateTime(2024, 2, 29, 23, 59, 59),
      );

      expect(instances, hasLength(1));
      expect(instances.first.month, 2);
      expect(instances.first.day, 29);
    });

    test('monthly recurrence_count cap limits instances', () {
      final utcStart = DateTime.utc(2026, 1, 1, 9, 0, 0);
      final e = EventRecurrence(
        startsAt: utcStart,
        freq: RecurrenceFreq.monthly,
        count: 3,
      );

      final from = DateTime.utc(2026, 1, 1);
      final to = DateTime.utc(2026, 12, 31);

      final instances = expandInstances(e, from, to);
      expect(instances, hasLength(3));
    });

    test('count-limited monthly is exhausted before a later window (no phantom occurrences)', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 1, 5, 9, 0, 0),
        freq: RecurrenceFreq.monthly,
        count: 3, // Jan 5, Feb 5, Mar 5 — series ends after March
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 4, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(out, isEmpty);
    });
  });

  group('expandInstances — timezoned (viewer-independent instance_start)', () {
    List<String> isoList(EventRecurrence e, String from, String to) =>
        expandInstances(e, DateTime.parse(from), DateTime.parse(to))
            .map((d) => d.toUtc().toIso8601String())
            .toList();

    test('a timezoned weekly series keeps its local time of day across a DST change', () {
      // The capacity key + race-arm key of an occurrence must be one instant
      // for every viewer, and it must be the organiser's wall-clock: 07:00 in
      // New York on both sides of the 1 November fall-back, so the UTC hour
      // moves.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 10, 21, 11), // Wed 07:00 EDT
        freq: RecurrenceFreq.weekly,
        timezone: 'America/New_York',
      );
      expect(isoList(e, '2026-10-15T00:00:00Z', '2026-11-12T00:00:00Z'), [
        '2026-10-21T11:00:00.000Z',
        '2026-10-28T11:00:00.000Z',
        '2026-11-04T12:00:00.000Z',
        '2026-11-11T12:00:00.000Z',
      ]);
    });

    test('two cross-TZ viewers compute the SAME instance_start', () {
      // Re-running the same input stands in for two viewers; the absolute-time
      // assertion is what guards the cross-device case (the suite runs under
      // several TZ values, and the shared vectors replay every viewer zone).
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 5, 2, 8), // Sat 09:00 BST
        freq: RecurrenceFreq.biweekly,
        byday: const [Weekday.sa],
        timezone: 'Europe/London',
      );
      final viewerA = isoList(e, '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z');
      final viewerB = isoList(e, '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z');
      expect(viewerA, viewerB);
      expect(viewerA, [
        '2026-05-02T08:00:00.000Z',
        '2026-05-16T08:00:00.000Z',
        '2026-05-30T08:00:00.000Z',
      ]);
    });

    test('a timezoned monthly series keeps its local day-of-month and time', () {
      // 22:00 UTC on 31 January is 09:00 on 1 February in Sydney, so the
      // series is "the 1st at 09:00": the UTC hour moves when Sydney leaves
      // DST on 5 April.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 1, 31, 22),
        freq: RecurrenceFreq.monthly,
        timezone: 'Australia/Sydney',
      );
      expect(isoList(e, '2026-01-01T00:00:00Z', '2026-04-30T23:59:59Z'), [
        '2026-01-31T22:00:00.000Z',
        '2026-02-28T22:00:00.000Z',
        '2026-03-31T22:00:00.000Z',
        '2026-04-30T23:00:00.000Z',
      ]);
    });

    test('a weekday chip is a local weekday, so an evening series west of UTC keeps its day', () {
      // Wednesday 21:30 in New York is Thursday in UTC. Read on the UTC clock
      // the WE chip moved the series to Tuesday evenings and dropped its first
      // night.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 10, 22, 1, 30),
        freq: RecurrenceFreq.weekly,
        byday: const [Weekday.we],
        timezone: 'America/New_York',
      );
      expect(isoList(e, '2026-10-15T00:00:00Z', '2026-11-13T00:00:00Z'), [
        '2026-10-22T01:30:00.000Z',
        '2026-10-29T01:30:00.000Z',
        '2026-11-05T02:30:00.000Z',
        '2026-11-12T02:30:00.000Z',
      ]);
    });

    test('a wall-clock inside the spring-forward gap moves forward by the gap', () {
      // 02:30 does not exist in New York on 14 March 2027; it becomes 03:30 EDT.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2027, 3, 7, 7, 30), // Sun 02:30 EST
        freq: RecurrenceFreq.weekly,
        timezone: 'America/New_York',
      );
      expect(isoList(e, '2027-03-01T00:00:00Z', '2027-03-22T00:00:00Z'), [
        '2027-03-07T07:30:00.000Z',
        '2027-03-14T07:30:00.000Z',
        '2027-03-21T06:30:00.000Z',
      ]);
    });

    test('a wall-clock inside the fall-back overlap takes the earlier instant', () {
      // 01:30 happens twice in New York on 1 November 2026; the occurrence is
      // the first, 01:30 EDT, as RFC 5545 resolves it.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 10, 25, 5, 30), // Sun 01:30 EDT
        freq: RecurrenceFreq.weekly,
        timezone: 'America/New_York',
      );
      expect(isoList(e, '2026-10-20T00:00:00Z', '2026-11-09T00:00:00Z'), [
        '2026-10-25T05:30:00.000Z',
        '2026-11-01T05:30:00.000Z',
        '2026-11-08T06:30:00.000Z',
      ]);
    });

    test('a series started in the second pass of an overlap hour keeps startsAt first', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 11, 1, 6, 30), // Sun 01:30 EST, the later
        freq: RecurrenceFreq.weekly,
        timezone: 'America/New_York',
      );
      expect(isoList(e, '2026-10-20T00:00:00Z', '2026-11-09T00:00:00Z'), [
        '2026-11-01T06:30:00.000Z',
        '2026-11-08T06:30:00.000Z',
      ]);
    });

    test('a zone the runtime cannot resolve expands in UTC', () {
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 7, 13),
        freq: RecurrenceFreq.weekly,
        timezone: 'Not/AZone',
      );
      expect(isoList(e, '2026-04-01T00:00:00Z', '2026-04-15T00:00:00Z'), [
        '2026-04-07T13:00:00.000Z',
        '2026-04-14T13:00:00.000Z',
      ]);
    });

    test('legacy event with no timezone keeps viewer-local behaviour', () {
      // A row predating 20270111_001 has no timezone; expansion falls back to
      // the original local-zone stamping so already-placed RSVPs don't shift.
      final e = EventRecurrence(
        startsAt: DateTime.utc(2026, 4, 7, 13, 0, 0),
        freq: RecurrenceFreq.weekly,
      );
      final out = expandInstances(
        e,
        DateTime.utc(2026, 4, 1),
        DateTime.utc(2026, 4, 30, 23, 59, 59),
      );
      expect(out, hasLength(4));
      final localStart = e.startsAt.toLocal();
      for (final inst in out) {
        expect(inst.hour, localStart.hour);
        expect(inst.isUtc, isFalse);
      }
    });
  });

  group('calendar-day stepping (DST parity with web)', () {
    String expansionSource() {
      final source = File('lib/recurrence.dart').readAsStringSync();
      final start = source.indexOf('List<DateTime> expandInstances(');
      final end = source.indexOf('DateTime? nextInstanceAfter(');
      return source.substring(start, end);
    }

    test('the instance walk steps civil day numbers, never an absolute Duration', () {
      // Regression guard for the biweekly-across-DST divergence. Dart's
      // add(Duration(days: n)) adds absolute 24-hour blocks, so across a
      // fall-back a local midnight lands at 23:00 the previous day, the local
      // calendar day repeats and every later offset shifts by one, flipping
      // the biweekly week parity. Verified against the old modules under
      // TZ=America/New_York for a legacy [SU] event over 2026-10-25 ->
      // 2026-11-30, where web gave Oct25,Nov8,Nov22 and Dart Oct25,Nov1,Nov15,
      // Nov29. The walk now counts integer days in the event's zone. This is a
      // SOURCE guard because CI runs in UTC, where no transition exists and a
      // behavioural test of the legacy path cannot fail.
      final body = expansionSource();
      expect(
        body.contains('for (var day = startDay; day <= lastScanDay; day++)'),
        isTrue,
        reason: 'The cursor must be a civil day number.',
      );
      expect(
        body.contains('Duration('),
        isFalse,
        reason: 'Absolute-Duration stepping of the cursor is the DST divergence.',
      );
    });

    test('every recurrence field is read through the event zone, never a DateTime getter', () {
      // startsAt is parsed from a +00:00 string, so it carries a UTC flag;
      // reading .weekday / .hour / .day off it (or off .toLocal()) picked the
      // clock by accident, which is how the monthly branch once shifted every
      // legacy instance by the viewer's offset and how the timezoned branch
      // read the organiser's chips on the UTC clock. Every field now comes
      // from the zone's offset.
      final body = expansionSource();
      expect(body.contains('zone.offset(startSecond)'), isTrue,
          reason: 'The start is read in the event zone.');
      for (final getter in ['.toLocal()', '.toUtc()', 'startsAt.weekday', 'startsAt.hour', 'startsAt.day']) {
        expect(body.contains(getter), isFalse, reason: '$getter reads a field off an ambient clock.');
      }
    });
  });

  // The sentence the phone renders on event detail, ported case for case from
  // the web mirror `apps/web/src/lib/social/recurrence.test.ts`. Both halves
  // hard-code the same English, the same ISO day ordering and the same ` · `
  // separator, and until this port only one of them was measured — so a
  // divergence would have shown a runner a different recurrence sentence on
  // the phone with nothing failing (decisions § 1444).
  group('describeRecurrence', () {
    test('null freq is "One-off event"', () {
      expect(describeRecurrence(null, const []), 'One-off event');
      expect(describeRecurrence(null, null), 'One-off event');
    });

    test('monthly is "Repeats monthly"', () {
      expect(describeRecurrence(RecurrenceFreq.monthly, null), 'Repeats monthly');
      expect(
        describeRecurrence(RecurrenceFreq.monthly, const [Weekday.mo]),
        'Repeats monthly',
      );
    });

    test('weekly with byday lists days in ISO order', () {
      // Even when input order is shuffled, output order is MO,TU,...,SU.
      expect(
        describeRecurrence(RecurrenceFreq.weekly, const [Weekday.we, Weekday.mo]),
        'Every week · Mon, Wed',
      );
    });

    test('biweekly without byday is bare', () {
      expect(describeRecurrence(RecurrenceFreq.biweekly, null), 'Every other week');
      expect(describeRecurrence(RecurrenceFreq.biweekly, const []), 'Every other week');
    });
  });
}
