import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_plan_cache.dart';
import 'backend_timeout.dart';
import 'comeback.dart' show kLayoffMaxDays;
import 'cycle_plan.dart';
import 'fitness.dart' show qualifyingRuns;
import 'offline_sync_store.dart' show parseServerTimestamp;
import 'plan_break.dart' show BreakChange;
import 'plan_bulk_ops.dart';
import 'plan_calibration.dart';
import 'plan_copy.dart';
import 'plan_current.dart';
import 'plan_race_date.dart' show RaceDateChange;
import 'plan_ramp.dart';
import 'plan_recap.dart' show PlanRecapRecord, PlanRecapRun;
import 'plan_repeat_week.dart' show RepeatWeekChange;
import 'plan_resume.dart';
import 'plan_week.dart';
import 'race_predictor.dart' show EffortForPrediction;
import 'relink_candidates.dart';
import 'settings_sync.dart' show activeSetting, updateActiveUniversal;
import 'training.dart';

/// The window the goal-time check reads efforts from: the same 90 days the
/// runner's fitness is taken from. Mirrors `GOAL_CHECK_WINDOW_DAYS` on web
/// `PlanEditor.svelte`.
const int kGoalCheckWindowDays = 90;

/// What the plan wizard reads off the runner's history: every run in the
/// window as [RunForVolume] (the ramp check and the break detection), and
/// the qualifying efforts of the last [kGoalCheckWindowDays] (the goal check).
class PlanRunHistory {
  final List<RunForVolume> runs;
  final List<EffortForPrediction> efforts;

  const PlanRunHistory({required this.runs, required this.efforts});
}

/// Rows of `runs` (id, started_at, distance_m, duration_s, activity_type,
/// source, metadata) to a [PlanRunHistory]. Efforts go through the same
/// [qualifyingRuns] gate the fitness card and race predictor use.
PlanRunHistory planRunHistoryFromRows(
    List<Map<String, dynamic>> rows, int nowMs) {
  final runs = <RunForVolume>[];
  final candidates = <Run>[];
  for (final r in rows) {
    final startedAt = r['started_at'] as String? ?? '';
    final distanceM = (r['distance_m'] as num?)?.toDouble();
    final activityType = r['activity_type'] as String?;
    runs.add(RunForVolume(
      startedAt: startedAt,
      distanceM: distanceM,
      activityType: activityType,
    ));
    final started = parseIsoStrictValue(startedAt);
    if (started == null ||
        nowMs - started.millisecondsSinceEpoch >
            kGoalCheckWindowDays * 86400000) {
      continue;
    }
    candidates.add(Run(
      id: r['id'] as String? ?? '',
      startedAt: started,
      duration: Duration(seconds: (r['duration_s'] as num?)?.round() ?? 0),
      distanceMetres: distanceM ?? 0,
      source: RunSource.values.firstWhere(
        (s) => s.name == r['source'],
        orElse: () => RunSource.app,
      ),
      metadata: {
        ...?(r['metadata'] as Map?)?.cast<String, dynamic>(),
        'activity_type': activityType,
      },
    ));
  }
  return PlanRunHistory(
    runs: runs,
    efforts: [
      for (final run in qualifyingRuns(candidates))
        EffortForPrediction(
          distanceM: run.distanceMetres,
          durationS: run.duration.inSeconds,
          ageDays: ((nowMs - run.startedAt.millisecondsSinceEpoch) / 86400000)
              .clamp(0, double.infinity)
              .toDouble(),
        ),
    ],
  );
}

/// View-model pairing a plan row with its current-week index + today's
/// workout + completion percentage. Used by the dashboard/Run-tab card.
class ActivePlanOverview {
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  final PlanWorkoutRow? todayWorkout;
  final int completionPct;
  final int currentWeekIndex;

  /// The next active plan queued after [plan], if any — the chained block a
  /// runner sees as "Up next".
  final TrainingPlanRow? upcomingPlan;

  const ActivePlanOverview({
    required this.plan,
    required this.weeks,
    required this.workouts,
    required this.todayWorkout,
    required this.completionPct,
    required this.currentWeekIndex,
    this.upcomingPlan,
  });
}

/// The race fields of a `race` plan workout, written together by
/// [TrainingService.updateWorkout]. A null [priority] leaves it to
/// `planRaces` (A on the plan's end date, C elsewhere).
typedef PlanWorkoutRaceFields = ({
  String? name,
  String? priority,
  int? goalTimeSec,
});

/// A workout's distance and pace targets, written together by
/// [TrainingService.updateWorkout]: a null field clears its column, so an
/// emptied field in the edit sheet removes the target instead of keeping it.
typedef PlanWorkoutTargets = ({double? distanceM, int? paceSecPerKm});

/// A workout's effort range (RPE 1..10) or heart-rate range (bpm), written
/// together by [TrainingService.updateWorkout]. Either end may be null, and a
/// null end clears its column (decisions § 2092).
typedef PlanWorkoutRange = ({int? min, int? max});

/// The `plan_workouts` patch [TrainingService.updateWorkout] sends. A null
/// argument leaves its column alone, except inside [race] and [targets]:
/// those write their columns as given, nulls included. A `rest` [kind]
/// clears every target (distance, pace, pace range, tolerance, zone and
/// structure), as web's `WorkoutEditor` does, so a day switched to rest
/// cannot keep the tempo it used to be. A [kind]
/// other than `race` clears the race name and priority instead, since the
/// table allows them only on race rows (23514 otherwise), and when the row
/// was a race ([fromKind]) it clears the race's goal time too, so a former
/// race does not keep its finish time as a duration target. Matches web's
/// `WorkoutEditor` save. [notes] is
/// trimmed and an empty result nulls the column, matching web's
/// `updatePlanWorkout`. [rpe] and [hr] write the effort and heart-rate
/// ranges as given; a null argument leaves them alone, which is how the
/// sheet keeps a bpm target it may not show (the deploy gate is off). A rest
/// day clears both, since the table allows neither on one.
Map<String, dynamic> planWorkoutPatch({
  String? kind,
  String? fromKind,
  PlanWorkoutTargets? targets,
  String? notes,
  PlanWorkoutRaceFields? race,
  PlanWorkoutRange? rpe,
  PlanWorkoutRange? hr,
}) {
  final patch = <String, dynamic>{};
  if (kind != null) patch[PlanWorkoutRow.colKind] = kind;
  if (kind != null && kind != 'race') {
    patch[PlanWorkoutRow.colRaceName] = null;
    patch[PlanWorkoutRow.colRacePriority] = null;
    if (fromKind == 'race') {
      patch[PlanWorkoutRow.colTargetDurationSeconds] = null;
    }
  } else if (race != null) {
    patch[PlanWorkoutRow.colRaceName] = TrainingService.trimToNull(race.name);
    patch[PlanWorkoutRow.colRacePriority] = race.priority;
    patch[PlanWorkoutRow.colTargetDurationSeconds] = race.goalTimeSec;
  }
  if (kind == 'rest') {
    patch[PlanWorkoutRow.colTargetDistanceM] = null;
    patch[PlanWorkoutRow.colTargetPaceSecPerKm] = null;
    patch[PlanWorkoutRow.colTargetPaceEndSecPerKm] = null;
    patch[PlanWorkoutRow.colTargetPaceToleranceSec] = null;
    patch[PlanWorkoutRow.colPaceZone] = null;
    patch[PlanWorkoutRow.colStructure] = null;
    patch[PlanWorkoutRow.colTargetRpeMin] = null;
    patch[PlanWorkoutRow.colTargetRpeMax] = null;
    patch[PlanWorkoutRow.colTargetHrMinBpm] = null;
    patch[PlanWorkoutRow.colTargetHrMaxBpm] = null;
  } else {
    if (targets != null) {
      patch[PlanWorkoutRow.colTargetDistanceM] = targets.distanceM;
      patch[PlanWorkoutRow.colTargetPaceSecPerKm] = targets.paceSecPerKm;
    }
    if (rpe != null) {
      patch[PlanWorkoutRow.colTargetRpeMin] = rpe.min;
      patch[PlanWorkoutRow.colTargetRpeMax] = rpe.max;
    }
    if (hr != null) {
      patch[PlanWorkoutRow.colTargetHrMinBpm] = hr.min;
      patch[PlanWorkoutRow.colTargetHrMaxBpm] = hr.max;
    }
  }
  if (notes != null) {
    patch[PlanWorkoutRow.colNotes] = TrainingService.trimToNull(notes);
  }
  return patch;
}

/// What creating or cloning a plan does to the active plans its window
/// overlaps, resolved by the server in the same transaction as the write
/// (decisions § 2050). [refuse] fails with [ActivePlanExistsError] so nothing
/// the runner did not name changes; [replace] marks them abandoned; [trim]
/// ends the one plan that started before the new plan on the day before it
/// starts. [name] is the RPC's `p_overlap` value.
enum PlanOverlapAction { refuse, replace, trim }

/// A plan row's window as ISO days, the accessors the pure plan helpers
/// (`plan_current.dart`, `plan_overlap.dart`) take.
String planRowStartIso(TrainingPlanRow p) => toIsoDate(p.startDate);
String planRowEndIso(TrainingPlanRow p) => toIsoDate(p.endDate);

/// The current plan among [activePlans] (see `plan_current.dart`), falling
/// back to the queued one when nothing has started yet. Null with no plans.
TrainingPlanRow? currentOrUpcomingPlan(
    List<TrainingPlanRow> activePlans, String todayIso) {
  final pick = pickCurrentPlan(activePlans, todayIso,
      start: planRowStartIso, end: planRowEndIso);
  return pick.current ?? pick.upcoming;
}

/// The current (else upcoming) plan among [activePlans] and the plans queued
/// after it, in date order: the season the Coach's "My season" reads.
List<TrainingPlanRow> currentSeasonPlans(
        List<TrainingPlanRow> activePlans, String todayIso) =>
    currentSeason(activePlans, todayIso,
        start: planRowStartIso, end: planRowEndIso);

/// The active plans a new `[startIso, endIso]` window overlaps.
List<TrainingPlanRow> overlappingActivePlans(
        List<TrainingPlanRow> activePlans, String startIso, String endIso) =>
    overlappingPlans(activePlans, startIso, endIso,
        start: planRowStartIso, end: planRowEndIso);

/// The ISO day before [iso] — the end date a trimmed plan takes.
String dayBeforeIso(String iso) {
  final d = parseIsoDate(iso);
  return toIsoDate(DateTime(d.year, d.month, d.day - 1));
}

bool _isOverlapViolation(Object e) =>
    e is PostgrestException && e.code == '23P01';

bool _isTrimBlocked(Object e) => e is PostgrestException && e.code == 'TR001';

/// [error] as a plan write should surface it: the overlap constraint's
/// refusal (23P01) becomes [ActivePlanExistsError], anything else is
/// returned unchanged. Web twin: `dbError`'s `PlanOverlapError` mapping in
/// `apps/web/src/lib/core/supabase_error.ts`.
Object planWriteError(Object error) =>
    _isOverlapViolation(error) ? const ActivePlanExistsError() : error;

/// A public-library plan paired with its author's public handle. The
/// browse + preview surfaces show the handle but never any other author
/// data. Mirrors web `core/data.ts:PublicPlanLibraryEntry`.
class PublicPlanLibraryEntry {
  final TrainingPlanRow plan;
  final String? authorHandle;

  const PublicPlanLibraryEntry({required this.plan, required this.authorHandle});
}

/// Thrown when an active plan already covers some of the dates a write would
/// activate — [TrainingService.resumePlan] up front, and either write when the
/// `training_plans_active_no_overlap` constraint rejects it (23P01) after a
/// concurrent change. Web twin: `ActivePlanExistsError` in
/// `apps/web/src/lib/core/data.ts`.
class ActivePlanExistsError implements Exception {
  const ActivePlanExistsError();

  @override
  String toString() => 'active_plan_exists';
}

/// A create or clone that chose [PlanOverlapAction.trim] was refused because
/// the plan it would end has completed workouts after the cut
/// (`trim_training_plan`'s SQLSTATE TR001, decisions § 2061). The whole
/// create rolled back, so nothing changed. [planName] names the plans a
/// follow-up lookup found in the way, comma-joined in start order, null
/// when that lookup failed or found none;
/// [trimEndIso] is the end date the trim would have given it.
class PlanTrimBlockedError implements Exception {
  final String? planName;
  final String trimEndIso;

  const PlanTrimBlockedError({required this.planName, required this.trimEndIso});

  @override
  String toString() => 'plan_trim_blocked';
}

/// A restart refused because the plan has a race on or after today
/// (`restart_training_plan`'s SQLSTATE RR001): moving the plan would move
/// race day off the real date. Nothing changed.
class PlanRestartRaceAheadError implements Exception {
  const PlanRestartRaceAheadError();

  @override
  String toString() => 'plan_restart_race_ahead';
}

/// A restart refused because its start is before the runner's today in their
/// stored time zone (`restart_training_plan`'s SQLSTATE RR002), which can be
/// ahead of the device's date the dialog checked against. Nothing changed.
class PlanRestartBeforeTodayError implements Exception {
  const PlanRestartBeforeTodayError();

  @override
  String toString() => 'plan_restart_before_today';
}

class TrainingService extends ChangeNotifier {
  final SupabaseClient? _override;

  TrainingService() : _override = null;

  /// Test-only DI seam mirroring `ApiClient.withClient` and
  /// `SocialService.withClient`. Production callsites use the unnamed
  /// constructor and resolve through the global; tests inject a
  /// real-but-local-loopback `SupabaseClient` so the Supabase-touching
  /// methods can be driven without booting `Supabase.initialize`.
  @visibleForTesting
  TrainingService.withClient(SupabaseClient client) : _override = client;

  Listenable? _runsLanded;

  /// Notifies this service's listeners whenever [runsLanded] fires, so every
  /// screen showing plan completion re-reads it. The server links a run to
  /// its workout as the row is written (decisions § 2079); without this a
  /// plain run that satisfied today's workout left every open plan surface
  /// showing it as still to do. Replaces any source passed earlier.
  void followRunsLanded(Listenable runsLanded) {
    _runsLanded?.removeListener(notifyListeners);
    _runsLanded = runsLanded..addListener(notifyListeners);
  }

  @override
  void dispose() {
    _runsLanded?.removeListener(notifyListeners);
    super.dispose();
  }

  SupabaseClient get _c {
    final override = _override;
    if (override != null) return override;
    if (!ApiClient.isInitialized) {
      throw StateError(
        'TrainingService called before Supabase.initialize() resolved.',
      );
    }
    return Supabase.instance.client;
  }
  String? get _uid => _c.auth.currentUser?.id;

  /// Public mirror of [_uid] for screens that need the viewer id but
  /// shouldn't be reaching into `Supabase.instance.client.auth` directly.
  /// Throws the [_c] bootstrap guard before Supabase.initialize resolves,
  /// same as `SocialService.currentUserId` — a pre-init read is a
  /// bootstrap bug, not a signed-out viewer, and must not read as one.
  String? get currentUserId => _uid;

  /// The runner facts every plan built for the viewer calibrates on —
  /// gender, age and the `extra_recovery` setting — graded by
  /// [planCalibrationFrom]. Mirror of web `loadPlanCalibration`.
  ///
  /// The profile goes through `get_my_profile()` (SECURITY DEFINER) because
  /// neither `gender` nor `date_of_birth` nor `health_data_consent_at` is in
  /// the cross-user column grant (20260707_001 / 20270408_001). Reshaping a
  /// plan around the runner's age is an Art 9 health inference, so the date
  /// is resolved through `healthUseDob` inside [planCalibrationFrom] (§ 722).
  ///
  /// L4 best-effort by contract, and each read is its own failure domain: a
  /// failed profile read keeps the setting, and an unloaded settings bag
  /// keeps the age. The try/catch wraps BOTH the `_uid` access (which
  /// touches `_c`, which throws `StateError` in widget tests that don't
  /// initialise Supabase) AND the network read.
  Future<PlanCalibration> fetchPlanCalibration() async {
    UserProfileRow? profile;
    var profileRead = true;
    try {
      if (_uid != null) {
        final row = ApiClient.profileRowFrom(
            await _c.rpc('get_my_profile', params: const {}, get: true));
        if (row != null) profile = UserProfileRow.fromJson(row);
      }
    } catch (e) {
      debugPrint('fetchPlanCalibration: profile read failed: $e');
      profileRead = false;
    }
    return planCalibrationFrom(
      profile: profile,
      profileRead: profileRead,
      extraRecoverySetting: activeSetting(SettingsKeys.extraRecovery),
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Turn `extra_recovery` on or off in the universal settings bag, the
  /// same switch as Settings → Preferences. Throws when the write fails.
  Future<void> setExtraRecovery(bool on) =>
      updateActiveUniversal({SettingsKeys.extraRecovery: on});

  /// The viewer's running history as the plan wizard reads it: far enough
  /// back ([kLayoffMaxDays] plus the four-week base before it) to see the
  /// break a returning runner is coming back from as well as the four weeks
  /// the ramp check grades against, and the last [kGoalCheckWindowDays] of
  /// qualifying efforts the goal-time check projects from. Mirrors the two
  /// reads on web `PlanEditor.svelte`. Same L4 best-effort contract as
  /// [fetchPlanCalibration]: null on any failure, and every note built from it
  /// then self-hides rather than grading against a base it doesn't have.
  Future<PlanRunHistory?> fetchPlanRunHistory() async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final from = DateTime.fromMillisecondsSinceEpoch(
        nowMs - (kLayoffMaxDays + kChronicWindowWeeks * 7 + 1) * 86400000,
        isUtc: true,
      );
      final rows = await _c
          .from('runs')
          .select(
              'id, started_at, distance_m, duration_s, activity_type, source, metadata')
          .eq('user_id', uid)
          .gte('started_at', from.toIso8601String());
      return planRunHistoryFromRows(
          (rows as List).cast<Map<String, dynamic>>(), nowMs);
    } catch (e) {
      debugPrint('fetchPlanRunHistory failed: $e');
    }
    return null;
  }

  /// Plan templates owned by `clubId`. Visible to club members per RLS.
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async {
    final rows = await _c
        .from('training_plans')
        .select()
        .eq('is_template', true)
        .eq('club_id', clubId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  /// Publish one of the viewer's plans as a template under a club they
  /// admin. Returns the new template id. Mirrors the canonical web
  /// path at `apps/web/src/lib/core/data.ts:publishPlanAsTemplate` — a
  /// multi-table INSERT rather than an RPC (there is no
  /// `publish_plan_as_template` function server-side; only
  /// `clone_plan_template` exists, for the adopt direction).
  ///
  /// `vdot`, `current_5k_seconds` and `notes` are nulled on the template
  /// row — the publisher's fitness numbers and their own free text, which
  /// would otherwise leak to every club member via `fetchClubTemplates`.
  /// The trigger in migration 20270508_001 is what actually enforces this;
  /// this insert is reachable by REST without it.
  Future<String> publishPlanAsTemplate({
    required String planId,
    required String clubId,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    final src = await fetchPlan(planId);
    final source = src.plan;
    if (source == null) {
      throw Exception('Source plan not found');
    }
    if (source.userId != uid) {
      throw Exception('Only the plan owner can publish');
    }

    final templateRow = await _c.from('training_plans').insert({
      ...planHeadCopyFields(source),
      'user_id': uid,
      'vdot': null,
      'current_5k_seconds': null,
      'status': 'completed',
      'notes': null,
      'is_template': true,
      'club_id': clubId,
      'parent_template_id': null,
    }).select('id').single();
    final newPlanId = templateRow['id'] as String;

    if (src.weeks.isEmpty) {
      notifyListeners();
      return newPlanId;
    }

    final weekRes = await _c
        .from('plan_weeks')
        .insert(planWeekCopyRows(src.weeks, newPlanId))
        .select('id, week_index');

    final byIdx = <int, String>{};
    for (final r in weekRes as List) {
      final m = r as Map<String, dynamic>;
      byIdx[m['week_index'] as int] = m['id'] as String;
    }
    final oldToNew = <String, String>{};
    for (final w in src.weeks) {
      final newId = byIdx[w.weekIndex];
      if (newId != null) oldToNew[w.id] = newId;
    }

    final workoutPayload = planWorkoutCopyRows(src.workouts, oldToNew);
    if (workoutPayload.isNotEmpty) {
      await _c.from('plan_workouts').insert(workoutPayload);
    }
    notifyListeners();
    return newPlanId;
  }

  /// Adopt a club template — RPC clones it back into a personal plan.
  /// Parameter names mirror the server function signature
  /// (`clone_plan_template(template_id uuid, new_start_date date,
  /// p_overlap text)`) exactly — postgrest passes these through verbatim, so a typo
  /// surfaces as `PGRST202 function not found`.
  Future<String> clonePlanTemplate({
    required String templateId,
    DateTime? startDate,
    PlanOverlapAction onOverlap = PlanOverlapAction.refuse,
  }) async {
    final startIso = toIsoDate(startDate ?? DateTime.now());
    final Object? newId;
    try {
      newId = await _c.rpc(
        'clone_plan_template',
        params: {
          'template_id': templateId,
          'new_start_date': startIso,
          'p_overlap': onOverlap.name,
        },
      );
    } catch (e, st) {
      Error.throwWithStackTrace(await _planCreateError(e, startIso), st);
    }
    notifyListeners();
    return newId as String;
  }

  /// Browse the public plan library — published plans any user can clone
  /// (migration 20270126_001). Optional case-insensitive name search, every
  /// character matched literally (`literalSubstringPattern`, decisions
  /// § 1937).
  /// Each entry carries the author's public display name (handle) joined
  /// from user_profiles; no other author data is exposed. Mirrors web
  /// `core/data.ts:fetchPublicPlanLibrary`.
  Future<List<PublicPlanLibraryEntry>> fetchPublicPlanLibrary({
    String query = '',
  }) async {
    var sel = _c.from('training_plans').select().eq('is_public_template', true);
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      sel = sel.imatchRegex('name', literalSubstringPattern(trimmed));
    }
    final rows = await sel.order('created_at', ascending: false).limit(100);
    final plans = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
    final authorIds = {for (final p in plans) p.userId}.toList();
    final byId = <String, String?>{};
    if (authorIds.isNotEmpty) {
      final profiles = await _c
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', authorIds);
      for (final p in profiles as List) {
        final m = p as Map<String, dynamic>;
        byId[m['id'] as String] = m['display_name'] as String?;
      }
    }
    return [
      for (final p in plans)
        PublicPlanLibraryEntry(plan: p, authorHandle: byId[p.userId]),
    ];
  }

  /// Clone a public-library plan into a user-owned active plan, anchored
  /// at [startDate]. The clone_public_plan RPC authorises on public
  /// visibility server-side and strips the publisher's private fitness
  /// data. Mirrors web `core/data.ts:clonePublicPlan`.
  Future<String> clonePublicPlan({
    required String templateId,
    DateTime? startDate,
    PlanOverlapAction onOverlap = PlanOverlapAction.refuse,
  }) async {
    final startIso = toIsoDate(startDate ?? DateTime.now());
    final Object? newId;
    try {
      newId = await _c.rpc(
        'clone_public_plan',
        params: {
          'template_id': templateId,
          'new_start_date': startIso,
          'p_overlap': onOverlap.name,
        },
      );
    } catch (e, st) {
      Error.throwWithStackTrace(await _planCreateError(e, startIso), st);
    }
    notifyListeners();
    return newId as String;
  }

  /// Publish one of the viewer's plans to the public library: copy the
  /// plan + every week + workout into a new `is_public_template = true`
  /// sibling, leaving the original untouched (mirrors
  /// publishPlanAsTemplate, in the public direction). Publisher fitness
  /// data is stripped. Returns the new template id. Mirrors web
  /// `core/data.ts:publishPlanToLibrary`.
  Future<String> publishPlanToLibrary({required String planId}) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');

    final src = await fetchPlan(planId);
    final source = src.plan;
    if (source == null) {
      throw Exception('Source plan not found');
    }
    if (source.userId != uid) {
      throw Exception('Only the plan owner can publish');
    }

    final templateRow = await _c.from('training_plans').insert({
      ...planHeadCopyFields(source),
      'user_id': uid,
      'vdot': null,
      'current_5k_seconds': null,
      'status': 'completed',
      'notes': null,
      'is_template': true,
      'is_public_template': true,
      'club_id': null,
      'parent_template_id': null,
    }).select('id').single();
    final newPlanId = templateRow['id'] as String;

    if (src.weeks.isEmpty) {
      notifyListeners();
      return newPlanId;
    }

    final weekRes = await _c
        .from('plan_weeks')
        .insert(planWeekCopyRows(src.weeks, newPlanId))
        .select('id, week_index');

    final byIdx = <int, String>{};
    for (final r in weekRes as List) {
      final m = r as Map<String, dynamic>;
      byIdx[m['week_index'] as int] = m['id'] as String;
    }
    final oldToNew = <String, String>{};
    for (final w in src.weeks) {
      final newId = byIdx[w.weekIndex];
      if (newId != null) oldToNew[w.id] = newId;
    }

    final workoutPayload = planWorkoutCopyRows(src.workouts, oldToNew);
    if (workoutPayload.isNotEmpty) {
      await _c.from('plan_workouts').insert(workoutPayload);
    }
    notifyListeners();
    return newPlanId;
  }

  /// Unpublish a public-library template the viewer owns — deletes the
  /// published copy (weeks + workouts cascade). Owner-only via RLS.
  Future<void> unpublishFromLibrary(String templateId) async {
    await _c
        .from('training_plans')
        .delete()
        .eq('id', templateId)
        .eq('is_public_template', true);
    notifyListeners();
  }

  /// The viewer's own published public-library plans (so plan detail can
  /// show whether a plan is already published and offer Unpublish).
  Future<List<TrainingPlanRow>> fetchMyPublishedPlans() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('training_plans')
        .select()
        .eq('is_public_template', true)
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  /// Duplicate a plan week — insert a copy right after [weekIndex], pushing
  /// every later week + the plan end date back by 7 days. The
  /// (plan_id, week_index) re-index is atomic server-side (duplicate_plan_week
  /// RPC) — a client-side multi-update would transiently break the unique
  /// index. Mirrors web `core/data.ts:duplicatePlanWeek`. Returns the new week id.
  ///
  /// Pushing the end date back a week can run into the next queued plan;
  /// the constraint refuses that and it surfaces as [ActivePlanExistsError].
  Future<String> duplicatePlanWeek(String planId, int weekIndex) async {
    final Object? newId;
    try {
      newId = await _c.rpc(
        'duplicate_plan_week',
        params: {
          'p_plan_id': planId,
          'p_week_index': weekIndex,
        },
      );
    } catch (e, s) {
      Error.throwWithStackTrace(planWriteError(e), s);
    }
    notifyListeners();
    return newId as String;
  }

  /// Writes the plan-details fields that change nothing else: the name,
  /// notes, days per week and rules. The goal time goes through
  /// [setPlanGoalTime], because it carries the paces with it. Mirrors web
  /// `core/data.ts:updatePlanMeta`.
  Future<void> updatePlanMeta(
    String planId, {
    required String name,
    required String? notes,
    required int daysPerWeek,
    required List<String>? rules,
  }) async {
    await _c.from(TrainingPlanRow.table).update({
      TrainingPlanRow.colName: name,
      TrainingPlanRow.colNotes: notes,
      TrainingPlanRow.colDaysPerWeek: daysPerWeek,
      TrainingPlanRow.colRules: rules,
    }).eq(TrainingPlanRow.colId, planId);
    notifyListeners();
  }

  /// Sets a plan's goal time with the re-derived workout paces
  /// (`goalTimeRepacePatches`) and VDOT in one transaction
  /// (`set_plan_goal_time`), so the goal and the paces never disagree.
  /// Mirrors web `core/data.ts:setPlanGoalTime`.
  Future<void> setPlanGoalTime(String planId, int? goalTimeSec, double? vdot,
      List<Map<String, Object?>> changes) async {
    await _c.rpc('set_plan_goal_time', params: {
      'p_plan_id': planId,
      'p_goal_time_seconds': goalTimeSec,
      'p_vdot': vdot,
      'p_changes': changes,
    });
    notifyListeners();
  }

  /// Restarts the caller's plan [planId] as a fresh active copy starting on
  /// [startIso], retiring the plans it replaces as abandoned in the same
  /// transaction (`restart_training_plan`). Returns the new plan's id. A race
  /// still ahead surfaces as [PlanRestartRaceAheadError], a start before the
  /// server's today as [PlanRestartBeforeTodayError].
  Future<String> restartPlan(String planId, String startIso) async {
    final Object? id;
    try {
      id = await _c.rpc('restart_training_plan', params: {
        'p_plan_id': planId,
        'p_start_date': startIso,
      });
    } catch (e, s) {
      if (e is PostgrestException && e.code == 'RR001') {
        Error.throwWithStackTrace(const PlanRestartRaceAheadError(), s);
      }
      if (e is PostgrestException && e.code == 'RR002') {
        Error.throwWithStackTrace(const PlanRestartBeforeTodayError(), s);
      }
      Error.throwWithStackTrace(planWriteError(e), s);
    }
    notifyListeners();
    return id! as String;
  }

  /// Moves every workout and the plan's start / end by [days] (the race
  /// moved, the runner started late) in one transaction, with the plans
  /// queued after it when [shiftFollowing]. A shift into another active
  /// plan's window surfaces as [ActivePlanExistsError]. Mirrors web
  /// `core/data.ts:shiftTrainingPlan`.
  Future<void> shiftTrainingPlan(
      String planId, int days, {bool shiftFollowing = false}) async {
    try {
      await _c.rpc('shift_training_plan', params: {
        'p_plan_id': planId,
        'p_days': days,
        'p_shift_following': shiftFollowing,
      });
    } catch (e, s) {
      Error.throwWithStackTrace(planWriteError(e), s);
    }
    notifyListeners();
  }

  /// Re-anchors a plan on a new race date: [change] (`raceDateChange`) names
  /// the weeks to drop or repeat and `change_plan_race_date` applies them in
  /// one transaction. A later end that runs into another
  /// active plan surfaces as [ActivePlanExistsError] via [planWriteError].
  Future<void> changePlanRaceDate(
      String planId, RaceDateChange change, String todayIso) async {
    try {
      await _c.rpc('change_plan_race_date', params: {
        'p_plan_id': planId,
        'p_race_date': change.raceDateIso,
        'p_today': todayIso,
        'p_drop_week_ids': change.dropWeekIds,
        'p_insert_at': change.insertAt,
        'p_insert_count': change.insertCount,
        'p_repeat_week_id': change.repeatWeekId,
        'p_race_workout_id': change.raceWorkoutId,
      });
    } catch (e, s) {
      Error.throwWithStackTrace(planWriteError(e), s);
    }
    notifyListeners();
  }

  /// Runs the latest weeks again after a break and records the offer as
  /// answered (`planBreakChange`, decisions § 2128), in one transaction.
  /// Web twin: `reschedulePlanAfterBreak` in `core/data.ts`.
  Future<void> reschedulePlanAfterBreak(String planId, BreakChange change,
      String breakFromIso, String todayIso) async {
    try {
      await _c.rpc('reschedule_plan_after_break', params: {
        'p_plan_id': planId,
        'p_today': todayIso,
        'p_break_from': breakFromIso,
        'p_repeat_week_ids': change.repeatWeekIds,
        'p_drop_week_ids': change.dropWeekIds,
      });
    } catch (e, s) {
      Error.throwWithStackTrace(planWriteError(e), s);
    }
    notifyListeners();
  }

  /// "Too hard? Repeat this week": runs [change]'s week again next week and
  /// pushes the rest back one, keeping race day by dropping
  /// `change.dropWeekId` (`repeatWeekChange`), in one transaction
  /// (`repeat_plan_week`). Web twin: `repeatPlanWeek` in `core/data.ts`.
  Future<void> repeatPlanWeek(
      String planId, RepeatWeekChange change, String todayIso) async {
    try {
      await _c.rpc('repeat_plan_week', params: {
        'p_plan_id': planId,
        'p_today': todayIso,
        'p_week_id': change.weekId,
        'p_drop_week_id': change.dropWeekId,
      });
    } catch (e, s) {
      Error.throwWithStackTrace(planWriteError(e), s);
    }
    notifyListeners();
  }

  /// Eases [workouts] dated [todayIso] or later for [cfg]'s cycle or
  /// pregnancy (`cyclePlanWorkoutPatch`, decisions § 231) through
  /// [_applyWorkoutAdjustments]; the past is history and is not rewritten.
  /// Returns how many workouts changed. Art 9: the caller holds the
  /// cycle-plans gate. Mirrors web `applyCycleAdjustment` on the plan page.
  Future<int> applyCycleAdjustment(String planId,
      List<PlanWorkoutRow> workouts, CyclePlanConfig cfg, String todayIso) async {
    final patches = <String, Map<String, Object?>>{};
    for (final w in workouts) {
      final date = toIsoDate(w.scheduledDate);
      if (date.compareTo(todayIso) < 0) continue;
      final patch = cyclePlanWorkoutPatch(w.kind, w.targetDistanceM, date, cfg);
      if (patch != null && !patch.isEmpty) patches[w.id] = patch.fields;
    }
    await _applyWorkoutAdjustments(planId, patches);
    return patches.length;
  }

  /// Turns [workouts] — one week's — into a recovery week through
  /// [_applyWorkoutAdjustments], which restates the week's volume in the same
  /// transaction. Returns how many workouts changed. Mirrors web
  /// `markWeekRecovery` on the plan page.
  Future<int> markWeekRecovery(
      String planId, List<PlanWorkoutRow> workouts) async {
    final patches = <String, Map<String, Object?>>{
      for (final w in workouts)
        if (recoveryWorkoutPatch(w.kind, w.targetDistanceM) case final p?)
          w.id: p,
    };
    await _applyWorkoutAdjustments(planId, patches);
    return patches.length;
  }

  Future<List<TrainingPlanRow>> fetchMyPlans() async {
    final uid = _uid;
    if (uid == null) return const [];
    // Published templates live in the same table (decisions §35).
    final rows = await _c
        .from('training_plans')
        .select()
        .eq('user_id', uid)
        .eq('is_template', false)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async {
    // One round trip, not three: the detail screen gives the whole load one
    // timeout, and three sequential queries spent it three times over on a
    // slow link.
    final row = await _c
        .from('training_plans')
        .select('*, plan_weeks(*, plan_workouts(*))')
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      return (
        plan: null,
        weeks: <PlanWeekRow>[],
        workouts: <PlanWorkoutRow>[],
      );
    }
    return planDetailFromRow(row);
  }

  /// Who owns a plan, for the "updated by your coach" line on a workout
  /// (`isEditedByCoach`). Web `fetchPlanOwnerId` twin.
  Future<String?> fetchPlanOwnerId(String planId) async {
    final row = await _c
        .from(TrainingPlanRow.table)
        .select(TrainingPlanRow.colUserId)
        .eq(TrainingPlanRow.colId, planId)
        .maybeSingle();
    return row?[TrainingPlanRow.colUserId] as String?;
  }

  Future<PlanWorkoutRow?> fetchWorkout(String id) async {
    final row = await _c
        .from('plan_workouts')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : PlanWorkoutRow.fromJson(row);
  }

  /// Distances of the runs linked to plan workouts, by run id, for the
  /// "Done · +3 km" status. Ids the viewer cannot read (a coach looking at an
  /// athlete's plan, a deleted run) are simply absent. Web twin:
  /// `fetchRunDistances` in data.ts.
  Future<Map<String, double>> fetchRunDistances(List<String> ids) async {
    final wanted = ids.toSet().toList();
    final rows = await readChunked(
      wanted,
      (chunk) async => List<Map<String, dynamic>>.from(await _c
          .from('runs')
          .select('id, distance_m')
          .inFilter('id', chunk)),
    );
    return {
      for (final r in rows)
        if (r['distance_m'] is num)
          r['id'] as String: (r['distance_m'] as num).toDouble(),
    };
  }

  /// The runs and records the end-of-plan recap (`assemblePlanRecap`) reads,
  /// each dated on the runner's local day. Runs reach two days past either
  /// end of the plan, the run-to-workout matcher's cross-day reach (decisions
  /// § 2079), so a linked run on the window's edge is still found by id.
  /// Throws, so the card can say the recap failed. Web twin:
  /// `fetchPlanRecapSources` in data.ts.
  Future<({List<PlanRecapRun> runs, List<PlanRecapRecord> records})>
      fetchPlanRecapSources(String startIso, String endIso) async {
    final uid = _uid;
    if (uid == null) {
      return (runs: <PlanRecapRun>[], records: <PlanRecapRecord>[]);
    }
    final from = parseIsoDate(shiftIsoDate(startIso, -2)).toUtc();
    final before = parseIsoDate(shiftIsoDate(endIso, 3)).toUtc();
    final results = await Future.wait([
      _c
          .from('runs')
          .select('id, started_at, distance_m, duration_s, activity_type, is_dnf')
          .eq('user_id', uid)
          .gte('started_at', from.toIso8601String())
          .lt('started_at', before.toIso8601String()),
      _c
          .from('personal_records')
          .select('distance, best_time_s, achieved_at, run_id')
          .eq('user_id', uid),
    ]);
    final runs = <PlanRecapRun>[];
    for (final r in (results[0] as List).cast<Map<String, dynamic>>()) {
      final started = parseServerTimestamp(r['started_at']);
      if (started == null) continue;
      runs.add(PlanRecapRun(
        id: r['id'] as String,
        date: toIsoDate(started.toLocal()),
        distanceM: (r['distance_m'] as num?)?.toDouble(),
        durationS: (r['duration_s'] as num?)?.round(),
        activityType: r['activity_type'] as String?,
        isDnf: r['is_dnf'] as bool?,
      ));
    }
    final records = <PlanRecapRecord>[];
    for (final r in (results[1] as List).cast<Map<String, dynamic>>()) {
      final achieved = parseServerTimestamp(r['achieved_at']);
      final time = (r['best_time_s'] as num?)?.round();
      if (achieved == null || time == null) continue;
      records.add(PlanRecapRecord(
        distance: r['distance'] as String,
        timeS: time,
        date: toIsoDate(achieved.toLocal()),
        runId: r['run_id'] as String?,
      ));
    }
    return (runs: runs, records: records);
  }

  /// The viewer's active, non-template plans. Several can be active at once
  /// when their date windows don't overlap.
  Future<List<TrainingPlanRow>> fetchActivePlans() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _c
        .from('training_plans')
        .select()
        .eq('user_id', uid)
        .eq('status', 'active')
        .eq('is_template', false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  /// The overview of the current plan — the one covering today, else the
  /// latest-ended — or, before any has started, of the queued one.
  Future<ActivePlanOverview?> fetchActiveOverview() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      // One deadline for the whole read, owned here rather than by each
      // caller, so a slow link still reaches the saved copy below.
      final snapshot = await _fetchActivePlanSnapshot().timeout(kBackendLoadTimeout);
      unawaited(writeActivePlanCache(uid, snapshot));
      return activeOverviewFrom(snapshot, DateTime.now());
    } catch (e) {
      final saved = await readActivePlanCache(uid);
      if (saved == null) rethrow;
      debugPrint('fetchActiveOverview failed, using the saved copy: $e');
      return activeOverviewFrom(saved, DateTime.now());
    }
  }

  Future<ActivePlanSnapshot> _fetchActivePlanSnapshot() async {
    final activePlans = await fetchActivePlans();
    final plan = currentOrUpcomingPlan(activePlans, toIsoDate(DateTime.now()));
    return ActivePlanSnapshot(
      activePlans: activePlans,
      detail: plan == null ? null : await fetchPlan(plan.id),
    );
  }

  /// The runner's most recently paused plan, so Home can offer to resume it
  /// when there is no active one instead of acting as though there is no
  /// plan. Mirrors the `paused` half of web `fetchActivePlanOverview`.
  Future<TrainingPlanRow?> fetchPausedPlan() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _c
        .from(TrainingPlanRow.table)
        .select()
        .eq('user_id', uid)
        .eq('status', 'paused')
        .eq('is_template', false)
        .order('paused_at', ascending: false, nullsFirst: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : TrainingPlanRow.fromJson(row);
  }

  /// Write a freshly generated plan — plan row, weeks, workouts — through
  /// `create_training_plan`, which resolves the active plans the new window
  /// overlaps per [onOverlap] and inserts everything in one transaction
  /// (decisions § 2050). Plans outside the window stay active beside it.
  Future<TrainingPlanRow> createPlan({
    required String name,
    required GoalEvent goalEvent,
    required double goalDistanceM,
    int? goalTimeSec,
    int? recent5kSec,
    required DateTime startDate,
    required int daysPerWeek,
    String? notes,
    required GeneratedPlan generated,
    // The race listing the plan is built for; the RPC writes null for an id
    // that names no listing rather than refusing the plan.
    String? raceListingId,
    PlanOverlapAction onOverlap = PlanOverlapAction.refuse,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw Exception(
        'Please sign in first — plans sync to your account.',
      );
    }

    // Client-side validation mirroring the TS path. Cheaper to reject here
    // with a readable message than to catch a PostgrestError 23xxx later.
    if (name.trim().isEmpty) {
      throw Exception('Name is required.');
    }
    if (goalDistanceM <= 0) {
      throw Exception('Goal distance must be positive.');
    }
    final minDays = minDaysPerWeek(generated.weeks);
    if (daysPerWeek < minDays || daysPerWeek > 7) {
      throw Exception('Days per week must be between $minDays and 7.');
    }
    if (goalTimeSec != null && goalTimeSec <= 0) {
      throw Exception('Goal time must be positive.');
    }
    if (recent5kSec != null && recent5kSec <= 0) {
      throw Exception('Recent 5K time must be positive.');
    }
    if (generated.weeks.isEmpty) {
      throw Exception('Generated plan has no weeks.');
    }
    // Defence in depth for the same class of generator bug we fixed in
    // training.ts — catch any null kind before the DB rejects the insert.
    for (final w in generated.weeks) {
      for (final wo in w.workouts) {
        // kind is non-nullable in Dart, but an uninitialised code path
        // could still produce WorkoutKind.rest unintentionally; we rely on
        // the non-null type rather than a null check here.
        if (wo.scheduledDate.isBefore(DateTime(2000))) {
          throw Exception(
            'Generator produced a workout with no date (week ${w.weekIndex}).',
          );
        }
      }
    }

    final Object? planId;
    try {
      planId = await _c.rpc('create_training_plan', params: {
        'p_plan': {
          'name': name.trim(),
          'goal_event': goalEventDbValue(goalEvent),
          'goal_distance_m': goalDistanceM,
          'goal_time_seconds': goalTimeSec,
          'start_date': toIsoDate(startDate),
          'end_date': toIsoDate(generated.endDate),
          'days_per_week': daysPerWeek,
          'vdot': generated.vdot,
          'current_5k_seconds': recent5kSec,
          // Match web's `notes?.trim() || null` — whitespace-only collapses
          // to null so the column stays clean for `IS NOT NULL` filters.
          'notes': _trimToNull(notes),
          'race_listing_id': raceListingId,
        },
        'p_weeks': [
          for (final w in generated.weeks)
            {
              'week_index': w.weekIndex,
              'phase': planPhaseDbValue(w.phase),
              'target_volume_m': w.targetVolumeM,
              'notes': w.notes,
              'workouts': [
                for (final wo in w.workouts)
                  {
                    'scheduled_date': toIsoDate(wo.scheduledDate),
                    'kind': workoutKindDbValue(wo.kind),
                    'target_distance_m': wo.targetDistanceM,
                    'target_duration_seconds': wo.targetDurationSeconds,
                    'target_pace_sec_per_km': wo.targetPaceSecPerKm,
                    'target_pace_tolerance_sec': wo.targetPaceToleranceSec,
                    'structure': wo.structure?.toJson(),
                    'notes': wo.notes,
                    'race_name': wo.kind == WorkoutKind.race
                        ? TrainingService.trimToNull(wo.raceName)
                        : null,
                    'race_priority':
                        wo.kind == WorkoutKind.race ? wo.racePriority : null,
                    'race_taper_applied_at': wo.raceTaperAppliedAt,
                  }
              ],
            }
        ],
        'p_overlap': onOverlap.name,
      });
    } catch (e, st) {
      Error.throwWithStackTrace(await _planCreateError(e, toIsoDate(startDate)), st);
    }

    final row = await _c
        .from('training_plans')
        .select()
        .eq('id', planId as String)
        .single();
    notifyListeners();
    return TrainingPlanRow.fromJson(row);
  }

  Future<void> updateStatus(String id, String status) async {
    await _c.from('training_plans').update({'status': status}).eq('id', id);
    notifyListeners();
  }

  /// File an active plan whose dates have run out under Completed (the
  /// "Finish plan" prompt, [isPlanFinished]). Scoped to `status = 'active'`
  /// so a plan paused or abandoned on another device is never relabelled as
  /// finished. Web twin: `finishPlan` in `data.ts`.
  Future<void> finishPlan(String id) async {
    await _c
        .from('training_plans')
        .update({'status': 'completed'})
        .eq('id', id)
        .eq('status', 'active');
    notifyListeners();
  }

  /// Pause an active plan — reversible by [resumePlan], and distinct from
  /// abandon/complete. Frees its dates so another plan can be active on them.
  /// Web twin: `pausePlan` in `apps/web/src/lib/core/data.ts`.
  Future<void> pausePlan(String id) => updateStatus(id, 'paused');

  /// Resume a paused plan. Refuses up front when another active plan
  /// overlaps the paused plan's dates: the `training_plans_active_no_overlap`
  /// constraint would reject the write as a bare 23P01, which reads to the
  /// runner as an unexplained failure rather than "that plan is in the way".
  /// A plan queued before or after it doesn't block. Web twin: `resumePlan` +
  /// `ActivePlanExistsError`.
  /// Resumes a paused plan through `resume_training_plan`, pushing the weeks
  /// [shift] names back when the pause spanned whole weeks (`resumeShift`),
  /// so they come back as upcoming rather than missed. The overlap pre-check
  /// covers the end date the shift gives the plan. Mirrors web `resumePlan`.
  Future<void> resumePlan(String id, {ResumeShift? shift}) async {
    final uid = _uid;
    if (uid == null) throw StateError('resumePlan called with no signed-in user.');
    final row = await _c
        .from('training_plans')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw StateError('resumePlan: plan $id not found.');
    final plan = TrainingPlanRow.fromJson(row);
    final endIso = shift == null
        ? planRowEndIso(plan)
        : shiftIsoDate(planRowEndIso(plan), 7 * shift.weeks);
    final others = [
      for (final p in await fetchActivePlans())
        if (p.id != id) p
    ];
    if (overlappingActivePlans(others, planRowStartIso(plan), endIso).isNotEmpty) {
      throw const ActivePlanExistsError();
    }
    try {
      await _c.rpc('resume_training_plan', params: {
        'p_plan_id': id,
        'p_from_week_index': shift?.fromWeekIndex,
        'p_shift_weeks': shift?.weeks ?? 0,
      });
    } catch (e) {
      if (_isOverlapViolation(e)) throw const ActivePlanExistsError();
      rethrow;
    }
    notifyListeners();
  }


  Future<void> deletePlan(String id) async {
    await _c.from('training_plans').delete().eq('id', id);
    notifyListeners();
  }

  /// Look up the plan that owns a given workout. Walks via `plan_weeks`
  /// because `plan_workouts` doesn't carry a direct `plan_id` column.
  /// Returns null when the row is missing or the user lacks RLS access.
  Future<TrainingPlanRow?> fetchPlanForWorkout(PlanWorkoutRow wo) async {
    try {
      final week = await _c
          .from(PlanWeekRow.table)
          .select()
          .eq('id', wo.weekId)
          .maybeSingle();
      if (week == null) return null;
      final w = PlanWeekRow.fromJson(week);
      final plan = await _c
          .from(TrainingPlanRow.table)
          .select()
          .eq('id', w.planId)
          .maybeSingle();
      if (plan == null) return null;
      return TrainingPlanRow.fromJson(plan);
    } catch (e) {
      debugPrint('[TrainingService.fetchPlanForWorkout] $e');
      return null;
    }
  }

  /// True when the viewer actively coaches [athleteId]: the test the coach
  /// RLS policies on `plan_workouts` run (`private.is_active_coach_of`), so a
  /// screen offers an edit only where the write will be allowed. Mirrors web
  /// `isActiveCoachOf`.
  /// One user's display name, or null when the profile is unreadable or
  /// unnamed. Web twin `fetchDisplayName` in `core/data.ts`.
  Future<String?> fetchDisplayName(String userId) async {
    final row = await _c
        .from('user_profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    return row?['display_name'] as String?;
  }

  Future<bool> isActiveCoachOf(String athleteId) async {
    final uid = _uid;
    if (uid == null || uid == athleteId) return false;
    final rows = await _c
        .from(CoachAthleteRow.table)
        .select(CoachAthleteRow.colId)
        .eq(CoachAthleteRow.colCoachId, uid)
        .eq(CoachAthleteRow.colAthleteId, athleteId)
        .eq(CoachAthleteRow.colStatus, 'active')
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Planned workouts within two days of a run that it could have been, for
  /// the run-detail prompt (`plan_workout_link_candidates`, decisions § 2079).
  /// The database links a run on its own local day only; these are linked
  /// only when the runner says yes, through [markCompleted]. Empty unless the
  /// caller owns the run and it is not linked yet. Nearest day first. Mirrors
  /// web `fetchPlanWorkoutLinkCandidates`.
  Future<List<PlanWorkoutLinkCandidate>> fetchLinkCandidates(
      String runId) async {
    final rows = await _c.rpc(
      'plan_workout_link_candidates',
      params: {'p_run_id': runId},
      get: true,
    );
    return [
      for (final r in rows as List)
        PlanWorkoutLinkCandidate.fromJson(r as Map<String, dynamic>),
    ];
  }

  /// "Not this one" on that prompt: the pair is never offered again. Mirrors
  /// web `dismissPlanWorkoutLink`.
  Future<void> dismissLinkCandidate(String workoutId, String runId) async {
    await _c.rpc(
      'dismiss_plan_workout_link',
      params: {'p_workout_id': workoutId, 'p_run_id': runId},
    );
  }

  Future<void> markCompleted(
    String workoutId,
    String? runId, {
    bool manual = false,
  }) async {
    final isCompleting = runId != null || manual;
    await _c.from('plan_workouts').update({
      'completed_run_id': runId,
      'manually_completed': manual,
      'completed_at':
          isCompleting ? DateTime.now().toUtc().toIso8601String() : null,
      // Completing clears any prior skip — the two states are mutually
      // exclusive. Un-completing leaves the skip flag untouched.
      if (isCompleting) 'skipped_at': null,
    }).eq('id', workoutId);
    notifyListeners();
  }

  /// Toggle a planned workout's intentionally-skipped state. Marking it
  /// skipped stamps `skipped_at` and clears any completion (a row is
  /// never both skipped and done); un-skipping clears `skipped_at`.
  /// Mirrors web `markWorkoutSkipped`.
  Future<void> setSkipped(String workoutId, bool skipped) async {
    await _c.from('plan_workouts').update(
      skipped
          ? {
              'skipped_at': DateTime.now().toUtc().toIso8601String(),
              'completed_run_id': null,
              'manually_completed': false,
              'completed_at': null,
            }
          : {'skipped_at': null},
    ).eq('id', workoutId);
    notifyListeners();
  }

  /// [error] from a create or clone RPC as the caller should surface it: the
  /// overlap refusal (23P01) as [ActivePlanExistsError], the trim refusal
  /// (TR001) as [PlanTrimBlockedError] naming every active plan that starts
  /// before [newStartIso] and runs into it, anything else unchanged. The trim
  /// ends all of them and the refusal does not say which one held completed
  /// workouts, so all are named, as web does. The RPC rolled back, so they
  /// still have their old dates.
  Future<Object> _planCreateError(Object error, String newStartIso) async {
    if (_isOverlapViolation(error)) return const ActivePlanExistsError();
    if (!_isTrimBlocked(error)) return error;
    String? planName;
    try {
      final inTheWay = [
        for (final p in await fetchActivePlans())
          if (planRowStartIso(p).compareTo(newStartIso) < 0 &&
              planRowEndIso(p).compareTo(newStartIso) >= 0)
            p,
      ]..sort((a, b) => a.startDate.compareTo(b.startDate));
      if (inTheWay.isNotEmpty) {
        planName = inTheWay.map((p) => p.name).join(', ');
      }
    } catch (lookup) {
      debugPrint('plan trim refusal: active plan lookup failed: $lookup');
    }
    return PlanTrimBlockedError(
        planName: planName, trimEndIso: dayBeforeIso(newStartIso));
  }

  /// Writes the B/C race taper's per-workout patches (`raceTaperPatch`,
  /// decisions § 2051) through [_applyWorkoutAdjustments]. Unlike
  /// [updateWorkout] a patch may clear the pace target and the interval
  /// structure. Every workout is stamped `race_taper_applied_at`, so the next
  /// proposal leaves the eased workout alone rather than cutting it again.
  /// Mirrors web `applyRaceTaper` on the plan page (`raceTaperAdjustments`).
  Future<void> applyRaceTaper({
    required String planId,
    required Map<String, Map<String, Object?>> patches,
  }) {
    final appliedAt = DateTime.now().toUtc().toIso8601String();
    // Only a workout the taper changes is stamped: a stamp on an untouched
    // one would make every later taper skip it.
    return _applyWorkoutAdjustments(planId, {
      for (final e in patches.entries)
        if (e.value.isNotEmpty)
          e.key: {
            ...e.value,
            PlanWorkoutRow.colRaceTaperAppliedAt: appliedAt,
          },
    });
  }

  /// Writes a re-plan's proposed distances — `target_distance_m` and nothing
  /// else, no load value (decisions § 1977) — through
  /// [_applyWorkoutAdjustments]. Mirrors web `applyReplan` on the plan page.
  Future<void> applyReplan({
    required String planId,
    required Map<String, double> distances,
  }) =>
      _applyWorkoutAdjustments(planId, {
        for (final e in distances.entries)
          e.key: {PlanWorkoutRow.colTargetDistanceM: e.value},
      });

  /// Records the runner's answer to the missed-workout prompt on each of
  /// [workoutIds] (`answer_missed_workouts`, decisions § 2122), so it is never
  /// asked again on any device. "Make it up" passes the previewed make-up as
  /// [distances]; they are written in the same transaction as the answer.
  /// Mirrors web `answerMissedWorkouts`.
  Future<void> answerMissedWorkouts({
    required String planId,
    required List<String> workoutIds,
    Map<String, double> distances = const {},
  }) async {
    await _c.rpc('answer_missed_workouts', params: {
      'p_plan_id': planId,
      'p_workout_ids': workoutIds,
      'p_changes': [
        for (final e in distances.entries)
          {'id': e.key, PlanWorkoutRow.colTargetDistanceM: e.value},
      ],
    });
    notifyListeners();
  }

  /// One `apply_workout_adjustments` call: it writes every patch and
  /// restates each touched week's `target_volume_m` in one transaction, so a
  /// failure changes nothing (decisions § 2061).
  Future<void> _applyWorkoutAdjustments(
      String planId, Map<String, Map<String, Object?>> patches) async {
    final changes = [
      for (final e in patches.entries)
        if (e.value.isNotEmpty) {'id': e.key, ...e.value},
    ];
    if (changes.isEmpty) return;
    await _c.rpc('apply_workout_adjustments', params: {
      'p_plan_id': planId,
      'p_changes': changes,
    });
    notifyListeners();
  }

  /// Candidate runs the owner can re-link to [workout].
  ///
  /// Owner-scoped, within ±7 days of the scheduled date, EXCLUDING any
  /// run already linked to a *different* plan workout so re-linking can't
  /// double-count a run in `plan_progress`. The workout's own current run
  /// stays in the list. Newest-first. Mirrors web `fetchRelinkCandidate-
  /// Runs`; the eligibility logic is the `relink_candidates.dart` twin.
  Future<List<RelinkCandidateRun>> fetchRelinkCandidates(
    PlanWorkoutRow workout,
  ) async {
    final uid = _uid;
    if (uid == null) return const [];

    // Run ids already linked anywhere in this owner's plans. Scope
    // through the owner's plan_weeks (RLS chains the same way; the
    // explicit scope is defence in depth).
    final planRows = await _c
        .from(TrainingPlanRow.table)
        .select('id, plan_weeks(id)')
        .eq('user_id', uid);
    final weekIds = <String>[];
    for (final p in (planRows as List).cast<Map<String, dynamic>>()) {
      final weeks = (p['plan_weeks'] as List?) ?? const [];
      for (final w in weeks.cast<Map<String, dynamic>>()) {
        weekIds.add(w['id'] as String);
      }
    }
    final linkedRunIds = <String>[];
    if (weekIds.isNotEmpty) {
      final linkedRows = await _c
          .from(PlanWorkoutRow.table)
          .select('completed_run_id')
          .inFilter('week_id', weekIds)
          .not('completed_run_id', 'is', null);
      for (final r in (linkedRows as List).cast<Map<String, dynamic>>()) {
        final id = r['completed_run_id'] as String?;
        if (id != null) linkedRunIds.add(id);
      }
    }

    final runRows = await _c
        .from('runs')
        .select('id, started_at, distance_m, duration_s')
        .eq('user_id', uid)
        .order('started_at', ascending: false);
    final runs = (runRows as List).cast<Map<String, dynamic>>().map((r) {
      return RelinkCandidateRun(
        id: r['id'] as String,
        startedAt: parseIsoStrictRequired(r['started_at'], 'started_at'),
        distanceM: (r['distance_m'] as num).toDouble(),
        durationS: (r['duration_s'] as num).toInt(),
      );
    }).toList();

    return filterRelinkCandidates(
      runs: runs,
      linkedRunIds: linkedRunIds,
      currentRunId: workout.completedRunId,
      scheduledDate: workout.scheduledDate,
    );
  }

  /// Patch the editable fields on a planned workout; see
  /// [planWorkoutPatch] for what each argument writes. Server-side RLS
  /// scopes writes to the plan owner.
  Future<void> updateWorkout(
    String workoutId, {
    String? kind,
    String? fromKind,
    PlanWorkoutTargets? targets,
    String? notes,
    PlanWorkoutRaceFields? race,
    PlanWorkoutRange? rpe,
    PlanWorkoutRange? hr,
  }) async {
    final patch = planWorkoutPatch(
      kind: kind,
      fromKind: fromKind,
      targets: targets,
      notes: notes,
      race: race,
      rpe: rpe,
      hr: hr,
    );
    if (patch.isEmpty) return;
    await _c.from(PlanWorkoutRow.table).update(patch).eq('id', workoutId);
    notifyListeners();
  }

  /// Move a planned workout to another day of its week through
  /// `move_plan_workout` (decisions § 2073). When [dateIso] already holds a
  /// row, the two trade days; returns the swapped workout's id, or null when
  /// the day was free. Web `movePlanWorkout` twin.
  Future<String?> moveWorkout(String workoutId, String dateIso) async {
    final swapped = await _c.rpc('move_plan_workout', params: {
      'p_workout_id': workoutId,
      'p_date': dateIso,
    });
    notifyListeners();
    return swapped as String?;
  }

  /// Pure helper: trim a string then collapse empty-after-trim to
  /// null. Mirrors web's `s?.trim() || null` pattern used across
  /// `apps/web/src/lib/core/data.ts` for every optional text column.
  /// Exposed `@visibleForTesting` so the contract can be pinned in
  /// the parity test suite alongside the other normalisation helpers.
  @visibleForTesting
  static String? trimToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  // Internal alias for the public helper above. Keeps callers inside
  // this file short while the public name stays explicit.
  static String? _trimToNull(String? s) => trimToNull(s);
}

/// One row of `plan_workout_link_candidates`: a planned workout [dayOffset]
/// days from the run's local day (positive = scheduled after it, so the run
/// was early).
class PlanWorkoutLinkCandidate {
  final String workoutId;
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final int? targetDurationSeconds;
  final int dayOffset;

  const PlanWorkoutLinkCandidate({
    required this.workoutId,
    required this.scheduledDate,
    required this.kind,
    this.targetDistanceM,
    this.targetDurationSeconds,
    required this.dayOffset,
  });

  factory PlanWorkoutLinkCandidate.fromJson(Map<String, dynamic> json) =>
      PlanWorkoutLinkCandidate(
        workoutId: json['workout_id'] as String,
        scheduledDate: json['scheduled_date'] as String,
        kind: json['kind'] as String,
        targetDistanceM: (json['target_distance_m'] as num?)?.toDouble(),
        targetDurationSeconds: (json['target_duration_seconds'] as num?)?.toInt(),
        dayOffset: (json['day_offset'] as num).toInt(),
      );
}

/// Splits one `training_plans` row carrying a `plan_weeks(*, plan_workouts(*))`
/// embed into the plan, its weeks and its workouts. Ordered here because an
/// embed is ordered per parent, so neither list arrives in plan order.
({TrainingPlanRow plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})
    planDetailFromRow(Map<String, dynamic> row) {
  final planRow = Map<String, dynamic>.of(row);
  final weekRows = ((planRow.remove('plan_weeks') as List?) ?? const [])
      .cast<Map<String, dynamic>>();
  final weeks = <PlanWeekRow>[];
  final workouts = <PlanWorkoutRow>[];
  for (final w in weekRows) {
    final weekRow = Map<String, dynamic>.of(w);
    final woRows = ((weekRow.remove('plan_workouts') as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    weeks.add(PlanWeekRow.fromJson(weekRow));
    workouts.addAll(woRows.map(PlanWorkoutRow.fromJson));
  }
  weeks.sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  workouts.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
  return (plan: TrainingPlanRow.fromJson(planRow), weeks: weeks, workouts: workouts);
}

/// The overview [snapshot] describes as of [now]: the current plan (the one
/// covering today, else the latest-ended, else the queued one), today's
/// workout, the completion figure and the current week. Pure, so a saved
/// snapshot reads today correctly whenever it was saved.
ActivePlanOverview? activeOverviewFrom(ActivePlanSnapshot snapshot, DateTime now) {
  final activePlans = snapshot.activePlans;
  final today = toIsoDate(now);
  final plan = currentOrUpcomingPlan(activePlans, today);
  final res = snapshot.detail;
  if (plan == null || res == null || res.plan == null || res.plan!.id != plan.id) {
    return null;
  }
  final upcoming = pickCurrentPlan(
    [for (final p in activePlans) if (p.id != plan.id) p],
    planRowStartIso(plan).compareTo(today) > 0 ? planRowStartIso(plan) : today,
    start: planRowStartIso,
    end: planRowEndIso,
  ).upcoming;
  final todayWorkout = res.workouts
      .where((w) => toIsoDate(w.scheduledDate) == today && w.kind != 'rest')
      .cast<PlanWorkoutRow?>()
      .firstOrNull;
  final active = res.workouts.where((w) => w.kind != 'rest').toList();
  final done = active.where(isWorkoutCompleted).length;
  final pct = active.isEmpty ? 0 : (100 * done / active.length).round();
  // Whole-epoch-day bucketing, not a wall-clock difference: a start→today
  // span crossing a DST transition is 167/169 h, so `inDays` truncates a day
  // short and reports the previous week (#338). A plan whose weeks failed to
  // load has no valid index — the helper's `weekCount - 1` would be -1.
  final currentWeek = res.weeks.isEmpty
      ? 0
      : currentPlanWeekIndex(
          toIsoDate(plan.startDate),
          today,
          res.weeks.length,
        );
  return ActivePlanOverview(
    plan: plan,
    weeks: res.weeks,
    workouts: res.workouts,
    todayWorkout: todayWorkout,
    completionPct: pct,
    currentWeekIndex: currentWeek,
    upcomingPlan: upcoming,
  );
}
