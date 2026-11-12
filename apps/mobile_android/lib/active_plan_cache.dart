import 'dart:convert';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kActivePlanCacheKey = 'active_plan_overview_v1';

/// The rows behind the last active-plan overview that loaded, so Home, the
/// Run tab and the dashboard still know today's workout without signal.
///
/// Rows, not the overview: today's workout, the completion figure and the
/// current week are derived again at read time, so a copy saved yesterday
/// still names today's session.
class ActivePlanSnapshot {
  final List<TrainingPlanRow> activePlans;
  final ({
    TrainingPlanRow? plan,
    List<PlanWeekRow> weeks,
    List<PlanWorkoutRow> workouts,
  })? detail;

  const ActivePlanSnapshot({required this.activePlans, required this.detail});
}

/// Saves [snapshot] for [userId], replacing any earlier copy. Best effort: a
/// failed write leaves the previous copy, which is only ever a fallback.
Future<void> writeActivePlanCache(
    String userId, ActivePlanSnapshot snapshot) async {
  try {
    final d = snapshot.detail;
    final blob = jsonEncode({
      'user_id': userId,
      'active_plans': [for (final p in snapshot.activePlans) p.toJson()],
      'detail': d == null
          ? null
          : {
              'plan': d.plan?.toJson(),
              'weeks': [for (final w in d.weeks) w.toJson()],
              'workouts': [for (final w in d.workouts) w.toJson()],
            },
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kActivePlanCacheKey, blob);
  } catch (e) {
    debugPrint('active plan cache write failed: $e');
  }
}

/// The copy saved for [userId], or null when there is none, it belongs to
/// another account, or it no longer parses.
Future<ActivePlanSnapshot?> readActivePlanCache(String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kActivePlanCacheKey);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['user_id'] != userId) return null;
    List<Map<String, dynamic>> rows(Object? v) =>
        (v as List).cast<Map<String, dynamic>>();
    final d = j['detail'] as Map<String, dynamic>?;
    return ActivePlanSnapshot(
      activePlans: rows(j['active_plans']).map(TrainingPlanRow.fromJson).toList(),
      detail: d == null
          ? null
          : (
              plan: d['plan'] == null
                  ? null
                  : TrainingPlanRow.fromJson(d['plan'] as Map<String, dynamic>),
              weeks: rows(d['weeks']).map(PlanWeekRow.fromJson).toList(),
              workouts: rows(d['workouts']).map(PlanWorkoutRow.fromJson).toList(),
            ),
    );
  } catch (e) {
    debugPrint('active plan cache read failed: $e');
    return null;
  }
}

/// Drops the saved copy. Called on sign-out: nothing of the departing
/// account may be readable by the next one.
Future<void> clearActivePlanCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kActivePlanCacheKey);
  } catch (e) {
    debugPrint('active plan cache clear failed: $e');
  }
}
