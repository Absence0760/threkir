/// The field sets the two plan publishers copy off a source plan onto the
/// template they insert. One definition, two callers.
///
/// `TrainingService.publishPlanToLibrary` (public library) and
/// `publishPlanAsTemplate` (club) each built their rows inline and had both
/// fallen behind the schema: every published workout lost its
/// `target_pace_end_sec_per_km`, `pace_zone` and `race_taper_applied_at`, and
/// the library head lost `source` and `rules`. Web twin:
/// `apps/web/src/lib/core/plan_copy.ts` — keep the field lists alike.
///
/// Pure and Supabase-free so `test/plan_copy_test.dart` can hold the lists
/// against the generated row classes.
library;

import 'package:core_models/core_models.dart'
    show PlanWeekRow, PlanWorkoutRow, TrainingPlanRow;

import 'training.dart' show toIsoDate;

/// Plan-design fields carried from the source plan onto the template head.
///
/// Deliberately absent: `vdot`, `current_5k_seconds` and `notes` are the
/// publisher's private fields, stripped on publish (each caller writes them
/// null, and the trigger in migration 20270508_001 enforces it). `status`,
/// `is_template`, `is_public_template`, `club_id` and `parent_template_id`
/// make the row a template, so each caller states them itself.
Map<String, Object?> planHeadCopyFields(TrainingPlanRow src) => {
      'name': src.name,
      'goal_event': src.goalEvent,
      'goal_distance_m': src.goalDistanceM,
      'goal_time_seconds': src.goalTimeSeconds,
      'start_date': toIsoDate(src.startDate),
      'end_date': toIsoDate(src.endDate),
      'days_per_week': src.daysPerWeek,
      'source': src.source,
      'rules': src.rules,
    };

List<Map<String, Object?>> planWeekCopyRows(
        List<PlanWeekRow> weeks, String planId) =>
    [
      for (final w in weeks)
        {
          'plan_id': planId,
          'week_index': w.weekIndex,
          'phase': w.phase,
          'target_volume_m': w.targetVolumeM,
          'notes': w.notes,
        },
    ];

/// Every workout whose week made it into the new plan. A workout whose week
/// has no mapping is dropped rather than orphaned: `week_id` is a NOT NULL FK.
///
/// Completion state (`completed_at`, `completed_run_id`,
/// `manually_completed`, `skipped_at`) is not copied — a template starts
/// fresh. The race fields and the taper stamp are: a B race is part of the
/// design, and an eased workout without its stamp would be cut again by the
/// cloner's next taper (decisions § 2063). The RPE range is carried; the bpm
/// range never is: a heart-rate target is one person's Art 9 prescription and
/// the database refuses one on a template (decisions § 2092).
List<Map<String, Object?>> planWorkoutCopyRows(
  List<PlanWorkoutRow> workouts,
  Map<String, String> newWeekIdByOldId,
) =>
    [
      for (final w in workouts)
        if (newWeekIdByOldId[w.weekId] case final weekId?)
          {
            'week_id': weekId,
            'scheduled_date': toIsoDate(w.scheduledDate),
            'kind': w.kind,
            'target_distance_m': w.targetDistanceM,
            'target_duration_seconds': w.targetDurationSeconds,
            'target_pace_sec_per_km': w.targetPaceSecPerKm,
            'target_pace_end_sec_per_km': w.targetPaceEndSecPerKm,
            'target_pace_tolerance_sec': w.targetPaceToleranceSec,
            'pace_zone': w.paceZone,
            'structure': w.structure,
            'notes': w.notes,
            'race_name': w.raceName,
            'race_priority': w.racePriority,
            'race_taper_applied_at': w.raceTaperAppliedAt?.toIso8601String(),
            'target_rpe_min': w.targetRpeMin,
            'target_rpe_max': w.targetRpeMax,
          },
    ];
