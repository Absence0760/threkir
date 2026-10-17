import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'training.dart' show TrainingGender;

import 'health_consent.dart';
import 'nutrition_targets.dart' show ageFromDob;
import 'plan_copy.dart';
import 'plan_current.dart';
import 'plan_ramp.dart';
import 'plan_week.dart';
import 'relink_candidates.dart';
import 'training.dart';

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

/// The `plan_workouts` patch [TrainingService.updateWorkout] sends. A null
/// argument leaves its column alone, except inside [race]: that writes the
/// race name, priority and goal time as given, nulls included. A [kind]
/// other than `race` clears the race name and priority instead, since the
/// table allows them only on race rows (23514 otherwise), and when the row
/// was a race ([fromKind]) it clears the race's goal time too, so a former
/// race does not keep its finish time as a duration target. Matches web's
/// `WorkoutEditor` save. [notes] is
/// trimmed and an empty result nulls the column, matching web's
/// `updatePlanWorkout`.
Map<String, dynamic> planWorkoutPatch({
  String? kind,
  String? fromKind,
  double? targetDistanceM,
  int? targetPaceSecPerKm,
  String? notes,
  PlanWorkoutRaceFields? race,
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
  if (targetDistanceM != null) {
    patch[PlanWorkoutRow.colTargetDistanceM] = targetDistanceM;
  }
  if (targetPaceSecPerKm != null) {
    patch[PlanWorkoutRow.colTargetPaceSecPerKm] = targetPaceSecPerKm;
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

  /// The viewer's own `user_profiles` row, or null. Goes through
  /// `get_my_profile()` (SECURITY DEFINER) because neither `gender` nor
  /// `date_of_birth` nor `health_data_consent_at` is in the cross-user column
  /// grant (20260707_001 / 20270408_001): a direct `.select('gender')` is
  /// rejected outright with 42501, so the reads this replaced could only ever
  /// report "unset" — the same defect `ApiClient.fetchAiDisclosure` records.
  ///
  /// L4 best-effort by contract: the plan wizard's initState awaits the two
  /// callers without blocking, and any failure only costs the calibration.
  /// The try/catch must therefore wrap BOTH the `_uid` access (which touches
  /// `_c`, which throws `StateError` in widget tests that don't initialise
  /// Supabase) AND the network read. A regression that narrowed the catch to
  /// the inner read alone surfaced as `plan_new_screen_test` failing with
  /// "TrainingService called before Supabase.initialize() resolved" in CI.
  Future<UserProfileRow?> _fetchMyProfile() async {
    try {
      if (_uid == null) return null;
      final row = ApiClient.profileRowFrom(
          await _c.rpc('get_my_profile', params: const {}, get: true));
      if (row == null) return null;
      return UserProfileRow.fromJson(row);
    } catch (_) {
      /* L4 best-effort — fall back to null on any failure,
         including the not-yet-initialised StateError thrown by
         the _c getter in widget tests. */
    }
    return null;
  }

  /// Persona-hunt Round 3 finding Woman #3. Reads the viewer's
  /// `user_profiles.gender` so the plan wizard can apply the
  /// gender-aware pace calibration. Returns null when the column is
  /// unset (the default) — pacesFromGoalPace then uses the
  /// male-derived curve unchanged. Mirror of the inline supabase
  /// read on web `PlanEditor.svelte`. Gender carries its own consent
  /// term at every write path, so the read needs none.
  Future<TrainingGender> fetchViewerGender() async {
    final g = (await _fetchMyProfile())?.gender;
    if (g == 'male' || g == 'female' || g == 'prefer_not_to_say') return g;
    return null;
  }

  /// The viewer's chronic weekly running volume over the ramp check's
  /// trailing window, so the plan wizard can say whether the plan it just
  /// generated is a step the runner's current training supports. Same L4
  /// best-effort contract as [fetchViewerGender]: null on any failure, and
  /// the note then self-hides rather than grading against a base it doesn't
  /// have.
  Future<RecentVolume?> fetchRecentRunVolume() async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final from = DateTime.fromMillisecondsSinceEpoch(
        nowMs - kChronicWindowWeeks * 7 * 86400000,
        isUtc: true,
      );
      final rows = await _c
          .from('runs')
          .select('started_at, distance_m, activity_type')
          .eq('user_id', uid)
          .gte('started_at', from.toIso8601String());
      final runs = (rows as List).cast<Map<String, dynamic>>().map((r) {
        return RunForVolume(
          startedAt: r['started_at'] as String? ?? '',
          distanceM: (r['distance_m'] as num?)?.toDouble(),
          activityType: r['activity_type'] as String?,
        );
      }).toList();
      return recentRunVolume(runs, nowMs);
    } catch (_) {
      /* L4 best-effort — null on any failure. */
    }
    return null;
  }

  /// Persona-hunt finding Older #30. Returns the viewer's whole-year age so
  /// the plan wizard can apply the masters recovery calibration (50+), or
  /// null — generatePlan then uses the standard younger-physiology schedule.
  ///
  /// Reshaping a training plan around the runner's age is an Art 9 health
  /// inference, and the age record itself carries no consent term because the
  /// under-18 search floor depends on it (§ 718). So the date comes through
  /// [healthUseDob] rather than off the row, matching web's PlanEditor
  /// (§ 722). Same L4 best-effort contract as [fetchViewerGender].
  Future<int?> fetchViewerAge() async {
    final dob = healthUseDob(await _fetchMyProfile());
    return ageFromDob(dob, DateTime.now().millisecondsSinceEpoch);
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
    final planRow = await _c
        .from('training_plans')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (planRow == null) {
      return (
        plan: null,
        weeks: <PlanWeekRow>[],
        workouts: <PlanWorkoutRow>[],
      );
    }
    final weekRows = await _c
        .from('plan_weeks')
        .select()
        .eq('plan_id', id)
        .order('week_index', ascending: true);
    final weeks = (weekRows as List)
        .cast<Map<String, dynamic>>()
        .map(PlanWeekRow.fromJson)
        .toList();
    if (weeks.isEmpty) {
      return (
        plan: TrainingPlanRow.fromJson(planRow),
        weeks: <PlanWeekRow>[],
        workouts: <PlanWorkoutRow>[],
      );
    }
    final woRows = await _c
        .from('plan_workouts')
        .select()
        .inFilter('week_id', weeks.map((w) => w.id).toList())
        .order('scheduled_date', ascending: true);
    final workouts = (woRows as List)
        .cast<Map<String, dynamic>>()
        .map(PlanWorkoutRow.fromJson)
        .toList();
    return (
      plan: TrainingPlanRow.fromJson(planRow),
      weeks: weeks,
      workouts: workouts,
    );
  }

  Future<PlanWorkoutRow?> fetchWorkout(String id) async {
    final row = await _c
        .from('plan_workouts')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : PlanWorkoutRow.fromJson(row);
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
    final activePlans = await fetchActivePlans();
    final today = toIsoDate(DateTime.now());
    final plan = currentOrUpcomingPlan(activePlans, today);
    if (plan == null) return null;
    final upcoming = pickCurrentPlan(
      [for (final p in activePlans) if (p.id != plan.id) p],
      planRowStartIso(plan).compareTo(today) > 0 ? planRowStartIso(plan) : today,
      start: planRowStartIso,
      end: planRowEndIso,
    ).upcoming;
    final res = await fetchPlan(plan.id);
    if (res.plan == null) return null;
    final todayWorkout = res.workouts
        .where((w) =>
            toIsoDate(w.scheduledDate) == today && w.kind != 'rest')
        .cast<PlanWorkoutRow?>()
        .firstOrNull;
    final active = res.workouts.where((w) => w.kind != 'rest').toList();
    final done = active
        .where((w) => w.completedRunId != null || w.manuallyCompleted)
        .length;
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
    if (daysPerWeek < 3 || daysPerWeek > 7) {
      throw Exception('Days per week must be between 3 and 7.');
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
  Future<void> resumePlan(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('resumePlan called with no signed-in user.');
    final row = await _c
        .from('training_plans')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) throw StateError('resumePlan: plan $id not found.');
    final plan = TrainingPlanRow.fromJson(row);
    final others = [
      for (final p in await fetchActivePlans())
        if (p.id != id) p
    ];
    if (overlappingActivePlans(others, planRowStartIso(plan), planRowEndIso(plan))
        .isNotEmpty) {
      throw const ActivePlanExistsError();
    }
    try {
      await updateStatus(id, 'active');
    } catch (e) {
      if (_isOverlapViolation(e)) throw const ActivePlanExistsError();
      rethrow;
    }
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
    double? targetDistanceM,
    int? targetPaceSecPerKm,
    String? notes,
    PlanWorkoutRaceFields? race,
  }) async {
    final patch = planWorkoutPatch(
      kind: kind,
      fromKind: fromKind,
      targetDistanceM: targetDistanceM,
      targetPaceSecPerKm: targetPaceSecPerKm,
      notes: notes,
      race: race,
    );
    if (patch.isEmpty) return;
    await _c.from(PlanWorkoutRow.table).update(patch).eq('id', workoutId);
    notifyListeners();
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
