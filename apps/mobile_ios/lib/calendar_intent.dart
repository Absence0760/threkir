/// Hands a club event to the phone's own calendar.
///
/// Web downloads an RFC 5545 `.ics` file (decisions § 599) because a browser
/// has nothing else to hand it to. A phone has an OS calendar, so the mirror is
/// the platform hand-off — `ACTION_INSERT` on `CalendarContract.Events` on
/// Android, `EKEventEditViewController` on iOS — and the `.ics` text builder
/// owes no Dart twin (§ 24).
///
/// The series crosses the channel as an RRULE value because both platforms
/// already speak that grammar: Android stores it verbatim in `Events.RRULE`,
/// iOS maps it onto an `EKRecurrenceRule`. One representation means one
/// shaping and one place for it to be wrong.
///
/// [buildRrule] mirrors web's `buildRrule` decision for decision, including its
/// refusal to state a monthly series anchored past the 28th. Web's guards for
/// an unparseable UNTIL and a non-integer COUNT have no analogue here — a
/// `DateTime` and an `int` cannot arrive in those states.
///
/// The stored recurrence fields are wall-clock in the event's own zone, so the
/// rule restates them in that zone and the zone crosses the channel with it
/// (decisions § 1919): the platform expands BYDAY on the event's local
/// weekdays and keeps the local time of day across DST, as the app does.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'event_occurrence.dart';
import 'recurrence.dart';

@visibleForTesting
const MethodChannel calendarChannel = MethodChannel('run_app/calendar');

/// RFC 5545 BYDAY ordering, so the same weekday set always renders the same
/// rule string.
const List<Weekday> _rruleWeekdayOrder = [
  Weekday.mo,
  Weekday.tu,
  Weekday.we,
  Weekday.th,
  Weekday.fr,
  Weekday.sa,
  Weekday.su,
];

/// How far ahead cancelled occurrences are counted for the surface's note —
/// the same one-year horizon the occurrence picker expands over.
const Duration _cancellationHorizon = Duration(days: 365);

/// The whole series restated in the terms a platform recurrence rule needs.
class CalendarSeries {
  /// The rule's first occurrence. RFC 5545 § 3.8.5.3 requires the start to be a
  /// member of the recurrence set and `startsAt` need not be (a Tuesday-created
  /// Saturday series), so this is the first date in the event's zone that
  /// carries one of its weekdays, at `startsAt`'s local time of day.
  final DateTime anchor;

  /// The RRULE value, with no `RRULE:` prefix. Its weekdays and day of the
  /// month are read in [timeZone].
  final String rrule;

  /// The IANA zone the platform must expand [rrule] in — the event's own. Null
  /// for a legacy series with no stored zone, which the app expands on the
  /// viewer's clock and so the device calendar's default zone matches.
  final String? timeZone;

  /// Called-off occurrences within the next year. Neither `ACTION_INSERT`'s
  /// extras nor `EKRecurrenceRule` carry exception dates, so the hand-off
  /// cannot subtract these the way web's `EXDATE` does — the surface says so
  /// rather than letting the calendar quietly disagree with the club page.
  final List<DateTime> unsubtractedCancellations;

  const CalendarSeries({
    required this.anchor,
    required this.rrule,
    required this.timeZone,
    required this.unsubtractedCancellations,
  });
}

/// Render a recurrence as an RRULE value, or null when it cannot be stated
/// faithfully.
///
/// The one shape that fails is a monthly series anchored after the 28th:
/// [expandInstances] clamps a missing day-of-month to the month's last day
/// (Jan 31 -> Feb 28) and BYMONTHDAY has no clamp — it skips the short month
/// outright. A calendar that disagrees with the club page about which dates the
/// club is meeting is worse than no calendar entry.
String? buildRrule({
  required RecurrenceFreq freq,
  List<Weekday> byday = const [],
  int? monthDay,
  int? count,
  DateTime? until,
}) {
  final parts = <String>[];

  if (freq == RecurrenceFreq.monthly) {
    if (monthDay == null || monthDay < 1 || monthDay > 28) return null;
    parts.add('FREQ=MONTHLY');
  } else {
    parts.add('FREQ=WEEKLY');
    if (freq == RecurrenceFreq.biweekly) parts.add('INTERVAL=2');
  }

  // RFC 5545 § 3.3.10 forbids UNTIL and COUNT in one rule.
  if (count != null) {
    if (count < 1) return null;
    parts.add('COUNT=$count');
  } else if (until != null) {
    parts.add('UNTIL=${_rruleUtc(until)}');
  }

  if (freq == RecurrenceFreq.monthly) {
    parts.add('BYMONTHDAY=$monthDay');
  } else if (byday.isNotEmpty) {
    final ordered = [
      for (final w in _rruleWeekdayOrder)
        if (byday.contains(w)) weekdayCode(w),
    ];
    if (ordered.isEmpty) return null;
    parts.add('BYDAY=${ordered.join(',')}');
  }

  return parts.join(';');
}

/// The series of [e] as a platform recurrence rule, or null for a one-off event
/// and for a series the rule grammar cannot state exactly.
CalendarSeries? calendarSeriesFor(
  EventRecurrence e, {
  Iterable<DateTime> cancelled = const [],
  DateTime? now,
}) {
  final freq = e.freq;
  if (freq == null) return null;

  final _Clock clock;
  if (e.timezone == null) {
    clock = const _DeviceClock();
  } else {
    final location = _location(e.timezone!);
    if (location == null) return null;
    clock = _ZoneClock(location);
  }

  final start = clock.read(_wholeSecond(e.startsAt));
  final stored = e.byday ?? const <Weekday>[];
  final byday = stored.isNotEmpty
      ? [
          for (final w in _rruleWeekdayOrder)
            if (stored.contains(w)) w,
        ]
      : [_rruleWeekdayOrder[start.weekday - 1]];

  final anchorDay = freq == RecurrenceFreq.monthly
      ? start
      : _firstSeriesDay(freq, byday, start);
  if (anchorDay == null) return null;
  final anchor = clock.stamp(anchorDay, start);
  // A start in the second pass of a fall-back hour is its own first
  // occurrence, but a zoned reading names the first pass, so no rule anchored
  // on the platform's wall clock can state it.
  if (anchor.isBefore(_wholeSecond(e.startsAt))) return null;
  final until = e.until;
  if (until != null && anchor.isAfter(until)) return null;

  final end = _resolveSeriesEnd(e);
  final rrule = buildRrule(
    freq: freq,
    byday: freq == RecurrenceFreq.monthly ? const [] : byday,
    monthDay: freq == RecurrenceFreq.monthly ? start.day : null,
    count: end.count,
    until: end.until,
  );
  if (rrule == null) return null;

  final from = now ?? DateTime.now();
  final ahead = expandInstances(e, from, from.add(_cancellationHorizon));
  return CalendarSeries(
    anchor: anchor,
    rrule: rrule,
    timeZone: e.timezone,
    unsubtractedCancellations: [
      for (final d in ahead)
        if (isOccurrenceCancelled(cancelled, d)) d,
    ],
  );
}

/// The first date on or after [start]'s date carrying one of [byday], counting
/// a fortnightly series in the even weeks from the Monday of [start]'s week.
DateTime? _firstSeriesDay(
  RecurrenceFreq freq,
  List<Weekday> byday,
  DateTime start,
) {
  final sinceMonday = start.weekday - 1;
  for (var offset = sinceMonday; offset < 35; offset++) {
    if (freq == RecurrenceFreq.biweekly && (offset ~/ 7).isOdd) continue;
    final day = DateTime.utc(start.year, start.month, start.day - sinceMonday + offset);
    if (byday.contains(_rruleWeekdayOrder[day.weekday - 1])) return day;
  }
  return null;
}

bool _tzReady = false;

tz.Location? _location(String name) {
  if (!_tzReady) {
    tzdata.initializeTimeZones();
    _tzReady = true;
  }
  // The bundled database carries `Etc/UTC` but not the bare `UTC` the
  // platforms and the web client report.
  if (name == 'UTC') return tz.UTC;
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

/// Reads an instant as wall-clock fields (returned in a UTC `DateTime` so the
/// fields are the reading itself) and turns a reading back into an instant.
abstract class _Clock {
  DateTime read(DateTime instant);

  /// The instant [day]'s date at [timeOfDay]'s time reads as.
  DateTime stamp(DateTime day, DateTime timeOfDay);
}

/// The event's own zone. A reading a spring-forward gap skips is taken with
/// the offset in force before the gap (02:30 -> 03:30), and one the fall-back
/// hour repeats takes the earlier instant — RFC 5545 § 3.3.5, which is how
/// the platform calendar will resolve the same reading.
class _ZoneClock implements _Clock {
  final tz.Location location;
  const _ZoneClock(this.location);

  int _offsetMs(int utcMs) => location.timeZone(utcMs).offset.inMilliseconds;

  @override
  DateTime read(DateTime instant) {
    final ms = instant.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(ms + _offsetMs(ms), isUtc: true);
  }

  @override
  DateTime stamp(DateTime day, DateTime timeOfDay) {
    final naive = DateTime.utc(
      day.year,
      day.month,
      day.day,
      timeOfDay.hour,
      timeOfDay.minute,
      timeOfDay.second,
    ).millisecondsSinceEpoch;
    const dayMs = 86400000;
    final before = _offsetMs(naive - dayMs);
    final after = _offsetMs(naive + dayMs);
    final matches = <int>{
      for (final o in {before, after})
        if (_offsetMs(naive - o) == o) naive - o,
    }.toList()
      ..sort();
    return DateTime.fromMillisecondsSinceEpoch(
      matches.isEmpty ? naive - before : matches.first,
      isUtc: true,
    );
  }
}

/// The device's own clock, for a legacy series with no stored zone — the clock
/// the app expands it on.
class _DeviceClock implements _Clock {
  const _DeviceClock();

  @override
  DateTime read(DateTime instant) {
    final l = instant.toLocal();
    return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second);
  }

  @override
  DateTime stamp(DateTime day, DateTime timeOfDay) => DateTime(
        day.year,
        day.month,
        day.day,
        timeOfDay.hour,
        timeOfDay.minute,
        timeOfDay.second,
      ).toUtc();
}

/// The app applies `until` and `count` together; a rule may carry only one.
/// Where both are set, count the real occurrences inside the until-bound so
/// whichever binds first survives the translation.
({int? count, DateTime? until}) _resolveSeriesEnd(EventRecurrence e) {
  final count = e.count;
  final until = e.until;
  if (count != null && until != null) {
    return (
      count:
          expandInstances(e, _wholeSecond(e.startsAt), until, max: count).length,
      until: null,
    );
  }
  return (count: count, until: until);
}

/// [expandInstances] stamps every occurrence at whole-second resolution, so a
/// `starts_at` carrying sub-second precision sorts strictly after its own first
/// occurrence — counting from the raw value silently drops it and states the
/// series one occurrence short.
DateTime _wholeSecond(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
      d.millisecondsSinceEpoch - d.millisecondsSinceEpoch % 1000,
      isUtc: d.isUtc,
    );

String _rruleUtc(DateTime d) {
  final u = d.toUtc();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${p2(u.month)}${p2(u.day)}'
      'T${p2(u.hour)}${p2(u.minute)}${p2(u.second)}Z';
}

/// Open the OS calendar's own new-event editor, pre-filled from the event —
/// one occurrence, or the whole series when [rrule] is set. [timeZone] is the
/// IANA zone the entry lives in, which is the zone the platform expands
/// [rrule] in; null leaves the calendar's default (the device zone).
///
/// Returns false when the editor could not be opened (no calendar app,
/// calendar access refused on iOS, no native handler) so the caller can say so.
/// Never throws: this is an L4 auxiliary effect hanging off the event page.
Future<bool> addToDeviceCalendar({
  required String title,
  required DateTime start,
  int? durationMin,
  String? description,
  String? location,
  String? url,
  String? rrule,
  String? timeZone,
}) async {
  final startUtc = start.toUtc();
  try {
    final opened = await calendarChannel.invokeMethod<bool>('addEvent', {
      'title': title,
      'startMs': startUtc.millisecondsSinceEpoch,
      if (durationMin != null && durationMin > 0)
        'endMs': startUtc
            .add(Duration(minutes: durationMin))
            .millisecondsSinceEpoch,
      'description': description,
      'location': location,
      'url': url,
      'rrule': rrule,
      'timeZone': timeZone,
    });
    return opened == true;
  } catch (e) {
    debugPrint('addToDeviceCalendar failed: $e');
    return false;
  }
}
