// Mirrors apps/web/src/lib/core/plan_copy.test.ts: the field lists both plan
// publishers copy, held against the generated row classes so a new column is
// either copied or excused, never silently dropped.
import 'dart:io';

import 'package:core_models/core_models.dart'
    show PlanWeekRow, PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_copy.dart';

final _sourcePlan = TrainingPlanRow(
  id: 'plan-1',
  userId: 'author',
  name: 'Autumn marathon',
  goalEvent: 'distance_full',
  goalDistanceM: 42195,
  goalTimeSeconds: 12600,
  startDate: DateTime(2026, 1, 4),
  endDate: DateTime(2026, 4, 19),
  daysPerWeek: 5,
  vdot: 52.4,
  current5kSeconds: 1140,
  status: 'active',
  notes: 'left knee ITB flare',
  createdAt: DateTime.utc(2025, 12, 1),
  updatedAt: DateTime.utc(2025, 12, 2),
  source: 'generated',
  rules: [
    {'kind': 'cap_weekly_increase', 'pct': 10},
  ],
  isTemplate: false,
  parentTemplateId: 'tmpl-0',
  clubId: 'club-0',
  assignedByCoachId: 'coach-0',
  isPublicTemplate: false,
  trimmedAt: DateTime.utc(2026, 3, 1),
);

const _sourceWeek = PlanWeekRow(
  id: 'week-1',
  planId: 'plan-1',
  weekIndex: 0,
  phase: 'base',
  targetVolumeM: 48000,
  notes: 'ease in',
);

final _sourceWorkout = PlanWorkoutRow(
  id: 'wo-1',
  weekId: 'week-1',
  scheduledDate: DateTime(2026, 1, 6),
  kind: 'tempo',
  targetDistanceM: 12000,
  targetDurationSeconds: 3300,
  targetPaceSecPerKm: 265,
  targetPaceToleranceSec: 5,
  structure: const {'reps': 4, 'on_m': 1600},
  notes: '4x1600m at threshold',
  completedRunId: 'run-9',
  completedAt: DateTime.utc(2026, 1, 6, 9),
  paceZone: 'threshold',
  targetPaceEndSecPerKm: 250,
  manuallyCompleted: true,
  updatedBy: 'author',
  updatedAt: DateTime.utc(2026, 1, 6, 10),
  skippedAt: DateTime.utc(2026, 1, 7),
  raceName: null,
  racePriority: null,
  raceTaperAppliedAt: DateTime.utc(2026, 1, 2, 8),
  targetRpeMin: 7,
  targetRpeMax: 8,
  targetHrMinBpm: 160,
  targetHrMaxBpm: 172,
);

List<String> _missing(
        Map<String, Object?> row, Map<String, dynamic> copied, Set<String> excused) =>
    [
      for (final c in row.keys)
        if (!copied.containsKey(c) && !excused.contains(c)) c,
    ];

void main() {
  test('a published workout keeps every design field with its value', () {
    final [row] = planWorkoutCopyRows([_sourceWorkout], {'week-1': 'new-week-1'});
    expect(row, {
      'week_id': 'new-week-1',
      'scheduled_date': '2026-01-06',
      'kind': 'tempo',
      'target_distance_m': 12000.0,
      'target_duration_seconds': 3300,
      'target_pace_sec_per_km': 265,
      'target_pace_end_sec_per_km': 250,
      'target_pace_tolerance_sec': 5,
      'pace_zone': 'threshold',
      'structure': {'reps': 4, 'on_m': 1600},
      'notes': '4x1600m at threshold',
      'race_name': null,
      'race_priority': null,
      'race_taper_applied_at': '2026-01-02T08:00:00.000Z',
      'target_rpe_min': 7,
      'target_rpe_max': 8,
    });
  });

  test('a published race keeps its name and priority, an unstamped one no stamp', () {
    final race = PlanWorkoutRow.fromJson({
      ..._sourceWorkout.toJson(),
      'kind': 'race',
      'race_name': 'Two Oceans',
      'race_priority': 'B',
      'race_taper_applied_at': null,
    });
    final [row] = planWorkoutCopyRows([race], {'week-1': 'w'});
    expect([row['race_name'], row['race_priority'], row['race_taper_applied_at']],
        ['Two Oceans', 'B', null]);
  });

  test('a workout whose week did not make the copy is dropped, not orphaned', () {
    final absent = PlanWorkoutRow.fromJson(
        {..._sourceWorkout.toJson(), 'id': 'wo-2', 'week_id': 'week-absent'});
    final rows =
        planWorkoutCopyRows([_sourceWorkout, absent], {'week-1': 'new-week-1'});
    expect([for (final r in rows) r['week_id']], ['new-week-1']);
  });

  test('the published plan head keeps source and rules, and never the private fields', () {
    final head = planHeadCopyFields(_sourcePlan);
    expect(head['rules'], [
      {'kind': 'cap_weekly_increase', 'pct': 10},
    ]);
    expect(head['source'], 'generated');
    expect(head['start_date'], '2026-01-04');
    for (final col in ['vdot', 'current_5k_seconds', 'notes']) {
      expect(head.containsKey(col), isFalse, reason: col);
    }
  });

  test('a published week keeps its phase, volume and notes under the new plan id', () {
    expect(planWeekCopyRows([_sourceWeek], 'new-plan'), [
      {
        'plan_id': 'new-plan',
        'week_index': 0,
        'phase': 'base',
        'target_volume_m': 48000.0,
        'notes': 'ease in',
      },
    ]);
  });

  test('a published workout keeps its RPE range and never its bpm range', () {
    final [row] =
        planWorkoutCopyRows([_sourceWorkout], {'week-1': 'new-week-1'});
    expect([row['target_rpe_min'], row['target_rpe_max']], [7, 8]);
    expect(row.containsKey('target_hr_min_bpm'), isFalse);
    expect(row.containsKey('target_hr_max_bpm'), isFalse);
  });

  // Census: the requirement is every key the generated row class serialises,
  // which only changes when a migration does.
  test('every plan_workouts column is either copied on publish or excused', () {
    const excused = {
      'id', // server-generated on the new row
      'week_id', // remapped to the new week (copied under the same key)
      'completed_at', // completion state — a template starts fresh
      'completed_run_id', // points at the publisher's own run
      'manually_completed', // completion state
      'skipped_at', // completion state
      'updated_at', // server-maintained
      'updated_by', // server-maintained
      'target_hr_min_bpm', // Art 9, refused on a template (decisions § 2092)
      'target_hr_max_bpm', // Art 9, refused on a template (decisions § 2092)
    };
    final [copied] =
        planWorkoutCopyRows([_sourceWorkout], {'week-1': 'new-week-1'});
    expect(_missing(_sourceWorkout.toJson(), copied, excused), isEmpty);
    for (final col in excused.difference({'week_id'})) {
      expect(copied.containsKey(col), isFalse, reason: '$col rode along');
    }
  });

  test('every plan_weeks column is either copied on publish or excused', () {
    final [copied] = planWeekCopyRows([_sourceWeek], 'new-plan');
    expect(_missing(_sourceWeek.toJson(), copied, const {'id'}), isEmpty);
  });

  test('every training_plans column is either copied on publish or excused', () {
    const excused = {
      'id', // server-generated
      'user_id', // the publisher, stated by each caller
      'vdot', // publisher-private fitness proxy
      'current_5k_seconds', // publisher-private fitness proxy
      'notes', // publisher's own free text
      'status', // a template is always inserted completed
      'is_template', // what makes the row a template
      'is_public_template', // library vs club, stated by each caller
      'club_id', // library vs club, stated by each caller
      'parent_template_id', // a publish has no parent
      'assigned_by_coach_id', // not a property of the design
      'created_at', // server-maintained
      'updated_at', // server-maintained
      'trimmed_at', // the owner's plan state, not the design
    };
    expect(
        _missing(_sourcePlan.toJson(), planHeadCopyFields(_sourcePlan), excused),
        isEmpty);
  });

  test('both plan publishers shape their rows through plan_copy.dart', () {
    final source = File('lib/training_service.dart').readAsStringSync();
    for (final fn in ['publishPlanToLibrary', 'publishPlanAsTemplate']) {
      final start = source.indexOf('Future<String> $fn(');
      expect(start, greaterThan(0), reason: '$fn not found — rename it here too');
      final end = source.indexOf('\n  Future<', start + 1);
      final body = source.substring(start, end);
      for (final helper in [
        'planHeadCopyFields(',
        'planWeekCopyRows(',
        'planWorkoutCopyRows(',
      ]) {
        expect(body.contains(helper), isTrue, reason: '$fn must use $helper');
      }
    }
  });
}
