// Client-side expansion of the enum-recurrence model used by Phase 2 events.
// Dart port of apps/web/src/lib/social/recurrence.ts. The two implementations must
// stay in sync so web and Android render the same instance timestamps for a
// given event row. See docs/architecture/decisions.md #10.

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

enum Weekday { mo, tu, we, th, fr, sa, su }

enum RecurrenceFreq { weekly, biweekly, monthly }

const _isoCodes = <Weekday, String>{
  Weekday.mo: 'MO',
  Weekday.tu: 'TU',
  Weekday.we: 'WE',
  Weekday.th: 'TH',
  Weekday.fr: 'FR',
  Weekday.sa: 'SA',
  Weekday.su: 'SU',
};

const _weekdayLabels = <Weekday, String>{
  Weekday.mo: 'Mon',
  Weekday.tu: 'Tue',
  Weekday.we: 'Wed',
  Weekday.th: 'Thu',
  Weekday.fr: 'Fri',
  Weekday.sa: 'Sat',
  Weekday.su: 'Sun',
};

Weekday? weekdayFromCode(String code) {
  for (final e in _isoCodes.entries) {
    if (e.value == code) return e.key;
  }
  return null;
}

String weekdayCode(Weekday w) => _isoCodes[w]!;
String weekdayLabel(Weekday w) => _weekdayLabels[w]!;

RecurrenceFreq? recurrenceFromString(String? s) {
  switch (s) {
    case 'weekly':
      return RecurrenceFreq.weekly;
    case 'biweekly':
      return RecurrenceFreq.biweekly;
    case 'monthly':
      return RecurrenceFreq.monthly;
    default:
      return null;
  }
}

abstract class _Zone {
  int offset(int ms);
}

class _UtcZone implements _Zone {
  const _UtcZone();
  @override
  int offset(int ms) => 0;
}

class _LocalZone implements _Zone {
  const _LocalZone();
  @override
  int offset(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms).timeZoneOffset.inMilliseconds;
}

class _NamedZone implements _Zone {
  final tz.Location location;
  const _NamedZone(this.location);
  @override
  int offset(int ms) => location.timeZone(ms).offset.inMilliseconds;
}

const _day = 86400000;

var _tzReady = false;

/// The zone a series expands in. The tz database is loaded on first use, so
/// every caller — the app, a background isolate, a test — gets it without an
/// init step it could forget. A name the database does not know expands in
/// UTC, as web does when `Intl` rejects it and as the SQL does.
_Zone _eventZone(String? name) {
  if (name == null) return const _LocalZone();
  if (name == 'UTC') return const _UtcZone();
  if (!_tzReady) {
    tzdata.initializeTimeZones();
    _tzReady = true;
  }
  try {
    return _NamedZone(tz.getLocation(name));
  } on tz.LocationNotFoundException {
    return const _UtcZone();
  }
}

int _floorDiv(int a, int b) => (a - a % b) ~/ b;

/// The instant a local wall-clock names: the earlier of two in a fall-back
/// overlap, the pre-transition offset (so a later wall time) in a gap.
int _wallToInstant(_Zone zone, int wall) {
  final before = zone.offset(wall - _day);
  final after = zone.offset(wall + _day);
  int? best;
  for (final o in [before, after]) {
    final t = wall - o;
    if (zone.offset(t) == o && (best == null || t < best)) best = t;
  }
  return best ?? wall - before;
}

int _isoDow(int day) => (day + 3) % 7 + 1;

class EventRecurrence {
  final DateTime startsAt;
  final RecurrenceFreq? freq;
  final List<Weekday>? byday;
  final DateTime? until;
  final int? count;

  /// IANA timezone the event's wall-clock is expressed in (events.timezone,
  /// migration 20270111_001). When non-null the series expands on that zone's
  /// wall-clock, identically for every viewer; null (legacy rows) expands in
  /// the device's zone. See [expandInstances].
  final String? timezone;

  const EventRecurrence({
    required this.startsAt,
    this.freq,
    this.byday,
    this.until,
    this.count,
    this.timezone,
  });
}

/// Expand a recurrence into instance start times within [from, to]. Returns
/// `[startsAt]` for non-recurring events if it's in-window, else `[]`.
///
/// A recurring instance's start is its per-occurrence capacity key
/// (20261018_001) and live-race arm key, so every viewer must compute the
/// identical instant. An occurrence is a LOCAL date in the event's own zone: a
/// weekday in `byday` (else startsAt's local weekday), biweekly counted in
/// local weeks from the local Monday of startsAt, monthly on startsAt's local
/// day-of-month clamped to the month's end, stamped at startsAt's local time
/// of day. A wall-clock inside a spring-forward gap moves forward by the gap;
/// one inside a fall-back overlap takes the EARLIER instant (RFC 5545). The
/// occurrence on startsAt's own local date is startsAt, to the second. A
/// legacy series with no timezone expands in the DEVICE's zone, as it always
/// has. Mirrors apps/web/src/lib/social/recurrence.ts and the SQL
/// private.event_occurrences / private.is_event_occurrence (decisions § 1918).
///
/// A timezoned instance is a UTC `DateTime`; a legacy one is a LOCAL
/// `DateTime` naming the same absolute instant web's `new Date(...)` does.
/// That stops being fine at SERIALISATION, because `toIso8601String()` writes
/// no zone designator for a local `DateTime` where JS's `toISOString()` always
/// emits `Z` — so the wire form is normalised at the boundary that owns it
/// (`instanceStartKey` in `api_client`), not here (decisions § 1343), and
/// enforced by `test/instance_start_wire_guard_test.dart` over the whole of
/// `lib/` (decisions § 1379).
List<DateTime> expandInstances(
  EventRecurrence e,
  DateTime from,
  DateTime to, {
  int max = 100,
}) {
  if (e.freq == null) {
    return (e.startsAt.compareTo(from) >= 0 && e.startsAt.compareTo(to) <= 0)
        ? [e.startsAt]
        : [];
  }
  final zone = _eventZone(e.timezone);
  final asUtc = e.timezone != null;
  DateTime instant(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: asUtc);
  final hardCap = e.count ?? 1 << 30;
  final results = <DateTime>[];
  // Every instant is rebuilt from whole seconds, so a startsAt carrying a
  // sub-second part is compared, and stands as its own first occurrence, at
  // that resolution. `%` is floor-based for a positive divisor, so a pre-epoch
  // startsAt truncates downward too.
  final startSecond = e.startsAt.millisecondsSinceEpoch -
      e.startsAt.millisecondsSinceEpoch % 1000;
  final startLocal = startSecond + zone.offset(startSecond);
  final startDay = _floorDiv(startLocal, _day);
  final timeOfDay = startLocal - startDay * _day;
  int stamp(int day) =>
      day == startDay ? startSecond : _wallToInstant(zone, day * _day + timeOfDay);
  int localDay(DateTime t) {
    final ms = t.millisecondsSinceEpoch;
    return _floorDiv(ms + zone.offset(ms), _day);
  }

  // The walk always starts at startsAt (occurrences before [from] still count
  // toward `count`), so its budget has to reach the far end of the requested
  // window, not [max] periods past the start.
  final scanEnd = (e.until != null && e.until!.isBefore(to)) ? e.until! : to;

  var produced = 0;
  if (e.freq == RecurrenceFreq.monthly) {
    // Each instance is `i` whole months from start with the day clamped to the
    // target month's last day (Jan-31 → Feb-28/29). Stepping a running cursor
    // would let a clamp permanently shrink the day-of-month.
    final s = DateTime.fromMillisecondsSinceEpoch(startDay * _day, isUtc: true);
    final end = DateTime.fromMillisecondsSinceEpoch(localDay(scanEnd) * _day, isUtc: true);
    final monthBudget = (end.year - s.year) * 12 + (end.month - s.month) + 1;
    for (var i = 0; produced < hardCap; i++) {
      if (i > monthBudget) break;
      final total = s.month - 1 + i;
      final year = s.year + _floorDiv(total, 12);
      final month = total % 12 + 1;
      final lastDay = DateTime.utc(year, month + 1, 0).day;
      final day = DateTime.utc(year, month, s.day < lastDay ? s.day : lastDay)
              .millisecondsSinceEpoch ~/
          _day;
      final cursor = instant(stamp(day));
      if (e.until != null && cursor.isAfter(e.until!)) break;
      // count caps TOTAL occurrences from startsAt, not the ones inside
      // [from, to].
      produced++;
      if (cursor.isAfter(to)) break;
      if (!cursor.isBefore(from)) {
        results.add(cursor);
        if (results.length >= max) break;
      }
    }
    return results;
  }

  final stepWeeks = e.freq == RecurrenceFreq.biweekly ? 2 : 1;
  final byday = (e.byday == null || e.byday!.isEmpty)
      ? [weekdayChoices[_isoDow(startDay) - 1]]
      : e.byday!;
  // Weeks are counted from the local Monday of startsAt's week, matching web
  // and the SQL. The cursor is a civil day number, so a DST change can never
  // repeat or skip a calendar day.
  final anchor = startDay - (_isoDow(startDay) - 1);
  final lastScanDay = localDay(scanEnd) + 1;
  for (var day = startDay; day <= lastScanDay; day++) {
    if (_floorDiv(day - anchor, 7) % stepWeeks != 0) continue;
    if (!byday.contains(weekdayChoices[_isoDow(day) - 1])) continue;

    final stamped = instant(stamp(day));
    if (e.until != null && stamped.isAfter(e.until!)) continue;
    if (stamped.isAfter(to)) continue;
    if (stamped.millisecondsSinceEpoch < startSecond) continue;

    // Every real occurrence counts toward count, in-window or not, and the cap
    // is checked BEFORE counting so a stored count of 0 yields no occurrence
    // (decisions § 1910).
    if (produced >= hardCap) break;
    produced++;
    if (!stamped.isBefore(from)) {
      results.add(stamped);
      if (results.length >= max) break;
    }
  }
  return results;
}

DateTime? nextInstanceAfter(EventRecurrence e, [DateTime? after]) {
  final start = after ?? DateTime.now();
  // elapsed-time: a ten-year search horizon, mirroring web's
  // `after.getTime() + 10 * 365 * 24 * 3600 * 1000`.
  final tenYears = start.add(const Duration(days: 365 * 10));
  final xs = expandInstances(e, start, tenYears, max: 1);
  return xs.isEmpty ? null : xs.first;
}

String describeRecurrence(RecurrenceFreq? freq, List<Weekday>? byday) {
  if (freq == null) return 'One-off event';
  if (freq == RecurrenceFreq.monthly) return 'Repeats monthly';
  final days = (byday == null || byday.isEmpty)
      ? ''
      : [Weekday.mo, Weekday.tu, Weekday.we, Weekday.th, Weekday.fr, Weekday.sa, Weekday.su]
          .where(byday.contains)
          .map(weekdayLabel)
          .join(', ');
  final base = freq == RecurrenceFreq.biweekly ? 'Every other week' : 'Every week';
  return days.isEmpty ? base : '$base · $days';
}

const weekdayChoices = <Weekday>[
  Weekday.mo,
  Weekday.tu,
  Weekday.we,
  Weekday.th,
  Weekday.fr,
  Weekday.sa,
  Weekday.su,
];
