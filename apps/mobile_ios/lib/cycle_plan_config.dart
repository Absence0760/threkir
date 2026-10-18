import 'package:api_client/api_client.dart' show SettingsKeys;

import 'cycle_plan.dart';
import 'cycle_plan_flag.dart';
import 'settings_sync.dart' show activeSetting;

/// The runner's cycle / pregnancy settings as a [CyclePlanConfig], or null
/// when they are unset or incomplete. [read] returns one setting's raw value.
/// Web twin: the settings read on `/plans/[id]` behind
/// `isCyclePlansEnabled()`. These are GDPR Art 9 values, so the caller reads
/// them only under `cyclePlansGate` (decisions § 231); they exist only when
/// health-data consent was given.
CyclePlanConfig? cyclePlanConfigFrom(Object? Function(String key) read) {
  final mode = read(SettingsKeys.cycleTrackingMode);
  if (mode == 'cycle') {
    final len = read(SettingsKeys.cycleLengthDays);
    final last = read(SettingsKeys.cycleLastPeriodStart);
    if (len is num && len > 0 && last is String && last.isNotEmpty) {
      return CyclePlanConfig.cycle(
          cycleLengthDays: len.toInt(), lastPeriodStartIso: last);
    }
  } else if (mode == 'pregnancy') {
    final due = read(SettingsKeys.pregnancyDueDate);
    if (due is String && due.isNotEmpty) {
      return CyclePlanConfig.pregnancy(dueDateIso: due);
    }
  }
  return null;
}

/// The adjustment's config as plan detail reads it: null without reading a
/// single Art 9 setting while the cycle-plans gate is off (decisions § 231),
/// else [cyclePlanConfigFrom] over the synced settings. [gate] and [read] are
/// test seams.
CyclePlanConfig? readCyclePlanConfig({
  bool Function()? gate,
  Object? Function(String key)? read,
}) {
  if (!(gate ?? () => cyclePlansGate)()) return null;
  return cyclePlanConfigFrom(read ?? activeSetting);
}
