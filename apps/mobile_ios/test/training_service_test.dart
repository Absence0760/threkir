import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/training_service.dart';

void main() {
  // CI regression pin: TrainingService.fetchViewerGender is called
  // from `_PlanNewScreenState.initState`. When Supabase isn't
  // initialised (every widget test that doesn't boot the local
  // stack), the `_c` getter throws a StateError. A previous version
  // of `fetchViewerGender` only wrapped the network read in
  // try/catch, leaving the `_uid` -> `_c` access exposed — the
  // initState thus crashed the entire test. The fix moved the
  // try/catch to cover both, restoring the L4-best-effort contract.
  //
  // This test is the smallest possible reproducer: a default-
  // constructed TrainingService (no override, no Supabase.initialize)
  // returns null from fetchViewerGender instead of throwing.

  test(
    'fetchViewerGender returns null (no throw) when Supabase is uninitialised',
    () async {
      final svc = TrainingService();
      final g = await svc.fetchViewerGender();
      expect(g, isNull);
    },
  );

  // Same contract for the age read, which shares the profile fetch: both go
  // through `get_my_profile()` now (the direct column selects they replaced
  // are refused by the column lockdown, 20260707_001, so they could only ever
  // report "unset"), and both are awaited unblocking from the same initState.
  test(
    'fetchViewerAge returns null (no throw) when Supabase is uninitialised',
    () async {
      final svc = TrainingService();
      final a = await svc.fetchViewerAge();
      expect(a, isNull);
    },
  );

  group('planRunHistoryFromRows', () {
    final now = DateTime.utc(2026, 10, 17, 12);
    Map<String, dynamic> row(int daysAgo, double m, int s,
            {String type = 'run', String source = 'app', Map? metadata}) =>
        {
          'id': 'r$daysAgo',
          'started_at':
              now.subtract(Duration(days: daysAgo)).toIso8601String(),
          'distance_m': m,
          'duration_s': s,
          'activity_type': type,
          'source': source,
          'metadata': metadata,
        };

    test('every row counts toward volume; only recent qualifying runs are efforts',
        () {
      final h = planRunHistoryFromRows([
        row(2, 5000, 1800),
        row(3, 20000, 2400, type: 'cycle'),
        row(4, 5000, 1800, metadata: {'indoor': true}),
        row(120, 10000, 3600),
      ], now.millisecondsSinceEpoch);
      expect(h.runs, hasLength(4));
      expect(h.efforts, hasLength(1));
      expect(h.efforts.single.distanceM, 5000);
      expect(h.efforts.single.durationS, 1800);
      expect(h.efforts.single.ageDays, closeTo(2, 1e-9));
    });

    test('a row with no start time counts nowhere as an effort', () {
      final h = planRunHistoryFromRows([
        {'id': 'x', 'started_at': null, 'distance_m': 5000, 'duration_s': 1800},
      ], now.millisecondsSinceEpoch);
      expect(h.runs, hasLength(1));
      expect(h.efforts, isEmpty);
    });
  });

  group('planDetailFromRow', () {
    // A real `training_plans` row with its `plan_weeks(*, plan_workouts(*))`
    // embed, captured from the local stack and trimmed to two weeks of two
    // workouts — then reversed, because an embed is only ordered per parent.
    Map<String, dynamic> row() => jsonDecode(_embeddedPlan) as Map<String, dynamic>;

    test('splits the embed into plan, weeks and workouts, in plan order', () {
      final d = planDetailFromRow(row());
      expect(d.plan.name, 'Richmond Half 2026');
      expect(d.weeks.map((w) => w.weekIndex), [0, 1]);
      expect(d.workouts.map((w) => w.scheduledDate.toIso8601String().substring(0, 10)),
          ['2026-09-30', '2026-10-01', '2026-10-07', '2026-10-08']);
      expect(d.workouts.every((w) => d.weeks.any((wk) => wk.id == w.weekId)), isTrue);
    });

    test('leaves the caller\'s row untouched', () {
      final r = row();
      planDetailFromRow(r);
      expect(r.containsKey('plan_weeks'), isTrue);
      expect((r['plan_weeks'] as List).first, contains('plan_workouts'));
    });

    test('a plan with no weeks, or a week with no workouts, is empty not null', () {
      final noWeeks = row()..['plan_weeks'] = <dynamic>[];
      expect(planDetailFromRow(noWeeks).weeks, isEmpty);
      expect(planDetailFromRow(noWeeks).workouts, isEmpty);

      final emptyWeek = row();
      for (final w in emptyWeek['plan_weeks'] as List) {
        (w as Map<String, dynamic>)['plan_workouts'] = <dynamic>[];
      }
      final d = planDetailFromRow(emptyWeek);
      expect(d.weeks, hasLength(2));
      expect(d.workouts, isEmpty);
    });
  });
}

const _embeddedPlan = r'''
{
  "id": "a1a1eada-aaaa-0000-0000-000000000001",
  "user_id": "00000000-0000-0000-0000-000000000001",
  "name": "Richmond Half 2026",
  "goal_event": "distance_half",
  "goal_distance_m": 21097.5,
  "goal_time_seconds": 5700,
  "start_date": "2026-09-30",
  "end_date": "2026-12-22",
  "days_per_week": 5,
  "vdot": 52.0,
  "current_5k_seconds": 1320,
  "status": "active",
  "notes": "Goal race: Richmond Half Marathon, 2026-06-21.",
  "created_at": "2026-10-17T03:10:26.208153+00:00",
  "updated_at": "2026-10-17T03:13:28.353722+00:00",
  "source": "manual",
  "rules": [
    "80% of weekly mileage should be easy",
    "Never increase weekly volume more than 10% week-over-week",
    "Long run is non-negotiable \u2014 protect Sunday",
    "Sleep 8 hours through build weeks"
  ],
  "is_template": false,
  "parent_template_id": null,
  "club_id": null,
  "assigned_by_coach_id": null,
  "is_public_template": false,
  "trimmed_at": null,
  "plan_weeks": [
    {
      "id": "a0aa0002-0000-0000-0000-000000000002",
      "notes": null,
      "phase": "base",
      "plan_id": "a1a1eada-aaaa-0000-0000-000000000001",
      "week_index": 1,
      "plan_workouts": [
        {
          "id": "95535e98-0c37-4c75-b473-f279b842445e",
          "kind": "rest",
          "notes": null,
          "week_id": "a0aa0002-0000-0000-0000-000000000002",
          "pace_zone": null,
          "race_name": null,
          "structure": null,
          "skipped_at": null,
          "updated_at": "2026-10-17T03:10:26.208153+00:00",
          "updated_by": null,
          "completed_at": null,
          "race_priority": null,
          "scheduled_date": "2026-10-08",
          "completed_run_id": null,
          "target_distance_m": null,
          "manually_completed": false,
          "race_taper_applied_at": null,
          "target_pace_sec_per_km": null,
          "target_duration_seconds": null,
          "target_pace_tolerance_sec": null,
          "target_pace_end_sec_per_km": null
        },
        {
          "id": "acc8d833-12ea-4a17-8453-cded80e72575",
          "kind": "long",
          "notes": null,
          "week_id": "a0aa0002-0000-0000-0000-000000000002",
          "pace_zone": "E",
          "race_name": null,
          "structure": null,
          "skipped_at": null,
          "updated_at": "2026-10-17T03:10:26.208153+00:00",
          "updated_by": null,
          "completed_at": null,
          "race_priority": null,
          "scheduled_date": "2026-10-07",
          "completed_run_id": null,
          "target_distance_m": 15000.0,
          "manually_completed": false,
          "race_taper_applied_at": null,
          "target_pace_sec_per_km": 325,
          "target_duration_seconds": null,
          "target_pace_tolerance_sec": 20,
          "target_pace_end_sec_per_km": null
        }
      ],
      "target_volume_m": 45000.0
    },
    {
      "id": "a0aa0001-0000-0000-0000-000000000001",
      "notes": null,
      "phase": "base",
      "plan_id": "a1a1eada-aaaa-0000-0000-000000000001",
      "week_index": 0,
      "plan_workouts": [
        {
          "id": "3e9fed34-1bc5-4cef-8ea4-d5db70c2cbb1",
          "kind": "rest",
          "notes": null,
          "week_id": "a0aa0001-0000-0000-0000-000000000001",
          "pace_zone": null,
          "race_name": null,
          "structure": null,
          "skipped_at": null,
          "updated_at": "2026-10-17T03:10:26.208153+00:00",
          "updated_by": null,
          "completed_at": null,
          "race_priority": null,
          "scheduled_date": "2026-10-01",
          "completed_run_id": null,
          "target_distance_m": null,
          "manually_completed": false,
          "race_taper_applied_at": null,
          "target_pace_sec_per_km": null,
          "target_duration_seconds": null,
          "target_pace_tolerance_sec": null,
          "target_pace_end_sec_per_km": null
        },
        {
          "id": "6179d2e4-cd47-470d-a02e-9fbcd34519b1",
          "kind": "long",
          "notes": null,
          "week_id": "a0aa0001-0000-0000-0000-000000000001",
          "pace_zone": "E",
          "race_name": null,
          "structure": null,
          "skipped_at": null,
          "updated_at": "2026-10-17T03:10:26.208153+00:00",
          "updated_by": null,
          "completed_at": null,
          "race_priority": null,
          "scheduled_date": "2026-09-30",
          "completed_run_id": null,
          "target_distance_m": 12000.0,
          "manually_completed": false,
          "race_taper_applied_at": null,
          "target_pace_sec_per_km": 330,
          "target_duration_seconds": null,
          "target_pace_tolerance_sec": 20,
          "target_pace_end_sec_per_km": null
        }
      ],
      "target_volume_m": 40000.0
    }
  ]
}
''';
