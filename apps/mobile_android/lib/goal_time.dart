/// Goal-time text parsing shared by every surface that asks for an elapsed
/// race/goal time (the run screen's race-strategy sheet, the roadbook's
/// goal field). One parser so "3:30" cannot mean three-and-a-half hours on
/// one screen and three-and-a-half minutes on another.
library;

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

/// Parse a race goal time that is always written in hours: h:mm:ss, or an
/// explicit h:mm. Unlike [parseGoalTimeS] there is no pace guess and no
/// bare-minutes form, so a field prefilled by [formatGoalTimeS] reads back
/// as the value it was filled with whether or not the race has a distance.
int? parseRaceGoalTimeS(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    final t = p.trim();
    if (t.isEmpty || !RegExp(r'^\d+$').hasMatch(t)) return null;
    nums.add(int.parse(t));
  }
  if (nums.skip(1).any((n) => n > 59)) return null;
  final s = nums[0] * 3600 + nums[1] * 60 + (nums.length == 3 ? nums[2] : 0);
  return s > 0 ? s : null;
}

/// Always h:mm:ss, a sub-hour time included ("0:45:00"), so the output is
/// three-part and reads back exactly through both [parseGoalTimeS] and
/// [parseRaceGoalTimeS]. A two-part "45:00" would be read as 45 hours
/// wherever no distance disambiguates it.
String formatGoalTimeS(int s) {
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(sec)}';
}
