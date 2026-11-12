import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA zone name (`Europe/Berlin`) for server aggregates
/// that bucket by the runner's local day (`run_streaks_for_user`'s
/// `p_tz`, decisions § 471 / § 475). `DateTime.now().timeZoneName` is an
/// abbreviation (`CEST`) the server rejects, and a fixed UTC offset
/// buckets DST-era history onto different days than the on-device
/// display compute — so the platform zone id is the only honest source.
/// When the platform can't name one, degrade to `'UTC'` explicitly: the
/// same fallback web takes when `Intl` fails, still an all-time answer
/// over the right run set, just bucketed in UTC.
Future<String> deviceIanaTimeZone() async =>
    await deviceIanaTimeZoneOrNull() ?? 'UTC';

/// The device's IANA zone name, or null when the platform can't name one.
/// A club event is stamped with this (`events.timezone`) because its
/// recurrence is wall-clock in the organiser's zone (decisions § 1919), and
/// for that a guessed `'UTC'` would be worse than none: a row with no zone
/// keeps the legacy viewer-local expansion web gives the same failure.
Future<String?> deviceIanaTimeZoneOrNull() async {
  try {
    final id = (await FlutterTimezone.getLocalTimezone()).identifier;
    return id.isEmpty ? null : id;
  } catch (e) {
    debugPrint('deviceIanaTimeZone failed: $e');
    return null;
  }
}
