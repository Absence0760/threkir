/// The `time_zone` universal pref (docs/backend/settings.md): the runner's
/// IANA zone, read server-side by `coach_roster_summary` so a coach's roster
/// picks the athlete's current plan by the athlete's local date (issue
/// #1182). Written from the device zone on sign-in by
/// `SettingsSyncService`, and only when it differs from what is stored.
///
/// Dart twin of `apps/web/src/lib/settings/time_zone.ts` — keep
/// `timeZoneToWrite` and the test counts in lockstep.
library;

/// The zone to write, or null when nothing needs writing: the device zone is
/// unknown or blank, or the bag already holds it.
String? timeZoneToWrite(Object? stored, String? device) {
  final tz = device?.trim();
  if (tz == null || tz.isEmpty) return null;
  return stored == tz ? null : tz;
}
