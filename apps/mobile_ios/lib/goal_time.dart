/// Goal-time text parsing shared by every surface that asks for an elapsed
/// race/goal time (the run screen's race-strategy sheet, the roadbook's
/// goal field). One parser so "3:30" cannot mean three-and-a-half hours on
/// one screen and three-and-a-half minutes on another.
library;

import 'plan_races.dart' show raceGoalMaxHours;

/// Parse a goal-time string. Accepts h:mm:ss, h:mm, mm:ss, or bare
/// minutes. A two-part value is ambiguous ("3:30" the marathon vs
/// "25:00" the 5K); when [distanceM] is known the reading whose implied
/// pace is plausible for running (2:30–25:00 min/km) wins, preferring
/// the hours reading when both fit.
int? parseGoalTimeS(String raw, {double? distanceM}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(':');
  if (parts.length > 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null || n < 0) return null;
    nums.add(n);
  }
  switch (nums.length) {
    case 1:
      return nums[0] > 0 ? nums[0] * 60 : null;
    case 3:
      final s = nums[0] * 3600 + nums[1] * 60 + nums[2];
      return s > 0 ? s : null;
    default:
      final asHours = nums[0] * 3600 + nums[1] * 60;
      final asMinutes = nums[0] * 60 + nums[1];
      if (distanceM != null && distanceM > 0) {
        bool plausible(int t) {
          if (t <= 0) return false;
          final pace = t / (distanceM / 1000);
          return pace >= 150 && pace <= 1500;
        }

        if (plausible(asHours)) return asHours;
        if (plausible(asMinutes)) return asMinutes;
      }
      return asHours > 0 ? asHours : null;
  }
}

/// h:mm:ss (or mm:ss under an hour) — round-trips through [parseGoalTimeS].
String formatGoalTimeS(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// A plan race's goal time, always h:mm:ss — a sub-hour goal included
/// ("0:45:00") — so the race field's prefill reads back through
/// [parseRaceGoalTimeS] unchanged whether or not the race has a distance.
String formatRaceGoalTimeS(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(sec)}';
}

/// Parse a plan race's goal time: exactly h:mm:ss, hours 0–[raceGoalMaxHours]
/// (a 240-mile race runs past 100 hours), minutes and seconds 0–59. No pace
/// guess and no two-part form, because a race may have no distance to
/// disambiguate "45:00" with.
int? parseRaceGoalTimeS(String raw) {
  final m = RegExp(r'^(\d{1,3}):(\d{2}):(\d{2})$').firstMatch(raw.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final sec = int.parse(m.group(3)!);
  if (h > raceGoalMaxHours || min > 59 || sec > 59) return null;
  final s = h * 3600 + min * 60 + sec;
  return s > 0 ? s : null;
}
