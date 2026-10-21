/**
 * Data access layer — all Supabase queries in one place.
 */
import { supabase } from './supabase';
import { edgeFunctionErrorCode, edgeFunctionErrorMessage } from './edge_function_error';
import { appErrorMessage, dbError, isDuplicateKeyError, supabaseErrorFields, thrownMessage } from './supabase_error';
import { singleEmbed, fitnessSnapshotDue, publicRouteListFill } from './data_normalise';
import { TABLES, BUCKETS, METADATA_KEYS } from './schema';
import type { Database, Json } from '../database.types';
import { asProjectedRun, asRun, type ProjectedRun, type RunRow } from './run_narrow';
import { SELECT_SEPARATOR, type Join } from './database';
import type { Insertable, Updatable } from './database';
import type { JsonObject, TrackPoint } from '../types';
import { isEntityId } from './entity_id';
import { saveRunEdit, type RunEditFields, type RunEditOutcome } from './run_edit_cas';
import { markListsStale } from './list_freshness';
import {
	keysetAfter,
	literalSubstringPattern,
	literalSubstringTerm,
	nextCursor,
	publicRouteOrder,
	type KeysetCursor,
	type KeysetKey,
	type KeysetPage,
	type PublicRouteSort,
	walkKeyset,
} from './keyset_page';
import { probeSaysConfigured } from './provider_probe';
import { loadSettings, effective } from '../settings/settings';
import type { Modality } from '../settings/modality_visibility';
import {
	audienceColumns,
	levelRevokesGrants,
	privacyDefaultToAudience,
	type AudienceColumns,
	type AudienceLevel,
} from '../social/run_visibility';
import { bandsToRanges, type DistanceBandKey } from '../routes/distance_bands';
import { assemblePublicRoute } from '../routes/public_route_assembly';
import { stripExifFromFile } from '../util/exif_strip';
import { entriesFromTemplate } from '../nutrition/meal_template';
import { logInputFromRecipe } from '../nutrition/recipe';
import {
	assignmentsToEnd,
	stopFollowingAction,
	type PlanAssignment,
	type PlanTargets,
} from '../nutrition/meal_plan';
import { challengesToRecomputeForRun } from '../social/challenge_progress';
import { mergeMyProgress } from '../social/challenge_list';
import { selectEffectivePricing } from '../social/event_instance';
import type { RepacePatch } from '../training/plan_repace';
import type { ResumeShift } from '../training/plan_resume';
import type { RaceDateChange } from '../training/plan_race_date';
import type { BreakChange } from '../training/plan_break';
import type { RepeatWeekChange } from '../training/plan_repeat_week';
import { shiftIsoDate } from '../training/plan_bulk_ops';
import type { PlanRecapRecord, PlanRecapRun } from '../training/plan_recap';
import {
	EVENT_PHOTO_WINDOW_AFTER_MS,
	EVENT_PHOTO_WINDOW_BEFORE_MS,
	isRunInEventPhotoWindow,
} from '../social/event_photo_window';
import {
	applyCourseSave,
	planCourseSave,
	sortCourses,
	type CourseDraft,
	type EventCourse,
} from '../social/event_courses';
import { parseHostEarningsRow, type HostEarningsInstance } from '../social/host_earnings';
import {
	cancelledOccurrenceRefunds,
	parseOccurrenceRefundSummary,
	type OccurrenceRefundState,
	type OccurrenceRefundSummary
} from '../social/paid_registration';
import { planHeadCopyFields, planWeekCopyRows, planWorkoutCopyRows } from './plan_copy';
import { clubSlug, CLUB_SLUG_FALLBACK } from '../social/club_slug';
import {
	ROUTE_LIST_COLS,
	PUBLIC_ROUTE_LIST_COLS,
	type RouteListItem,
	type PublicRouteListRow,
	type PublicRouteSummary
} from '../routes/route_list_columns';
import type {
	Run,
	Route,
	Integration,
	Club,
	ClubWithMeta,
	ClubMember,
	ClubRole,
	MembershipStatus,
	JoinPolicy,
	Event,
	EventWithMeta,
	EventAttendee,
	EventAttendance,
	RsvpStatus,
	ClubPost,
	ClubPostWithAuthor,
	RecurrenceFreq,
	EventCategory,
	EventPricing,
	EventOrder,
	Weekday,
	TrainingPlan,
	PlanWeek,
	PlanWorkout,
	ActivePlanOverview,
	PlanStatus,
	NotificationKind,
	GymSetType,
	GymExerciseModality,
	GymProgressionScheme,
	Exercise,
	ExerciseCategory,
	RouteMarker,
	RouteMarkerKind,
	Achievement,
	Challenge,
	ChallengeMetric,
	ChallengeScope,
	ChallengeWithMeta,
	ChallengeLeaderboardRow,
	ActivityType,
	Fundraiser,
	FundraiserStatus,
	FundraiserFeedEntry,
	FundraiserTotals,
	RaceListing,
	RaceProvider,
	RouteCondition,
	RouteConditionKind,
	RouteConditionSeverity
} from '../types';
export type { NotificationKind };
import {
	parseActivityType,
	parseIntegrationProvider,
	parseJoinPolicy,
	parseNutritionAssignmentStatus,
	parseNutritionGoalPhase,
	parseNutritionProgression,
	parseRouteSurface,
	parseRunMetadata,
	parseRunSource,
	type NutritionGoalPhase,
	type NutritionPlan,
	type NutritionPlanAssignment,
	type RunSource,
} from '../types';
import type { RaceImportLeg } from '../integrations/race_import_providers';
import {
	parseUltraSignUpCandidates,
	ultraSignUpLinkFromRow,
	type UltraSignUpCandidate,
	type UltraSignUpPersonLink
} from '../integrations/ultrasignup_person';
import {
	filterRelinkCandidates,
	DEFAULT_RELINK_WINDOW_DAYS,
	type RelinkCandidateRun
} from '../training/relink_candidates';
import type { GeneratedPlan, GoalEvent, PlanPhase } from '../training/training';
import type { RacePriority } from '../training/plan_races';
import { parseRosterRecentWorkouts, type RosterRecentWorkout } from '../training/coach_load';
import { auth } from '../stores/auth.svelte';
import { lineLngLat, trackLine } from '../runs/track_line';
import {
	mergeSmoothedSidecar,
	needsSmoothedSidecar,
	sha256Hex,
	sidecarNamedFor,
	smoothedSidecarPath,
} from '../runs/smoothed_sidecar';
import { compareLeaderboard } from '../runs/race_leaderboard';
import { readRankRows } from '../segments/effort_rank';
import type { RecapPeriodKind } from '../types';
import { GYM_SESSION_DRAFT_KEY, hasSessionDraft } from '../gym/gym_session_draft';
import { dedupeShadowedExercises } from '../gym/exercise_catalogue';
import { namesAnExercise } from '../gym/gym_prs';
import type { RoutineHistoryAggregate, RoutineSessionRow } from '../gym/routine_history';
import type { YearInRunningRecap } from '../runs/recap';
import type { PlatformFeeMonthRow } from '../billing/platform_fee_summary';
import { mergeRecapRuns, recapYearWindow } from '../runs/recap_window';
import type {
	CoachAthleteStatus,
	FinisherStatus,
	FinishMethod,
	RaceSessionStatus,
	SessionPlan,
	SessionPlanBlock,
	SessionPlanItem,
	SessionPlanWithItems,
	SessionItemKind,
	ReportTargetKind
} from '../types';
// Re-export the session-plan domain shapes so consumers can import them from the
// data-layer facade alongside fetchSessionPlan* (which returns SessionPlanWithItems)
// and the SessionPlan*Input types defined below.
export type { SessionPlan, SessionPlanBlock, SessionPlanItem, SessionPlanWithItems } from '../types';
// ReportTargetKind lives in types.ts alongside the other CHECK-paired narrow
// unions (so the CHECK<->union guard can read it from one file); re-exported
// here so the report surfaces keep importing it from the data-layer facade.
export type { ReportTargetKind } from '../types';
import { isOccurrenceCancelled, nextLiveInstance } from '../social/event_occurrence';
import {
	parseGymTemplate,
	type EventGymTemplate
} from '../social/event_gym_template';
import { m } from '../i18n/store.svelte';
import { rateLimitErrorMessage } from '../i18n/rate_limit_message';
import {
	DM_THREAD_ORDER,
	DM_THREAD_PAGE_SIZE,
	dmPageBeforeFilter,
	dmPageFromRows,
	type DmOrderKey,
	type DmPage,
	type DmThreadTarget,
} from '../social/dm_thread';
import type { ParsedResultRow } from '../runs/event_results_csv';
import {
	normalisePlanWorkoutNotes,
	shouldRescoreGlobalSegments,
	stampGlobalSegmentsScored,
	GLOBAL_SEGMENT_SCORING_LIMIT,
} from './data_normalise';
import { dashboardRunsWindowStart } from './dashboard_runs';
import {
	chunk,
	mergeFeedPages,
	mergeProfilePages,
	mergeRecencyPages,
	readChunked,
	queryChunked,
	FEED_FOLLOWEE_CHUNK
} from '../social/feed_merge';
import { deleteRunsBounded } from './bulk_delete';
import {
	assignCompetitionRanks,
	type SegmentAgeBand,
	type SegmentGenderFilter,
} from '../segments/segments';

// --- Runs ---

/// A `runs` projection, as the tuple both the wire string and the row type are
/// derived from. `satisfies RunColumns` on a literal refuses a name that is not
/// a column, so a migration that drops one fails to compile at the declaration
/// rather than asking PostgREST for nothing.
///
/// The intersection is what makes that true, and `keyof Run` alone did not:
/// the overlay adds `track` — a lazy Storage download that has never been a
/// column — and `has_track`, a field only the `public_runs` view carries. Both
/// passed `satisfies` and both reach PostgREST as a 42703 that fails the WHOLE
/// read, not just the column. Narrowing to the generated row's own keys is the
/// check the typed client makes available; `data.test.ts` pins both refusals.
///
/// The wire string is `.join()`ed from the tuple, so it is `string` and
/// supabase-js's select parser can read nothing from it — unlike every other
/// narrowed read here, whose columns are a module constant `Join<T, D>` can
/// re-state as the literal it spells. These are a caller's parameter, known
/// only at the call site, so the check lives at the tuple's own declaration
/// instead and the row type is `Pick`ed from that same tuple: one declaration,
/// two derivations, which is the whole point of § 1330.
///
/// Making the implementation generic over the tuple and casting the join to
/// `Join<C, D>` does not recover the parse, and it is worse than the string:
/// measured, `ParseQuery` neither resolves nor collapses to
/// `GenericStringError` but stays a deferred conditional, so the body cannot
/// read a single field off the row it is meant to narrow (§ 1518). The row
/// shape is therefore stated once, at the read, as what a projection of this
/// table can return. The UNNARROWED read shares nothing with that: it hands
/// `.select()` a literal `'*'` of its own and infers the whole row for itself
/// (§ 1560), so only this branch carries a stated shape.
export type RunColumns = readonly (keyof Run & keyof RunRow)[];

export interface FetchRunsOptions<C extends RunColumns = RunColumns> {
	/** Cap the number of rows returned. Pair with `after` for paging. */
	limit?: number;
	/**
	 * Only the runs strictly after this cursor in `RUN_ORDER` — the previous
	 * page's `next` from `fetchRunsWithError`. A cursor rather than an offset:
	 * a run deleted or synced in between two reads moves every later position,
	 * and an offset then skips or repeats a run.
	 */
	after?: KeysetCursor | null;
	/**
	 * Re-throw a hard fetch error instead of degrading to `[]`. Default off:
	 * most callers want a resilient empty list. The personal heatmap opts in
	 * so it can tell "fetch failed" (retryable error) apart from "no runs yet"
	 * (empty state) — returning `[]` on a 500 would tell an active runner
	 * they've never run anywhere.
	 */
	throwOnError?: boolean;
	/**
	 * The columns to project, as a tuple. Absent means `*`. A caller that
	 * reads only a handful should narrow — `*` ships the `metadata` jsonb bag
	 * on every row, which is what made the unbounded history scan expensive in
	 * the first place (#332).
	 *
	 * A tuple rather than the PostgREST string it becomes, because the string
	 * narrowed the WIRE while the return type stayed `Run[]`: nineteen of the
	 * twenty-four columns were `undefined` behind a type promising them
	 * (§ 1330). The tuple is the one declaration both halves derive from — the
	 * select list is joined from it and the row type is `Pick`ed from it.
	 */
	columns?: C;
	/** Inclusive lower bound on `started_at`, as an ISO instant. */
	startedAtFrom?: string;
	/** Exclusive upper bound on `started_at`, as an ISO instant. */
	startedAtBefore?: string;
}

/// Newest run first; `id` breaks a `started_at` tie so the order is total.
/// Served by `runs_user_started_at (user_id, started_at desc)` up to the
/// tie-break. Both columns are NOT NULL, so the null placement is the
/// Postgres default and only spelt out because a keyset key must say it.
const RUN_ORDER: readonly KeysetKey[] = [
	{ column: 'started_at', ascending: false, nullsFirst: true },
	{ column: 'id', ascending: false, nullsFirst: true },
];

export async function fetchRuns(opts?: Omit<FetchRunsOptions, 'columns'>): Promise<Run[]>;
export async function fetchRuns<C extends RunColumns>(
	opts: FetchRunsOptions<C> & { columns: C },
): Promise<Pick<Run, C[number]>[]>;
export async function fetchRuns(
	opts?: FetchRunsOptions,
): Promise<Run[] | ProjectedRun[]> {
	// Explicit user_id filter as defence in depth — RLS already scopes
	// runs to the caller, but every other personal-data list in this
	// file follows the same explicit-scope pattern. See audit
	// `/tmp/data-isolation-audit/client-realtime.md` M2.
	const userId = auth.user?.id;
	if (!userId) return [];
	const build = <S extends string>(select: S, after: string | null) => {
		let q = supabase
			.from(TABLES.runs)
			// Generic over the select list rather than a ternary over it. A
			// ternary is a union of `string` and `'*'`, which is `string`, so the
			// literal arm was erased for the parser too and neither branch could
			// be read off. A type parameter is instantiated at each CALL site
			// instead, so `build('*')` carries its own literal; § 1518 measured
			// that a deferred `ParseQuery` cannot be read in the body, and
			// nothing here reads a field off the row.
			.select(select)
			.eq('user_id', userId);
		if (opts?.startedAtFrom != null) q = q.gte('started_at', opts.startedAtFrom);
		if (opts?.startedAtBefore != null) q = q.lt('started_at', opts.startedAtBefore);
		if (after) q = q.or(after);
		// Sorted by the same spec the cursor is read from, so the two cannot
		// drift: a cursor taken in one order and applied in another skips rows.
		for (const k of RUN_ORDER) {
			q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
		}
		return q;
	};

	// One load-more page, or the whole history; the `throwOnError` contract is
	// shared by both branches and generic in the row type the caller's own page
	// function hands back. Sharing it is what the per-projection sibling § 1518
	// refused would have cost four copies of.
	const collect = async <R extends object>(
		page: (after: string | null, limit: number) => PromiseLike<{ data: R[] | null; error: unknown }>,
	): Promise<R[]> => {
		if (opts?.limit != null) {
			const after = opts.after ? keysetAfter(RUN_ORDER, opts.after) : null;
			if (opts.after && after === null) return [];
			const { data, error } = await page(after, opts.limit);
			if (error || !data) {
				if (opts?.throwOnError && error) throw dbError(error);
				return [];
			}
			return data;
		}
		// No explicit limit means "every run" — recap, heatmap, account export.
		// PostgREST caps an unbounded SELECT at 1000 rows, so the history is
		// walked, and walked by cursor: an OFFSET walk over a history that a
		// sync or a delete changes mid-read skips or repeats a run (§ 1936).
		const walk = await walkKeyset(RUN_ORDER, page, { start: opts?.after ?? null });
		// A history that ended short is not a shorter history: the export and
		// the totals would present the missing runs as never having existed.
		if (!walk.complete) {
			if (opts?.throwOnError) {
				throw dbError(walk.error ?? new Error('fetchRuns: the history walk ended short'));
			}
			console.warn('fetchRuns: the history walk ended short', walk.error);
		}
		return walk.rows;
	};

	// Defensive narrow on read: the DB CHECK constraints stop bad `source` /
	// `activity_type` values at write time, but historical rows imported
	// before the constraint, or rows from a future client whose new value
	// hasn't propagated to this build, need a fallback — and `metadata` is
	// jsonb, which admits a string, a number and an array as well as an
	// object. A projection narrows only what it selected; the unnarrowed read
	// selects every column, and says so with a literal the parser reads for
	// itself rather than with an assertion this function makes about itself.
	if (opts?.columns) {
		const columns: readonly string[] = opts.columns;
		// The cursor is read off the row, so a projection that leaves out an
		// order column selects it for the walk and drops it again: the row
		// must carry only the columns its type names (§ 1520).
		const cursorOnly = RUN_ORDER.map((k) => k.column).filter((c) => !columns.includes(c));
		// The joined list is `string`, so the parser answers `GenericStringError`
		// and the rows would be walked as errors. `Partial<RunRow>` is the honest
		// claim for a projection: which of the columns arrived is the caller's
		// tuple to say, and the overload above says it.
		const read = await collect((after, limit) =>
			build([...columns, ...cursorOnly].join(SELECT_SEPARATOR), after)
				.limit(limit)
				.overrideTypes<Partial<RunRow>[]>(),
		);
		const rows = read.map((r) => {
			const out: Record<string, unknown> = { ...r };
			for (const c of cursorOnly) delete out[c];
			return out as Partial<RunRow>;
		});
		return rows.map(asProjectedRun);
	}
	const rows = await collect((after, limit) => build('*', after).limit(limit));
	return rows.map((r) => asRun(r, null));
}

/// Runs for the signed-in user that surface a hard fetch failure instead of
/// degrading to `[]`. `fetchRuns` returns an empty list on a network / DB
/// error, which is indistinguishable from a brand-new account with zero runs
/// — so the /runs + /history surfaces showed the "log your first run"
/// onboarding card (with no retry) on a transient failure. This sibling
/// distinguishes the two: `error` is non-null only on a real failure; a
/// genuinely-empty result is `{ runs: [], error: null }`. Mirrors the
/// `fetchFoodLogWithError` convention. A signed-out caller is empty, not an
/// error (nothing to load yet).
///
/// With a `limit` it is one load-more page, and `next` is the cursor to pass
/// back as `after` for the page that follows — null once a short page says
/// the history is exhausted, and always null for an unlimited read.
export async function fetchRunsWithError(
	opts?: Omit<FetchRunsOptions, 'columns'>,
): Promise<{ runs: Run[]; error: string | null; next: KeysetCursor | null }> {
	try {
		const runs = await fetchRuns({ ...opts, throwOnError: true });
		const next = opts?.limit != null ? nextCursor(RUN_ORDER, runs, opts.limit) : null;
		return { runs, error: null, next };
	} catch (e) {
		return { runs: [], error: thrownMessage(e) || 'Failed to load runs', next: null };
	}
}

/// Column-narrowed, date-windowed run fetch for the dashboard (window
/// contract + rationale in `./dashboard_runs`); the select carries exactly
/// the columns the dashboard's consumers read (streaks, training-load,
/// race-predictor, consistency, intensity, trend, goals, snapshot,
/// this-week, weekly mileage chart, recent list, the no-plan recent-5K
/// suggestion) — `metadata` stays because those consumers
/// read `avg_bpm` / `elevation_m` / `indoor` from it. `track` is NOT set — it
/// is a lazy Storage download rather than a column, so it is not one of the
/// eleven and `DashboardRun` does not declare it. `fetchRuns` answers the same
/// way for a narrowed read and sets it only for `select('*')`, whose row type
/// is the whole of `Run`.
/// The `started_at desc` order means the PostgREST 1000-row cap, if a
/// very high-volume runner ever hits it inside the window, drops only
/// the oldest rows in the window — never the recent ones any consumer
/// reads. Lifetime headline numbers come from `fetchRunAllTimeStats`.
/// Reports the read error: almost every card on /dashboard derives from this
/// one set, so degrading to `[]` rendered a complete, convincing brand-new
/// account — zero runs, no PRs, an empty week — to a runner mid-outage.
export const DASHBOARD_RUN_COLUMNS = [
	'id',
	'user_id',
	'started_at',
	'distance_m',
	'duration_s',
	'source',
	'activity_type',
	'is_dnf',
	'elevation_gain_m',
	'metadata',
	'fastest_5k_s',
] as const satisfies RunColumns;

/// What the dashboard read carries, and what `fetchRunsForDashboard` declares.
export type DashboardRun = Pick<Run, (typeof DASHBOARD_RUN_COLUMNS)[number]>;

export async function fetchRunsForDashboard(): Promise<{
	runs: DashboardRun[];
	error: string | null;
}> {
	const userId = auth.user?.id;
	if (!userId) return { runs: [], error: null };
	const windowStart = dashboardRunsWindowStart(new Date());
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select(
			DASHBOARD_RUN_COLUMNS.join(SELECT_SEPARATOR) as Join<
				typeof DASHBOARD_RUN_COLUMNS,
				typeof SELECT_SEPARATOR
			>,
		)
		.eq('user_id', userId)
		.gte('started_at', windowStart.toISOString())
		.order('started_at', { ascending: false });
	if (error) return { runs: [], error: error.message };
	if (!data) return { runs: [], error: null };
	return {
		// All three narrowed on read, the same defence `fetchRunById` applies one
		// row at a time. `activity_type` and `source` are CHECK-constrained
		// `text` and `metadata` is jsonb, so the generated row types them
		// `string` / `string` / `Json` while the client unions promise less; the
		// widening cast this replaced meant the dashboard was the one read that
		// applied none of them. `track` is NOT set — it is not one of the eleven
		// columns, so `DashboardRun` does not carry it.
		runs: data.map((r) => ({
			...r,
			source: parseRunSource(r.source),
			activity_type: parseActivityType(r.activity_type),
			metadata: parseRunMetadata(r.metadata),
		})),
		error: null,
	};
}

/// Cheap all-time aggregates for the dashboard's two lifetime stat cards
/// (Total runs / Longest run — labelled "all sources" / "all time").
/// `fetchRunsForDashboard` windows to ~2 years for the recency cards,
/// which would silently truncate these lifetime numbers for a deep-history
/// runner — the exact Strava-migrant case the old unbounded scan protected.
/// A count-only HEAD read plus a single-row max keep them exact without
/// shipping any run payload. Scoped to the signed-in user (RLS + explicit
/// filter, matching every other personal-data read here).
export async function fetchRunAllTimeStats(): Promise<{
	totalRuns: number;
	longestRunM: number;
}> {
	const userId = auth.user?.id;
	if (!userId) return { totalRuns: 0, longestRunM: 0 };
	const [countRes, longestRes] = await Promise.all([
		supabase
			.from(TABLES.runs)
			.select('id', { count: 'exact', head: true })
			.eq('user_id', userId),
		supabase
			.from(TABLES.runs)
			.select('distance_m')
			.eq('user_id', userId)
			.order('distance_m', { ascending: false })
			.limit(1),
	]);
	return {
		totalRuns: countRes.error ? 0 : countRes.count ?? 0,
		longestRunM:
			longestRes.error || !longestRes.data?.[0]
				? 0
				: longestRes.data[0].distance_m ?? 0,
	};
}

/// All-time current + best run streak for the dashboard streak card, from
/// the `run_streaks_for_user` gaps-and-islands aggregate (migration
/// 20270501_001, decisions § 471) — one row, one round trip, so the
/// paint-path card never needs the pre-window history the ~2-year
/// `fetchRunsForDashboard` window drops. The RPC buckets by the LOCAL day
/// the display-side `computeRunStreaks` helper uses, so the browser's IANA
/// zone is passed; `source` mirrors the dashboard's source-filter chips so
/// the sub-label's all-time claim stays true under a filter. Returns null —
/// never zeros — on any failure: unlike `fetchRunAllTimeStats`' degrade-to-0
/// (a lifetime card showing 0 is visibly broken), a zeroed streak is
/// indistinguishable from a truthful one, so the caller must suppress the
/// all-time claim instead (streak_card.ts).
export async function fetchRunStreaks(
	source?: RunSource | null,
): Promise<{ current: number; best: number } | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	let tz = 'UTC';
	try {
		tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
	} catch {
		/* keep UTC */
	}
	const { data, error } = await supabase.rpc('run_streaks_for_user', {
		p_tz: tz,
		...(source ? { p_source: source } : {}),
	}, { get: true });
	const row = data?.[0];
	if (error || !row) return null;
	return { current: row.current_streak ?? 0, best: row.best_streak ?? 0 };
}

/// Exactly the columns `PeriodSummary` reads. The period drilldown has to
/// ship every row — it lists them — so the saving is per-row width, not row
/// count: no `metadata` jsonb bag, no elevation, no DNF flag.
export const PERIOD_SUMMARY_RUN_COLUMNS = [
	'id',
	'started_at',
	'distance_m',
	'duration_s',
	'source',
] as const satisfies RunColumns;

/// A run as the period drilldown reads it — the five values it renders, and
/// nothing it can read `undefined` off.
export type PeriodSummaryRun = Pick<Run, (typeof PERIOD_SUMMARY_RUN_COLUMNS)[number]>;

/// Complete run history for a `PeriodSummary`, column-narrowed to the five
/// values it renders. Both drilldown entry points use it: the standalone
/// /dashboard/period route, and the dashboard modal's lazy load when the
/// requested period reaches past `DASHBOARD_RUNS_WINDOW_DAYS`. Throws on a
/// fetch error so the caller can show a retry rather than a total that is
/// silently short.
export async function fetchRunsForPeriodSummary(): Promise<PeriodSummaryRun[]> {
	return fetchRuns({ columns: PERIOD_SUMMARY_RUN_COLUMNS, throwOnError: true });
}

/// Exactly the columns the recap engine reads off an in-period run: the
/// distance / duration totals, elevation (with the legacy `metadata.
/// elevation_m` fallback `elevationOf` still honours), the activity type
/// behind the run-family longest / fastest rules, and the route id for the
/// unique-route tally. `source` rides along because `fetchRuns` narrows it on
/// every row it returns.
export const RECAP_RUN_COLUMNS = [
	'id',
	'started_at',
	'distance_m',
	'duration_s',
	'elevation_gain_m',
	'activity_type',
	'route_id',
	'source',
	'metadata',
] as const satisfies RunColumns;

/// A run as the recap engine reads it.
export type RecapRun = Pick<Run, (typeof RECAP_RUN_COLUMNS)[number]>;

/// Runs shaped for a recap card, without the lifetime `select('*')` scan both
/// pages used to do — ~3,000 full rows, `metadata` bag and all, to render a
/// card built from the ~250 inside the year (a monthly card, ~20).
///
/// Two reads instead of one: the recap year at `RECAP_RUN_COLUMNS`, plus every
/// run's `started_at` and nothing else. The recap engine reaches a run outside
/// the period only through `computeRunStreaks`, which reads that one column,
/// so the second read reproduces `bestStreakDays` / `currentStreakDays`
/// exactly — including a streak that crosses 31 Dec (`recap.test.ts` pins the
/// engine's dependency, `recap_window.test.ts` pins the equivalence). Both
/// recap routes take the whole year: the monthly card carries the year's
/// twelve-month strip.
export async function fetchRunsForRecap(year: number): Promise<RecapRun[]> {
	const win = recapYearWindow(year);
	const [windowed, allStartedAt] = await Promise.all([
		fetchRuns({
			columns: RECAP_RUN_COLUMNS,
			startedAtFrom: win.fromIso,
			startedAtBefore: win.beforeIso,
		}),
		fetchRuns({ columns: ['started_at'] as const }),
	]);
	return mergeRecapRuns(
		windowed,
		allStartedAt.map((r) => r.started_at),
		win,
	);
}

/// Supplementary counts for the Year-in-Running recap that can't be
/// derived from `Run` rows alone (see `recap.ts#RecapExtras`): photos
/// attached to the year's runs, and personal records achieved during the
/// year. Both are scoped to the signed-in user (RLS + an explicit filter,
/// matching every other personal-data read here). Year bounds are UTC;
/// the recap aggregate itself buckets runs by local year, so a run within
/// a few hours of the boundary can disagree — acceptable for headline
/// counts on a wrap-up card.
export async function fetchRecapExtras(
	year: number,
): Promise<{ photoCount: number; personalRecordCount: number }> {
	const userId = auth.user?.id;
	if (!userId) return { photoCount: 0, personalRecordCount: 0 };
	const start = `${year}-01-01T00:00:00Z`;
	const end = `${year + 1}-01-01T00:00:00Z`;

	const [photos, prs] = await Promise.all([
		supabase
			.from(TABLES.run_photos)
			.select('id, runs!inner(started_at)', { count: 'exact', head: true })
			.eq('owner_id', userId)
			.gte('runs.started_at', start)
			.lt('runs.started_at', end),
		supabase
			.from(TABLES.personal_records)
			.select('user_id', { count: 'exact', head: true })
			.eq('user_id', userId)
			.gte('achieved_at', start)
			.lt('achieved_at', end),
	]);

	return {
		photoCount: photos.error ? 0 : photos.count ?? 0,
		personalRecordCount: prs.error ? 0 : prs.count ?? 0,
	};
}

/// Publish (or re-publish) a recap as a public, OG-unfurlable snapshot and
/// return its share id (the uuid in the /recap/share/[id] link). Owner-only:
/// RLS rejects writes for any other user. The snapshot is FROZEN aggregate
/// data only (totals / badges / monthly strip) — no GPS, no per-run rows.
/// Upserts on (user_id, period_kind, period_key) so re-publishing the same
/// period refreshes the same link instead of minting a new one. Returns null
/// when signed-out or the write fails (the caller surfaces the failure).
export async function publishRecap(
	periodKind: RecapPeriodKind,
	periodKey: string,
	snapshot: YearInRunningRecap,
): Promise<string | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from(TABLES.public_recaps)
		.upsert(
			{
				user_id: userId,
				period_kind: periodKind,
				period_key: periodKey,
				snapshot: snapshot as unknown as Json,
			},
			{ onConflict: 'user_id,period_kind,period_key' },
		)
		.select('id')
		.single();
	if (error || !data) {
		console.warn('publishRecap failed', error);
		return null;
	}
	return data.id;
}

/// Fetch a published recap snapshot by its share id. Anon-readable via the
/// public_recap_by_id RPC (the id is the capability token; the bare table is
/// not enumerable — migration 20270305_001). Used by the public share page;
/// returns null when the id doesn't resolve (never published, or revoked).
export async function fetchPublicRecap(
	id: string,
): Promise<{ periodKind: RecapPeriodKind; periodKey: string; snapshot: YearInRunningRecap } | null> {
	const { data, error } = await supabase
		.rpc('public_recap_by_id', { p_id: id }, { get: true })
		.maybeSingle();
	const row = data as {
		period_kind?: string | null;
		period_key?: string | null;
		snapshot?: unknown;
	} | null;
	if (error || !row?.period_kind || !row.period_key) return null;
	return {
		periodKind: row.period_kind as RecapPeriodKind,
		periodKey: row.period_key,
		snapshot: row.snapshot as unknown as YearInRunningRecap,
	};
}

/// Owner-scoped single-run read. Reports the transport/RLS error separately
/// from a null row: supabase-js resolves `{data: null, error}` rather than
/// throwing, so collapsing both into `null` made an unreachable backend
/// indistinguishable from a deleted run and rendered "Run not found".
export async function fetchRunById(
	id: string
): Promise<{ run: Run | null; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { run: null, error: null };
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('*')
		.eq('id', id)
		.eq('user_id', userId)
		.single();

	// PGRST116 is "no rows matched" — a genuine not-found (or not-owner),
	// not a failure to find out.
	if (error && error.code !== 'PGRST116') return { run: null, error: error.message };
	if (!data) return { run: null, error: null };

	// Lazy-load the GPS track from Storage when the run has one.
	let track = null;
	if (data.track_url) {
		try {
			track = await fetchOwnerTrack(data.track_url, data.user_id, data.id, data.metadata);
		} catch (e) {
			console.warn('Failed to fetch track', e);
		}
	}
	return { run: asRun(data, track), error: null };
}

/// The owner's run-detail track: the stored waypoints plus, for a track that
/// carries no smoothed pair of its own (a watch run, an old run the server
/// recomputed), the job_worker's smoothed-position sidecar merged on when the
/// run's metadata names these exact bytes and the sidecar's own fingerprint
/// agrees (`runs/smoothed_sidecar.ts`). A run whose metadata names no sidecar
/// for this track makes no sidecar request. The sidecar is an auxiliary layer
/// over the track: any failure to fetch or read it leaves the raw line, and is
/// not an error.
async function fetchOwnerTrack(path: string, userId: string, runId: string, metadata: unknown) {
	const { data, error } = await supabase.storage.from(BUCKETS.runs).download(path);
	if (error || !data) throw error ? dbError(error) : new Error('No data');
	const decompressed = await decompressGzip(await data.arrayBuffer());
	const points = JSON.parse(new TextDecoder().decode(decompressed));
	if (!Array.isArray(points) || !needsSmoothedSidecar(points)) return points;
	try {
		const sha256 = await sha256Hex(decompressed);
		if (!sidecarNamedFor(metadata, sha256)) return points;
		const { data: sc, error: scErr } = await supabase.storage
			.from(BUCKETS.runs)
			.download(smoothedSidecarPath(userId, runId));
		if (scErr || !sc) return points;
		const sidecar = JSON.parse(new TextDecoder().decode(await decompressGzip(await sc.arrayBuffer())));
		return mergeSmoothedSidecar(points, sidecar, { points: points.length, sha256 });
	} catch (e) {
		console.warn('smoothed sidecar unreadable; drawing the raw line', { run_id: runId, error: e });
		return points;
	}
}

/// Fetch every run by the signed-in user against `routeId`, ordered
/// by duration ascending so the caller can read off PB / rank without
/// re-sorting. Used by the Route History panel on `/runs/[id]`. The
/// returned rows are the column subset `route_history.ts` declares —
/// no track download.
export async function fetchRunsOnRoute(
	routeId: string,
): Promise<{ id: string; route_id: string | null; distance_m: number; duration_s: number; activity_type: string | null }[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('id, route_id, distance_m, duration_s, activity_type')
		.eq('user_id', userId)
		.eq('route_id', routeId)
		.order('duration_s', { ascending: true });
	if (error || !data) return [];
	return data;
}

/**
 * Download a gzipped GPS track from the `runs` Storage bucket.
 * Throws if the path is invalid or the user can't read it.
 */
async function fetchTrack(path: string) {
	const { data, error } = await supabase.storage.from(BUCKETS.runs).download(path);
	if (error || !data) throw error ? dbError(error) : new Error('No data');
	const buf = await data.arrayBuffer();
	const decompressed = await decompressGzip(buf);
	const json = new TextDecoder().decode(decompressed);
	return JSON.parse(json);
}

/// Public wrapper for list-page thumbnail fetches. Same pipeline as
/// the detail-page track loader but exposed so the runs list can lazy-
/// download track blobs as cards scroll into view. **Owner-only path** —
/// the per-user-folder Storage policy from 20260410_001 gates access to
/// `(storage.foldername(name))[1] = auth.uid()::text`. Non-owner viewers
/// must use [fetchClippedTrackForRun] instead, which routes through the
/// `clip-public-track` Edge Function so the privacy-zone clip happens
/// server-side and the unclipped blob never crosses the wire.
///
/// Every caller draws the track (the runs-list thumbnail, the personal
/// heatmap, the owner's share page), so it returns the line: the stored
/// off-track fixes, kept only for the server's distance replay, are dropped
/// here (`trackLine`), as `clip-public-track` drops them for a non-owner.
export async function fetchTrackByPath(path: string) {
	const points = await fetchTrack(path);
	return Array.isArray(points) ? trackLine(points) : points;
}

/// Owner-only fetch of the indoor/treadmill HR sidecar
/// (`{user_id}/{run_id}.hr.json.gz`, decisions §116). Same Storage pipeline as
/// the track. Returns the `{ bpm, ts? }` series; used by the run-detail HR-zone
/// breakdown when the GPS track carries no per-point bpm. The sidecar holds no
/// location, so unlike the track there is no non-owner / clipped variant — it
/// is never exposed off the owner's own run detail.
export async function fetchHrSeries(
	path: string,
): Promise<Array<{ bpm: number; ts?: string }>> {
	const series = await fetchTrack(path);
	if (!Array.isArray(series)) return [];
	return series.filter(
		(s): s is { bpm: number; ts?: string } =>
			!!s && typeof s.bpm === 'number',
	);
}

/// Privacy-aware non-owner track fetcher. Calls the `clip-public-track`
/// Edge Function which downloads the gzipped track via service-role,
/// passes the points through `clip_track_for_user`, and returns the
/// clipped result. Use this on every non-owner surface where the old
/// pattern was "fetchTrackByPath then clipTrackForUser client-side" —
/// that pattern leaked the unclipped blob (audit/storage High,
/// closed by migration 20260619_001 dropping the public-runs Storage
/// policy).
export async function fetchClippedTrackForRun(runId: string) {
	const { data, error } = await supabase.functions.invoke('clip-public-track', {
		body: { run_id: runId },
	});
	if (error) throw dbError(error);
	const points = (data as { points?: unknown })?.points;
	if (!Array.isArray(points)) {
		throw new Error('clip-public-track returned malformed payload');
	}
	return points;
}

/// Server-side privacy-zone-clipped waypoints for a route owned by
/// someone other than the caller. Routes carry waypoints inline as a
/// jsonb column (no Storage indirection like runs), so this is a
/// straight RPC rather than an Edge Function. The SECURITY DEFINER
/// function checks visibility (owner / public / club member), then
/// returns either unclipped waypoints (owner) or clipped output
/// (non-owner). Anon callers (no JWT) only get public routes.
///
/// Use on every non-owner route render site — the bare `route.waypoints`
/// from a `routes` row is the unclipped polyline and must not reach
/// the renderer when the viewer != owner. Decisions §33.
export async function fetchClippedRouteForViewer(
	routeId: string,
): Promise<Array<{ lat: number; lng: number }>> {
	const { data, error } = await supabase.rpc(
		'clip_route_for_viewer',
		{ p_route_id: routeId },
		{ get: true },
	);
	if (error) {
		// Fail closed — returning the unclipped waypoints on RPC error
		// would defeat the helper's purpose. Render an empty polyline
		// rather than leak — the same fail-closed rule every privacy-zone
		// clipping path follows.
		console.warn('clip_route_for_viewer failed; failing closed (empty route)', error);
		return [];
	}
	if (!Array.isArray(data)) return [];
	return data as Array<{ lat: number; lng: number }>;
}

export type RouteMatchCandidate = {
	id: string;
	name: string;
	distanceM: number;
	startOffsetM: number;
	endOffsetM: number;
};

/// Auto-link helper: given a recorded run's track, ask the DB which
/// of the user's saved routes it overlaps. Backed by the
/// routes_intersecting_track RPC (migration 20260610_001) which
/// uses the routes.geom GIST index to pre-filter candidates.
///
/// Caller decides the final ranking. The combination
/// (start_offset + end_offset < 2 * tolerance) AND
/// (|distance_m - track_length| / track_length < 0.20) is a strong
/// "definitely the same route" signal. A single low-offset candidate
/// with that distance match is auto-link-worthy; multiple candidates
/// or a length mismatch should defer to user confirmation.
export async function fetchRoutesIntersectingTrack(
	track: import('#lib/types.ts').TrackPoint[],
	toleranceM = 100,
	maxResults = 10,
): Promise<RouteMatchCandidate[]> {
	const userId = auth.user?.id;
	// Matched on the line: an off-track fix is distance input, not path.
	const line = trackLine(track);
	if (!userId || line.length < 2) return [];
	const geojson = {
		type: 'LineString' as const,
		coordinates: line.map(lineLngLat),
	};
	const { data, error } = await supabase.rpc('routes_intersecting_track', {
		caller_user_id: userId,
		track_geojson: geojson,
		tolerance_m: toleranceM,
		max_results: maxResults,
	});
	if (error || !data) return [];
	return (data as Array<{
		id: string;
		name: string;
		distance_m: number;
		start_offset_m: number;
		end_offset_m: number;
	}>).map((r) => ({
		id: r.id,
		name: r.name,
		distanceM: Number(r.distance_m),
		startOffsetM: Number(r.start_offset_m),
		endOffsetM: Number(r.end_offset_m),
	}));
}

/// Persist runs.route_id. Used by the auto-link suggestion on
/// /runs/[id] and by any future "save as route" flow that wants
/// to back-link the run to its source.
export async function linkRunToRoute(runId: string, routeId: string): Promise<void> {
	markListsStale('runs', 'history', 'routes');
	const { error } = await supabase.from(TABLES.runs).update({ route_id: routeId }).eq('id', runId);
	if (error) throw dbError(error);
}

export type MatchStatus = 'pending' | 'matched' | 'failed' | 'skipped';

export type RunMatchInfo = {
	status: MatchStatus;
	algorithm: string | null;
	algorithmVersion: string | null;
	matchedAt: string | null;
	track: import('#lib/types.ts').TrackPoint[] | null;
};

/// Fetch the run_matched_tracks row for a run + lazily download the
/// matched track when status='matched'. The owner-read RLS policy
/// gates this — non-owners get an empty result and the caller falls
/// back to the raw track. L4 per docs/architecture/conventions.md § Layered
/// resilience: the matched track is an enhancement on top of the
/// raw track that already renders; a failure here must NOT break
/// the run-detail page.
export async function fetchRunMatchedTrack(
	runId: string,
): Promise<RunMatchInfo | null> {
	const { data, error } = await supabase
		.from('run_matched_tracks')
		.select('status, matched_track_url, algorithm, algorithm_version, matched_at')
		.eq('run_id', runId)
		.maybeSingle();
	if (error || !data) return null;

	let track: import('#lib/types.ts').TrackPoint[] | null = null;
	if (data.status === 'matched' && data.matched_track_url) {
		try {
			track = (await fetchTrack(data.matched_track_url)) as import('#lib/types.ts').TrackPoint[];
		} catch (e) {
			console.warn('Failed to fetch matched track', e);
		}
	}
	return {
		status: data.status as MatchStatus,
		algorithm: data.algorithm,
		algorithmVersion: data.algorithm_version,
		matchedAt: data.matched_at,
		track,
	};
}

/// Force a fresh map-match for a run the caller owns. Resets
/// run_matched_tracks to pending and queues a `map_match` job. The
/// PostgREST RPC self-gates on auth.uid() = run.user_id; non-owner
/// calls get a 42501 error which we surface to the toast layer.
/// Idempotent against in-flight jobs (jobs_dedupe_map_match unique
/// index) — calling twice while a previous re-match is queued is a
/// no-op.
export async function enqueueRunRematch(runId: string): Promise<void> {
	const { error } = await supabase.rpc('enqueue_run_rematch', { p_run_id: runId });
	if (error) throw dbError(error);
}

/// Queue a server-side recompute of a run's distance from its stored track
/// with the GPS distance estimator (docs/features/gps_distance.md § Server
/// recompute). The RPC raises 42501 unless the caller owns the run and 22000
/// when the run has no track; both are thrown for the caller to surface. A
/// second request while one is in flight is a no-op server-side.
export async function requestDistanceRecompute(runId: string): Promise<void> {
	const { error } = await supabase.rpc('request_distance_recompute', { p_run_id: runId });
	if (error) throw dbError(error);
}

/** Decompress a gzipped ArrayBuffer using the browser's DecompressionStream. */
async function decompressGzip(buf: ArrayBuffer): Promise<Uint8Array> {
	const ds = new (globalThis as any).DecompressionStream('gzip');
	const stream = new Response(buf).body!.pipeThrough(ds);
	const chunks: Uint8Array[] = [];
	const reader = stream.getReader();
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value as Uint8Array);
	}
	const total = chunks.reduce((a, c) => a + c.length, 0);
	const out = new Uint8Array(total);
	let offset = 0;
	for (const c of chunks) {
		out.set(c, offset);
		offset += c.length;
	}
	return out;
}

export async function fetchPublicRun(
	id: string,
): Promise<{ run: Run | null; error: string | null }> {
	// Public reads go through the public_runs view (decisions §33,
	// migration 20260626_001) which strips external_id, redacts the
	// metadata bag's audit / sync / training-plan-linkage keys, and
	// nulls route_id / event_id when the joined target isn't public.
	// The view's where clause is `is_public = true` so the dropped
	// `.eq('is_public', true)` filter is redundant.
	//
	// Track is *not* fetched here: the audit (storage High) flagged that
	// loading raw bytes inline meant a future maintainer using `r.track`
	// for non-owners would bypass the privacy-zone clipping required by
	// decisions §33. RunShareView already branches on owner — owner takes
	// the direct Storage path via fetchTrack(); non-owner takes
	// fetchClippedTrackForRun(). This function only returns the row.
	const { data, error } = await supabase
		.from('public_runs')
		.select('*')
		.eq('id', id)
		.single();

	// PGRST116 is "no rows matched" — the run is private, deleted, or was
	// never there. Anything else is a failure to find out, and collapsing the
	// two rendered "Run not found" to every recipient of a shared link
	// whenever the read merely failed. `fetchRunById` was fixed for exactly
	// this and says so; the public half is the one strangers hit, and a
	// stranger has no way to tell a broken read from a deleted run.
	if (error && error.code !== 'PGRST116') return { run: null, error: error.message };
	if (!data) return { run: null, error: null };
	return { run: { ...data, track: null } as Run, error: null };
}

/// The non-owner read of a run that is NOT public but whose audience admits
/// the caller — the owner's followers for a followers-only run, or a named
/// recipient of a `run_shares` grant (migration 20270802000003). `shared_runs`
/// carries exactly `public_runs`' redacted projection, never a public run and
/// never the caller's own, so everything said about `fetchPublicRun` holds
/// here: no track (the clipped one comes from `fetchClippedTrackForRun`), and
/// a failed read is reported apart from "not shared with you".
export async function fetchSharedRun(
	id: string,
): Promise<{ run: Run | null; error: string | null }> {
	const { data, error } = await supabase
		.from('shared_runs')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (error) return { run: null, error: error.message };
	if (!data) return { run: null, error: null };
	return { run: { ...data, track: null } as Run, error: null };
}

/// Every non-owner read of a run in one call: public first, then shared with
/// this caller. Anonymous callers stop at public — they belong to no audience,
/// and `shared_runs` is not granted to anon.
export async function fetchViewableRun(
	id: string,
): Promise<{ run: Run | null; error: string | null; shared: boolean }> {
	const pub = await fetchPublicRun(id);
	if (pub.error || pub.run) return { ...pub, shared: false };
	if (!(await currentViewerId())) return { run: null, error: null, shared: false };
	const shared = await fetchSharedRun(id);
	return { ...shared, shared: shared.run !== null };
}

export interface PublicRunAttribution {
	ownerId: string;
	displayName: string | null;
	avatarUrl: string | null;
}

/// Resolve "may this signed-in viewer see a run they don't own, and whose
/// is it" for the non-owner branch of `/runs/[id]`.
///
/// The entitlement IS the `public_runs` row existing: the view's where
/// clause is `is_public = true` (20260626_001 and successors) and it runs
/// as its owner, so a returned row means the run is publicly readable.
/// Comment + kudos writes are gated independently by
/// `private.is_run_visible_to` (20260812_001) and the block filter
/// (20270204_001), so nothing here grants engagement rights.
///
/// Returns no run fields on purpose. The redacted row and the
/// privacy-zone-clipped track are fetched by `RunShareView`, which the
/// non-owner branch mounts — the clipped-track path (decisions §33) must
/// stay the single way a non-owner track reaches a renderer.
///
/// A coach reading an athlete's *private* run is deliberately not routed
/// here: `active coach reads athlete runs` (20261103_001) grants SELECT on
/// the row but the raw GPS trace stays owner-only (decisions §98), so that
/// surface is `/coaching/athletes/[id]`.
export async function fetchPublicRunAttribution(
	runId: string,
): Promise<{ attribution: PublicRunAttribution | null; error: string | null }> {
	// Reported separately for the same reason `fetchRunById` reports it: the
	// caller decides whether the viewer is a non-owner or whether nothing has
	// been established yet, and an errored read is evidence of neither.
	const { data: run, error } = await supabase
		.from('public_runs')
		.select('user_id')
		.eq('id', runId)
		.maybeSingle();
	if (error) return { attribution: null, error: error.message };
	let ownerId = (run as { user_id?: string | null } | null)?.user_id;
	if (!ownerId) {
		// Not public: the run may still be shared with this viewer — a
		// followers-only run they follow the owner for, or a named-person grant
		// (20270802000003). Same projection, same single column.
		const { data: shared, error: sharedError } = await supabase
			.from('shared_runs')
			.select('user_id')
			.eq('id', runId)
			.maybeSingle();
		if (sharedError) return { attribution: null, error: sharedError.message };
		ownerId = (shared as { user_id?: string | null } | null)?.user_id;
	}
	if (!ownerId) return { attribution: null, error: null };
	// The display name is decoration on an entitlement already established by
	// the row above, so its own failure degrades to an unnamed owner rather
	// than withdrawing the entitlement.
	const { data: profile } = await supabase
		.from('user_profiles')
		.select('display_name, avatar_url')
		.eq('id', ownerId)
		.maybeSingle();
	const p = profile as { display_name?: string | null; avatar_url?: string | null } | null;
	return {
		attribution: {
			ownerId,
			displayName: p?.display_name ?? null,
			avatarUrl: p?.avatar_url ?? null,
		},
		error: null,
	};
}

export async function deleteRun(id: string): Promise<void> {
	// Best-effort sweep of attached Storage objects before the row delete:
	//   - the gzipped track file in the `runs` bucket
	//   - every photo blob in the `run-photos` bucket
	// The DB cascade deletes the `run_photos` rows when the run is gone,
	// but the bytes orphan in Storage and continue paying for storage
	// indefinitely. (Visibility is closed by the Storage SELECT policy
	// since the row-cascade kills the join target — but unreachable
	// orphan bytes still occupy the bucket.) Audit/storage Medium fix.
	const { data: run } = await supabase
		.from(TABLES.runs)
		.select('user_id, track_url, hr_series_url')
		.eq('id', id)
		.single();
	// The GPS track, the indoor HR series, and the job_worker's map-matched
	// track and smoothed-position sidecar (whose rows cascade away without
	// their bytes; removing a path that is not there is a no-op) are removed
	// alongside the row so the bucket doesn't accumulate orphans.
	const orphanPaths = [
		run?.track_url,
		run?.hr_series_url,
		run?.user_id ? smoothedSidecarPath(run.user_id, id) : null,
		run?.user_id ? `${run.user_id}/${id}.matched.json.gz` : null,
	].filter((p): p is string => !!p);
	if (orphanPaths.length > 0) {
		try {
			await supabase.storage.from(BUCKETS.runs).remove(orphanPaths);
		} catch (e) {
			// Don't log the storage path — it embeds the user's auth
			// UUID and would land in Sentry breadcrumbs. The Sentry
			// hook redacts known signed-URL patterns but the row's
			// storage path doesn't match those. The run id is
			// sufficient to triangulate from server logs.
			console.warn('deleteRun: storage removal failed (orphaned file)', { run_id: id, error: e });
		}
	}
	const { data: photos } = await supabase
		.from(TABLES.run_photos)
		.select('storage_path, thumb_512_path')
		.eq('run_id', id);
	if (photos && photos.length > 0) {
		// Sweep both the original upload AND the worker-generated 512-wide
		// thumbnail. Until the audit/storage pass landed, `deleteRun` only
		// removed `storage_path`; the row cascade-deleted (so the Storage
		// SELECT policy hides the bytes via the run_photos join) but the
		// thumbnail blob persisted in the bucket indefinitely, paying for
		// storage cost and leaving a latent privacy footprint. Both paths
		// are best-effort — the row delete is more important than the
		// file cleanup.
		const paths = photos
			.flatMap((p: { storage_path: string | null; thumb_512_path: string | null }) => [
				p.storage_path,
				p.thumb_512_path,
			])
			.filter((p: string | null): p is string => !!p);
		if (paths.length > 0) {
			try {
				await supabase.storage.from(BUCKETS.run_photos).remove(paths);
			} catch (e) {
				console.warn('deleteRun: photo storage removal failed (orphaned files)', { run_id: id, count: paths.length, error: e });
			}
		}
	}
	markListsStale('runs', 'history', 'routes');
	const { error } = await supabase.from(TABLES.runs).delete().eq('id', id);
	if (error) throw dbError(error);
}

/// Delete a batch of runs plus their Storage track files. One RLS-scoped
/// REST call per delete because Supabase's batch delete doesn't return
/// the pre-delete `track_url` we need to clean up Storage. Each delete is
/// up to five sequential REST + Storage round-trips, so the ids are
/// processed in bounded `DELETE_RUNS_CONCURRENCY`-sized waves rather than
/// all at once — a full-page selection otherwise fires hundreds of
/// simultaneous requests. The wave orchestration lives in the pure
/// `deleteRunsBounded` so it is unit-testable without this Supabase-backed
/// module. Individual failures don't stop the rest; returns the failed ids.
export async function deleteRuns(ids: string[]): Promise<{ failed: string[] }> {
	return deleteRunsBounded(ids, deleteRun);
}

/// Flip a route's visibility. Mirrors the Android
/// `ApiClient.setRoutePublic` signature — bidirectional (public ↔
/// private) rather than the one-way `makeRoutePublic` the old Share
/// flow assumed. RLS guards ownership; the caller should still gate
/// the UI so non-owners never see the control.
export async function setRoutePublic(id: string, isPublic: boolean): Promise<void> {
	markListsStale('routes');
	const { error } = await supabase
		.from('routes')
		.update({ is_public: isPublic })
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Flip a run's visibility. Bidirectional (public ↔ private) like its
/// `setRoutePublic` sibling — the one-way `makeRunPublic` it replaces
/// left a live-shared run permanently exposed (issue #251). Flipping
/// to private revokes the /share/run link and the /live spectator
/// page. RLS guards ownership; the caller should still gate the UI
/// so non-owners never see the control.
export async function setRunPublic(id: string, isPublic: boolean): Promise<void> {
	markListsStale('runs', 'history', 'routes');
	const { error } = await supabase
		.from(TABLES.runs)
		.update({ is_public: isPublic })
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Which entity an audience control is acting on. The two grant tables and
/// the two base tables have the same shape, so one set of helpers serves both.
export type ShareableKind = 'run' | 'route';

/// One named person a run or route is shared with, for the owner's list.
export interface ShareRecipient {
	recipientId: string;
	displayName: string | null;
	avatarUrl: string | null;
	createdAt: string;
}

/// Whether the followers level and named-person shares are live (the server's
/// `private.feature_flags` row, decisions § 1874). The audience control
/// renders only when this is true. Fail-closed: any read failure is "off", and
/// is not cached, so a later mount can find out.
let audienceSharingProbe: Promise<boolean> | null = null;
export function audienceSharingEnabled(): Promise<boolean> {
	if (audienceSharingProbe) return audienceSharingProbe;
	const probe = (async () => {
		try {
			const { data, error } = await supabase.rpc('audience_sharing_enabled', undefined, { get: true });
			if (error) {
				audienceSharingProbe = null;
				return false;
			}
			return data === true;
		} catch {
			audienceSharingProbe = null;
			return false;
		}
	})();
	audienceSharingProbe = probe;
	return probe;
}

/// The owner's live grants on one run or route, oldest first, with each
/// recipient's display name. RLS returns only the owner's own grants (and a
/// recipient's own), so a non-owner calling this gets at most their own row.
export async function fetchShares(kind: ShareableKind, id: string): Promise<ShareRecipient[]> {
	const { data: rows, error } =
		kind === 'run'
			? await supabase
					.from('run_shares')
					.select('recipient_id, created_at')
					.eq('run_id', id)
					.order('created_at', { ascending: true })
					.order('recipient_id', { ascending: true })
			: await supabase
					.from('route_shares')
					.select('recipient_id, created_at')
					.eq('route_id', id)
					.order('created_at', { ascending: true })
					.order('recipient_id', { ascending: true });
	if (error) throw dbError(error);
	const ids = (rows ?? []).map((r) => r.recipient_id);
	if (ids.length === 0) return [];
	const { data: profiles, error: profilesError } = await queryChunked(ids, (part) =>
		supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', part)
	);
	if (profilesError) throw dbError(profilesError);
	const byId = new Map((profiles ?? []).map((p) => [p.id, p] as const));
	return (rows ?? []).map((r) => ({
		recipientId: r.recipient_id,
		displayName: byId.get(r.recipient_id)?.display_name ?? null,
		avatarUrl: byId.get(r.recipient_id)?.avatar_url ?? null,
		createdAt: r.created_at,
	}));
}

/// Share one run or route with one person. The INSERT policy admits only the
/// owner, only while audience sharing is on, and only for a recipient with a
/// follow edge either way and no block (20270802000002) — the same set the
/// picker offers. A repeat share of the same person is a no-op, not an error.
export async function addShare(kind: ShareableKind, id: string, recipientId: string): Promise<void> {
	const ownerId = await currentViewerId();
	if (!ownerId) throw new Error('Not authenticated');
	const { error } =
		kind === 'run'
			? await supabase.from('run_shares').insert({ run_id: id, owner_id: ownerId, recipient_id: recipientId })
			: await supabase
					.from('route_shares')
					.insert({ route_id: id, owner_id: ownerId, recipient_id: recipientId });
	if (error && !isDuplicateKeyError(error)) throw dbError(error);
}

/// Revoke one person's access. It ends on their next read: nothing is copied
/// to them, so there is nothing to recall. A delete RLS refused comes back as
/// zero rows rather than an error, so the row count is checked and a refusal
/// is reported instead of being shown as a revoke.
export async function revokeShare(kind: ShareableKind, id: string, recipientId: string): Promise<void> {
	const { data, error } =
		kind === 'run'
			? await supabase
					.from('run_shares')
					.delete()
					.eq('run_id', id)
					.eq('recipient_id', recipientId)
					.select('recipient_id')
			: await supabase
					.from('route_shares')
					.delete()
					.eq('route_id', id)
					.eq('recipient_id', recipientId)
					.select('recipient_id');
	if (error) throw dbError(error);
	if (!data || data.length === 0) throw new Error(m('audience.revokeRefused'));
}

/// Move a run or route to a level. Only me revokes every grant first, so the
/// row never claims "only me" while a named reader is still admitted; the
/// other levels leave grants in place (moot while wider, back in force if the
/// owner narrows again). Specific people writes the same columns as Only me —
/// its audience is the grants the caller adds with [addShare].
export async function setAudience(kind: ShareableKind, id: string, level: AudienceLevel): Promise<void> {
	if (kind === 'run') markListsStale('runs', 'history', 'routes');
	else markListsStale('routes');
	if (levelRevokesGrants(level)) {
		const { error } =
			kind === 'run'
				? await supabase.from('run_shares').delete().eq('run_id', id)
				: await supabase.from('route_shares').delete().eq('route_id', id);
		if (error) throw dbError(error);
	}
	const columns = audienceColumns(level);
	const { data, error } =
		kind === 'run'
			? await supabase.from(TABLES.runs).update(columns).eq('id', id).select('id')
			: await supabase.from('routes').update(columns).eq('id', id).select('id');
	if (error) throw dbError(error);
	if (!data || data.length === 0) throw new Error(m('audience.updateRefused'));
}

/// Persist at most one fitness snapshot per user per UTC day. The dashboard
/// call path computes the snapshot on every open (cheap — pure math over the
/// run list the dashboard already fetched) and persists so the trend chart has
/// a history to draw; without the per-day gate a runner who opens /dashboard
/// three times a day fills the chart's 60-point window with same-day
/// duplicates inside about two and a half weeks.
///
/// Read-then-insert rather than an upsert, deliberately. `fitness_snapshots`
/// carries self SELECT / INSERT / DELETE policies and no UPDATE one, so
/// PostgREST's `ON CONFLICT DO UPDATE` would be refused by RLS; and the
/// conflict target is a derived day, which `on_conflict=` cannot name. This
/// shape is correct on a database with no uniqueness constraint at all, and
/// once `fitness_snapshots_user_day_uniq` exists a second tab racing the read
/// gets a 23505 — the state we wanted, not a failure.
export async function insertFitnessSnapshot(input: {
	vdot: number | null;
	vo2Max: number | null;
	acuteLoad: number | null;
	chronicLoad: number | null;
	trainingStressBal: number | null;
	qualifyingRunCount: number;
}): Promise<void> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) return;
	// Don't spam writes — only persist when the user has enough data
	// for the numbers to mean something. Anything less is just noise
	// on the trend chart.
	if (
		input.vdot == null &&
		input.chronicLoad == null &&
		input.qualifyingRunCount < 3
	) {
		return;
	}
	const { data: latest, error: latestErr } = await supabase
		.from(TABLES.fitness_snapshots)
		.select('computed_at')
		.eq('user_id', userId)
		.order('computed_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (latestErr) {
		console.warn('insertFitnessSnapshot: latest-snapshot read failed', supabaseErrorFields(latestErr));
		return;
	}
	if (!fitnessSnapshotDue((latest as { computed_at: string } | null)?.computed_at, new Date())) {
		return;
	}
	const { error } = await supabase.from(TABLES.fitness_snapshots).insert({
		user_id: userId,
		vdot: input.vdot,
		vo2_max: input.vo2Max,
		acute_load: input.acuteLoad,
		chronic_load: input.chronicLoad,
		training_stress_bal: input.trainingStressBal,
		qualifying_run_count: input.qualifyingRunCount,
		source: 'client',
	});
	// A PostgREST error resolves rather than throws, so the caller's catch
	// cannot see this one — the write used to fail entirely silently.
	if (error && !isDuplicateKeyError(error)) {
		console.warn('insertFitnessSnapshot failed', supabaseErrorFields(error));
	}
}

export interface FitnessSnapshotRow {
	computed_at: string;
	vdot: number | null;
	vo2_max: number | null;
	acute_load: number | null;
	chronic_load: number | null;
	training_stress_bal: number | null;
}

/// Fetch recent snapshots for the trend chart. Ordered oldest → newest
/// so a Svelte `{#each}` draws the chart left-to-right.
export async function fetchFitnessSnapshots(limit = 60): Promise<FitnessSnapshotRow[]> {
	const { data } = await supabase
		.from(TABLES.fitness_snapshots)
		.select('computed_at, vdot, vo2_max, acute_load, chronic_load, training_stress_bal')
		.order('computed_at', { ascending: false })
		.limit(limit);
	const rows = (data as FitnessSnapshotRow[] | null) ?? [];
	return rows.slice().reverse();
}

/// Save a run's GPS track as a reusable saved route. Runs the track
/// through Douglas-Peucker to shed GPS jitter before persisting (same
/// 10 m epsilon the Android path uses), sums elevation gain, and
/// inserts a `routes` row for the current user. Throws if the run has
/// no track (manual-entry runs); the caller should gate the button.
/// `track` carries the run's chosen altitude series and
/// `elevationMinDeltaM` its noise band (`runAltitude`), so the route's
/// climb is the figure the run page showed.
///
/// Returns the new route id so the caller can navigate to it.
export async function saveRunAsRoute(
	runId: string,
	name: string,
	track: Array<{ lat: number; lng: number; ele?: number | null }>,
	elevationMinDeltaM?: number,
): Promise<{ id: string }> {
	const { summarizeRouteFromTrack } = await import('../routes/route_simplify');
	if (track.length < 2) throw new Error('Not enough GPS points to save a route');
	const { waypoints, distance_m, elevation_m } = summarizeRouteFromTrack(
		track,
		10,
		elevationMinDeltaM,
	);

	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');

	markListsStale('runs', 'history', 'routes');
	const { data, error } = await supabase
		.from('routes')
		.insert({
			user_id: userId,
			// Defence in depth — the call site already trims, but a
			// future non-prompt caller (bulk run→route conversion, an
			// automation) shouldn't be able to write whitespace.
			name: name.trim(),
			waypoints,
			distance_m,
			elevation_m,
			is_public: false,
		})
		.select('id')
		.single();
	if (error) throw dbError(error);

	// Back-link the run to its new route for convenience on the
	// run-detail page. Best-effort — the route insert is the important
	// bit. Swallow any RLS or FK miss silently.
	try {
		await supabase.from(TABLES.runs).update({ route_id: data.id }).eq('id', runId);
	} catch (e) {
		console.warn('saveRunAsRoute: back-link update failed', e);
	}

	return { id: data.id };
}

/// Insert a manually-entered run. No GPS track, no track file —
/// `track_url` stays null and downstream readers (run detail map,
/// dashboards) already handle the "no track" path. `source` is always
/// `'app'` so the run picks up the "Recorded" label in the UI; the
/// `metadata.manual_entry = true` flag lets the detail page show
/// "Manual entry" instead of the map.
/// Map the user's `privacy_default` preference to the visibility columns of a
/// newly-created run: `public` → public, `followers` → `followers_only`, else
/// owner-only (`social/run_visibility.ts`, decisions § 1875). Web once
/// ignored the preference entirely, so a runner who chose `public` still got
/// private runs from web saves + imports (comeback persona #27); until the
/// followers level existed, `followers` collapsed to owner-only. Fail-closed:
/// any settings-read failure → owner-only.
async function defaultRunAudience(userId: string): Promise<AudienceColumns> {
	try {
		const settings = await loadSettings(userId);
		return privacyDefaultToAudience(effective<string>(settings, 'privacy_default', 'private'));
	} catch {
		return audienceColumns('private');
	}
}

/// The columns a writer stores: an explicit per-run choice wins, otherwise the
/// runner's default. A caller that passes only `isPublic` (the importers'
/// historical shape) chose between public and owner-only.
async function runAudienceFor(
	userId: string,
	input: { isPublic?: boolean; followersOnly?: boolean },
): Promise<AudienceColumns> {
	if (input.isPublic === undefined && input.followersOnly === undefined) {
		return defaultRunAudience(userId);
	}
	const isPublic = input.isPublic === true;
	return { is_public: isPublic, followers_only: !isPublic && input.followersOnly === true };
}

export async function createManualRun(input: {
	startedAt: string; // ISO UTC
	durationS: number;
	distanceM: number;
	activityType?: 'run' | 'walk' | 'hike' | 'cycle' | 'stroller';
	notes?: string | null;
	routeId?: string | null;
	/// Per-run visibility override. When both are omitted, falls back to the
	/// user's `privacy_default` preference (`public` → public, `followers` →
	/// followers-only, else owner-only).
	isPublic?: boolean;
	followersOnly?: boolean;
}): Promise<{ id: string }> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const audience = await runAudienceFor(userId, input);

	const metadata: JsonObject = {
		[METADATA_KEYS.manual_entry]: true,
	};
	if (input.notes && input.notes.trim()) metadata[METADATA_KEYS.notes] = input.notes.trim();

	markListsStale('runs', 'history', 'routes');
	const { data, error } = await supabase
		.from(TABLES.runs)
		.insert({
			user_id: userId,
			started_at: input.startedAt,
			duration_s: input.durationS,
			distance_m: input.distanceM,
			source: 'app',
			activity_type: input.activityType ?? 'run',
			metadata,
			route_id: input.routeId ?? null,
			is_public: audience.is_public,
			followers_only: audience.followers_only,
		})
		.select('id')
		.single();
	if (error) throw dbError(error);
	const runId = data.id as string;

	await recomputeChallengesForRun(input.startedAt);

	return { id: runId };
}

/// Insert a run from an importer (Strava zip, GPX bulk, etc). Uploads
/// an optional `track` to the Storage bucket and stores the path in
/// `track_url`. For callers without a GPS track, pass `track: undefined`
/// and the row is saved without one, same as a scalar row from parkrun.
export async function saveRun(input: {
	started_at: string;
	distance_m: number;
	duration_s: number;
	elevation_m: number | null;
	source: string;
	/// Real `runs.activity_type` column (20261207_001). Defaults to 'run'.
	activity_type?: 'run' | 'walk' | 'hike' | 'cycle' | 'stroller';
	/// Promoted embedded-best columns (20270325_001) — seconds of the fastest
	/// rolling window per canonical distance, from computeEmbeddedBests.
	/// Written as real runs columns, never metadata keys.
	embedded_bests?: Partial<
		Record<'fastest_5k_s' | 'fastest_10k_s' | 'fastest_half_marathon_s' | 'fastest_marathon_s', number>
	>;
	metadata: JsonObject | null;
	track?: Array<{ lat: number; lng: number; ele?: number; ts?: string; bpm?: number }>;
	/// Per-point HR for a trackless (indoor / treadmill) run. Uploaded as the
	/// `{user_id}/{run_id}.hr.json.gz` sidecar only when `track` carries no bpm,
	/// so the run-detail HR-zone chart has a series without faking coordinates
	/// (decisions §116). Ignored when the track already has per-point bpm.
	hrSeries?: Array<{ bpm: number; ts?: string }>;
	title?: string | null;
	/// Cross-source dedupe key (e.g. `strava:1234567`, `csv:<iso>-<dist>-<dur>`).
	/// Saved into runs.external_id so a subsequent import of the same
	/// activity by any path can detect + skip. /audit/strava M3.
	external_id?: string | null;
	/// Per-run visibility override. When both are omitted, falls back to the
	/// user's `privacy_default` preference. Importers omit them so a bulk
	/// import honours the runner's default visibility.
	isPublic?: boolean;
	followersOnly?: boolean;
}): Promise<{ id: string; trackUploaded: boolean; trackError?: string }> {
	const { data: authUser } = await supabase.auth.getUser();
	const userId = authUser.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const audience = await runAudienceFor(userId, input);

	// `title` has no DB column, so it survives the round-trip in metadata only.
	// `elevation_m` is different: migration 20270302_001 promoted total ascent to
	// the first-class `runs.elevation_gain_m` column and its contract is that
	// "writers populate both" — the jsonb key for the readers that still use it
	// (recap fallback, export, the Go worker) and the column for the ones that
	// sum it in SQL. The vert challenge aggregate sums the COLUMN, so writing
	// only the metadata key leaves every vert leaderboard stuck at 0 m.
	// See docs/backend/metadata.md for the registered keys.
	const mergedMetadata: JsonObject = { ...(input.metadata ?? {}) };
	if (input.title) mergedMetadata[METADATA_KEYS.title] = input.title;
	if (input.elevation_m != null) mergedMetadata[METADATA_KEYS.elevation_m] = input.elevation_m;
	const row: Insertable<'runs'> = {
		user_id: userId,
		started_at: input.started_at,
		distance_m: input.distance_m,
		duration_s: input.duration_s,
		source: input.source,
		activity_type: input.activity_type ?? 'run',
		metadata: mergedMetadata,
		is_public: audience.is_public,
		followers_only: audience.followers_only,
	};
	if (input.elevation_m != null) row.elevation_gain_m = input.elevation_m;
	if (input.embedded_bests) Object.assign(row, input.embedded_bests);
	if (input.external_id) row.external_id = input.external_id;

	markListsStale('runs', 'history', 'routes');
	const { data, error } = await supabase
		.from(TABLES.runs)
		.insert(row)
		.select('id')
		.single();
	if (error) throw dbError(error);
	const runId = data.id as string;

	// Track upload runs as a separate transaction (no DB-level FK between
	// the row and the storage object). When it fails the scalar run row
	// is still valid — the readers (web, mobile) treat a null
	// `track_url` as "no track" and render fine. We surface the failure
	// to the caller so importers can report "X imported with tracks,
	// Y scalar-only" and interactive callers can show a toast +
	// retry button instead of silently shipping a GPS-less run.
	let trackUploaded = false;
	let trackError: string | undefined;
	if (input.track && input.track.length >= 2) {
		try {
			const path = `${userId}/${runId}.json.gz`;
			const encoded = new TextEncoder().encode(JSON.stringify(input.track));
			const gzipped = await gzipBytes(encoded);
			const { error: upErr } = await supabase.storage
				.from(BUCKETS.runs)
				.upload(path, new Blob([gzipped as BlobPart], { type: 'application/gzip' }), {
					contentType: 'application/gzip',
					upsert: true,
				});
			if (upErr) {
				trackError = upErr.message;
			} else {
				const { error: linkErr } = await supabase
					.from(TABLES.runs)
					.update({ track_url: path })
					.eq('id', runId);
				if (linkErr) {
					trackError = linkErr.message;
				} else {
					trackUploaded = true;
				}
			}
		} catch (e) {
			trackError = thrownMessage(e);
		}
	}

	// HR sidecar for a trackless run (indoor / treadmill). Only when the track
	// carries no per-point bpm — an outdoor run's HR already rides on the track
	// points, so a sidecar would be redundant. Failure is non-fatal (same
	// contract as the track upload): the row's scalar avg_bpm still renders.
	const trackHasBpm = !!input.track?.some((p) => p.bpm != null);
	if (trackHasBpm && input.hrSeries && input.hrSeries.length > 0) {
		// Mixed run (GPS records + fix-less HR records, e.g. a treadmill warm-up
		// stretch). The track's per-point bpm drives the zone chart, so the
		// fix-less hrSeries is intentionally dropped — but surface it so the
		// partial-coverage case isn't silently invisible. (decisions §116)
		console.warn(
			`saveRun: ${input.hrSeries.length} fix-less HR samples dropped — track already carries per-point bpm`,
		);
	}
	if (!trackHasBpm && input.hrSeries && input.hrSeries.length >= 1) {
		try {
			const path = `${userId}/${runId}.hr.json.gz`;
			const encoded = new TextEncoder().encode(JSON.stringify(input.hrSeries));
			const gzipped = await gzipBytes(encoded);
			const { error: upErr } = await supabase.storage
				.from(BUCKETS.runs)
				.upload(path, new Blob([gzipped as BlobPart], { type: 'application/gzip' }), {
					contentType: 'application/gzip',
					upsert: true,
				});
			if (upErr) {
				console.warn('hr-series sidecar upload failed', upErr.message);
			} else {
				// Mirror the track-upload error handling: a PostgREST error here is
				// a resolved { error }, not a throw, so the outer catch can't see
				// it — check it explicitly or the sidecar orphans silently.
				const { error: linkErr } = await supabase
					.from(TABLES.runs)
					.update({ hr_series_url: path })
					.eq('id', runId);
				if (linkErr) {
					console.warn('hr-series sidecar row-link failed', linkErr.message);
				}
			}
		} catch (e) {
			console.warn('hr-series sidecar upload failed', e);
		}
	}

	await recomputeChallengesForRun(input.started_at);

	return { id: runId, trackUploaded, trackError };
}

async function gzipBytes(data: Uint8Array): Promise<Uint8Array> {
	const cs = new (globalThis as any).CompressionStream('gzip');
	// TS 6 widened Uint8Array.buffer to ArrayBufferLike; Response()
	// wants BodyInit which excludes SharedArrayBuffer-backed views.
	// Cast is safe because data is always backed by a real ArrayBuffer.
	const stream = new Response(data as BodyInit).body!.pipeThrough(cs);
	const chunks: Uint8Array[] = [];
	const reader = stream.getReader();
	while (true) {
		const { done, value } = await reader.read();
		if (done) break;
		chunks.push(value as Uint8Array);
	}
	const total = chunks.reduce((a, c) => a + c.length, 0);
	const out = new Uint8Array(total);
	let offset = 0;
	for (const c of chunks) {
		out.set(c, offset);
		offset += c.length;
	}
	return out;
}

/// Save the run-detail edit made on [loaded], the row as the page last read
/// it, as a compare-and-swap on its server `updated_at` (decisions § 2147):
/// an edit never writes over a change made elsewhere since the page loaded
/// to a field it also changes, and reports that as a `conflict` with the
/// server's copy instead. `isDnf` rides the same write when the dialog
/// changed it: `runs.is_dnf` is a real column (20261207_001), and setting it
/// true drops the run from personal-records scoring.
///
/// Title / notes are trimmed and an empty-after-trim key is removed from the
/// bag rather than left as `""`; mobile's run-detail edit applies the same
/// normalisation (`data_normalise.ts` holds the contract).
export async function updateRunMetadata(
	loaded: Run,
	fields: RunEditFields,
	isDnf?: boolean,
): Promise<RunEditOutcome<Run>> {
	return saveRunEdit<Run>(
		{
			swap: async (patch, base) => {
				markListsStale('runs', 'history', 'routes');
				const filtered = supabase.from(TABLES.runs).update(patch).eq('id', loaded.id);
				const { data, error } = await (base === null
					? filtered.is('updated_at', null)
					: filtered.eq('updated_at', base)
				).select('*');
				if (error) throw dbError(error);
				return (data ?? []).map((row) => asRun(row, loaded.track));
			},
			reload: async () => {
				const { data, error } = await supabase
					.from(TABLES.runs)
					.select('*')
					.eq('id', loaded.id)
					.maybeSingle();
				if (error) throw dbError(error);
				return data ? asRun(data, loaded.track) : null;
			},
		},
		loaded,
		fields,
		isDnf,
	);
}

// --- Route reviews ---

export async function getRouteReviews(routeId: string, limit = 100) {
	const { data, error } = await supabase
		.from(TABLES.route_reviews)
		.select('*')
		.eq('route_id', routeId)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error) throw dbError(error);
	return data ?? [];
}

export async function upsertRouteReview(review: {
	route_id: string;
	rating: number;
	comment?: string | null;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from(TABLES.route_reviews).upsert(
		{ ...review, user_id: userId },
		{ onConflict: 'route_id,user_id' },
	);
	if (error) throw dbError(error);
}

/// Delete the signed-in user's own review of a route. Scoped by
/// `(route_id, user_id)` — the table's unique key — rather than by review
/// id so a caller can't be tricked into aiming the delete at someone else's
/// row; the "users delete their own reviews" RLS policy is the hard gate.
export async function deleteRouteReview(routeId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.route_reviews)
		.delete()
		.eq('route_id', routeId)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

// --- Routes ---

/// The public-route catalogue near a point. `nearby_routes` is declared
/// `setof public_routes`, so what comes back is the view's fifteen columns and
/// not a `routes` row — `PublicRouteSummary` says so rather than casting past
/// it to a `Route` the RPC cannot produce (§ 1328).
export async function nearbyPublicRoutes(options: {
	lat: number;
	lng: number;
	radiusM?: number;
	limit?: number;
}): Promise<PublicRouteSummary[]> {
	const { lat, lng, radiusM = 50000, limit = 50 } = options;
	const { data, error } = await supabase.rpc('nearby_routes', {
		lat,
		lng,
		radius_m: radiusM,
		max_results: limit,
	}, { get: true });
	if (error || !data) return [];
	return data as PublicRouteSummary[];
}

/// The public-route catalogue search, one keyset page at a time: pass the
/// previous page's `next` as `after` (with the SAME filters and sort) to load
/// more.
///
/// Reads the `public_routes` view directly rather than through the
/// `search_public_routes` RPC (dropped in 20270817000001). The RPC paged by
/// `p_offset`, and an offset is a position: a route published or unpublished
/// between two reads moves every later position, so "load more" repeated or skipped a route — and none of its
/// three orders was total, so two routes sharing a `created_at` could swap
/// between reads. The view is the RPC's own source (same visibility: public,
/// not shadow-hidden, club id redacted) and is granted to anon + authenticated,
/// so the filters move here verbatim and the order gains `id` from
/// `publicRouteOrder`, whose prefix keeps the RPC's per-sort partial indexes
/// (migration 20270326_001) serving it. Mirrors `ApiClient.searchPublicRoutes`.
export async function searchPublicRoutes(options?: {
	query?: string;
	minDistanceM?: number;
	maxDistanceM?: number;
	surface?: string;
	tags?: string[];
	featuredOnly?: boolean;
	sort?: PublicRouteSort;
	limit?: number;
	after?: KeysetCursor | null;
}): Promise<KeysetPage<PublicRouteSummary>> {
	const {
		query,
		minDistanceM,
		maxDistanceM,
		surface,
		tags,
		featuredOnly,
		sort = 'newest',
		limit = 50,
	} = options ?? {};

	const order = publicRouteOrder(sort);
	const after = options?.after ? keysetAfter(order, options.after) : undefined;
	if (after === null) return { rows: [], next: null };

	let q = supabase.from('public_routes').select('*');
	const trimmed = query?.trim();
	// Every character of the query matches literally: `ilike` would read `*`
	// (PostgREST's alias for `%`), `%`, `_` and `\` as wildcards.
	if (trimmed) q = q.regexIMatch('name', literalSubstringPattern(trimmed));
	if (minDistanceM != null) q = q.gte('distance_m', minDistanceM);
	if (maxDistanceM != null) q = q.lte('distance_m', maxDistanceM);
	// Treat empty-string surface the same as no filter — matches mobile's
	// `ApiClient.searchPublicRoutes`, which gates on `surface.isNotEmpty`.
	// `surface = ''` matches no rows, so passing it through showed an empty
	// result list rather than the full catalogue.
	if (surface && surface.length > 0) q = q.eq('surface', surface);
	if (tags && tags.length > 0) q = q.overlaps('tags', tags);
	if (featuredOnly) q = q.eq('is_featured', true);
	if (after) q = q.or(after);
	for (const k of order) {
		q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
	}
	const { data, error } = await q.limit(limit);
	// Throw on error rather than collapsing to []: the sole caller
	// (RouteExplorer) needs to tell a genuine load failure apart from a
	// legitimately empty result so it can show a retry affordance instead
	// of a misleading "no matches" empty state.
	if (error) throw dbError(error);
	const rows = data ?? [];
	return { rows: rows as PublicRouteSummary[], next: nextCursor(order, rows, limit) };
}

/// The set of tags currently used across any public route, ordered by
/// most-used. Powers the filter chip row on /explore.
///
/// Goes through the `popular_route_tags` RPC (migration 20260502_001;
/// rewritten in 20260703_001 to read from the `public_routes` view).
/// The RPC aggregates server-side with `count(*)` + `order by count desc,
/// tag asc`, so the result is stable, cap-free, and matches mobile's
/// `ApiClient.fetchPopularRouteTags` byte-for-byte.
///
/// The previous client-side aggregation was capped at 500 rows (a
/// known limitation noted in the original comment); past that the
/// chip row would silently mis-represent the popular-tag tail.
export async function fetchPopularRouteTags(limit = 20): Promise<string[]> {
	const { data } = await supabase.rpc('popular_route_tags', {
		tag_limit: limit,
	}, { get: true });
	if (!Array.isArray(data)) return [];
	return (data as Array<{ tag: string }>).map((r) => r.tag);
}

export async function updateRouteTags(routeId: string, tags: string[]): Promise<void> {
	markListsStale('routes');
	const { error } = await supabase
		.from('routes')
		.update({ tags, updated_at: new Date().toISOString() })
		.eq('id', routeId);
	if (error) throw dbError(error);
}

/// Toggle the star/favorite flag on a route. Starred routes are what
/// the watch fetches at run prep time — curating here surfaces the
/// runner's training rotation on a 1.4-inch picker that can't show
/// 30+ entries comfortably.
export async function setRouteStar(routeId: string, starred: boolean): Promise<void> {
	markListsStale('routes');
	const { error } = await supabase
		.from('routes')
		.update({ is_starred: starred, updated_at: new Date().toISOString() })
		.eq('id', routeId);
	if (error) throw dbError(error);
}

export async function fetchRoutes(): Promise<RouteListItem[]> {
	const result = await fetchRoutesWithError();
	return result.routes;
}

/// Reason string for a failed routes read: message plus the PostgREST code
/// when there is one, which is what tells a reporting user whether they hit a
/// policy or a transport fault.
function describeReadError(e: { message: string; code?: string | null }): string {
	return `${e.message}${e.code ? ` (${e.code})` : ''}`;
}

/// Same as `fetchRoutes` but returns the error message alongside the
/// rows. Callers that want to surface a failure to the user (rather
/// than silently rendering an empty state — which is indistinguishable
/// from "user has no routes") use this variant.
///
/// "My routes" is the union of routes the user uploaded (`user_id = me`)
/// and routes they've bookmarked (`saved_routes.user_id = me`). Each is
/// fetched in parallel and merged with a Set on `id` so a user who saves
/// their own route doesn't see it twice.
export async function fetchRoutesWithError(): Promise<{
	routes: RouteListItem[];
	error: string | null;
}> {
	// Read the session via `getSession()` — synchronous-ish from local
	// storage, doesn't round-trip to /auth/v1/user, and works the
	// instant the supabase-js client has initialised. Falls back to
	// just running the query and letting RLS decide if no session is
	// found, since the user might be in the brief hydration window.
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;

	if (!userId) {
		return { routes: [], error: 'Not signed in — sign in to see your saved routes.' };
	}

	const [ownedRes, savedIdsRes] = await Promise.all([
		supabase
			.from('routes')
			.select(ROUTE_LIST_COLS)
			.eq('user_id', userId)
			.order('created_at', { ascending: false }),
		supabase
			.from('saved_routes')
			.select('route_id, saved_at')
			.eq('user_id', userId)
			.order('saved_at', { ascending: false }),
	]);

	if (ownedRes.error) {
		console.error('fetchRoutes (owned) failed', ownedRes.error);
		return { routes: [], error: describeReadError(ownedRes.error) };
	}

	const owned = (ownedRes.data ?? []) as unknown as RouteListItem[];

	// Saved routes can't be embedded as `route:routes(*)` off saved_routes:
	// the base `routes` SELECT RLS only exposes the caller's own + club
	// routes, so a bookmarked route owned by ANOTHER user (the dominant
	// case — you save other people's routes from Explore) joins to null and
	// silently vanishes from My routes. Read the saved bodies by id from the
	// `public_routes` view (which exposes every public route's metadata,
	// the same privacy-preserving path Explore uses — waypoints stay behind
	// clip_route_for_viewer) AND the base table (for own / club-visible
	// saved routes), then union, preferring the fuller base-table row.
	//
	// A failed saved-route read is not an empty bookmark list. `?? []` on any
	// of the three below reported the runner's own routes with `error: null`
	// and their bookmarks silently gone — inside the one function in this file
	// whose whole shape exists to keep that from happening. The page renders
	// the banner INSTEAD of the list, so a partial answer would still be
	// hidden; report the failure and let the retry button do its job.
	if (savedIdsRes.error) {
		console.error('fetchRoutes (saved ids) failed', savedIdsRes.error);
		return { routes: [], error: describeReadError(savedIdsRes.error) };
	}
	const savedIds = ((savedIdsRes.data ?? []) as { route_id: string }[]).map(
		(r) => r.route_id,
	);
	let saved: RouteListItem[] = [];
	if (savedIds.length > 0) {
		const [savedBaseRes, savedPublicRes] = await Promise.all([
			queryChunked(savedIds, (part) =>
				supabase.from('routes').select(ROUTE_LIST_COLS).in('id', part)
			),
			queryChunked(savedIds, (part) =>
				supabase.from('public_routes').select(PUBLIC_ROUTE_LIST_COLS).in('id', part)
			),
		]);
		// Either half missing is a whole class of bookmark gone: the base table
		// carries the runner's own + club-visible saved routes, the view
		// carries every route they saved from someone else's — the dominant
		// case, per the comment above.
		const savedErr = savedBaseRes.error ?? savedPublicRes.error;
		if (savedErr) {
			console.error('fetchRoutes (saved bodies) failed', savedErr);
			return { routes: [], error: describeReadError(savedErr) };
		}
		const byId = new Map<string, RouteListItem>();
		for (const r of [
			...((savedBaseRes.data ?? []) as unknown as RouteListItem[]),
			...((savedPublicRes.data ?? []) as unknown as PublicRouteListRow[]).map((r) => ({
				...r,
				...publicRouteListFill()
			})),
		]) {
			if (!byId.has(r.id)) byId.set(r.id, r);
		}
		// Preserve the saved_at-desc order the id list already carries.
		saved = savedIds
			.map((id) => byId.get(id))
			.filter((r): r is RouteListItem => r != null);
	}

	const seen = new Set<string>();
	const merged: RouteListItem[] = [];
	for (const r of [...owned, ...saved]) {
		if (seen.has(r.id)) continue;
		seen.add(r.id);
		merged.push(r);
	}
	return { routes: merged, error: null };
}

/// One `routes` row as the `Route` every consumer reads it as.
///
/// Three things separate the two, and each read used to do a different subset
/// of them. `shadow_hidden` is server-/trigger-owned moderation state
/// (migration 20270218_001) that the read boundary is otherwise unanimous
/// about stripping (§ 1327). `surface` is a CHECK-constrained union the
/// generated row types as a bare `string`. And `waypoints` is jsonb, typed
/// `Json`, which is not the non-nullable `TrackPoint[]` the client type
/// promises. `fetchClubRoutes` and `saveRoute` did none of the three and
/// returned the raw row as a `Route` regardless, so a club route arrived
/// carrying the moderation column and an unparsed surface.
///
/// A `waypoints` that is not an array becomes `[]` rather than being asserted
/// through: a line the consumer can iterate is the promise, and § 1229 is
/// exactly the failure of handing back `undefined` under a type that says
/// otherwise.
function asRoute(row: Database['public']['Tables']['routes']['Row']): Route {
	const { shadow_hidden: _moderation, waypoints, surface, ...rest } = row;
	return {
		...rest,
		waypoints: Array.isArray(waypoints) ? (waypoints as unknown as TrackPoint[]) : [],
		surface: parseRouteSurface(surface),
	};
}

/// Routes owned by a club (`routes.club_id = clubId`). Read-gated by
/// RLS to club members; admin-write-gated for transfers/edits. Used by
/// the club home Routes tab and by EventEditor's route picker.
export async function fetchClubRoutes(clubId: string): Promise<Route[]> {
	const { data, error } = await supabase
		.from('routes')
		.select('*')
		.eq('club_id', clubId)
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchClubRoutes failed', error);
		return [];
	}
	return (data ?? []).map(asRoute);
}

/// Bookmark a public route. Inserts a `saved_routes` reference rather
/// than cloning the row — see decisions.md § 30.
export async function bookmarkRoute(routeId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('saved_routes')
		.insert({ user_id: userId, route_id: routeId });
	// Treat duplicate (already saved) as a no-op.
	if (error && !isDuplicateKeyError(error)) throw dbError(error);
}

export async function unbookmarkRoute(routeId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('saved_routes')
		.delete()
		.eq('user_id', userId)
		.eq('route_id', routeId);
	if (error) throw dbError(error);
}

/// Transfer a personal route into club ownership (admins only) — or
/// back out (`clubId = null`). Server-side RLS enforces that only
/// admins of the target club may set `club_id`.
export async function setRouteClubId(routeId: string, clubId: string | null): Promise<void> {
	markListsStale('routes');
	const { error } = await supabase
		.from('routes')
		.update({ club_id: clubId, updated_at: new Date().toISOString() })
		.eq('id', routeId);
	if (error) throw dbError(error);
}

/// The viewer the READ is authorised as, rather than the one the reactive
/// store has got round to.
///
/// A page awaits `auth.ready()` before its mount-time fetch, but that gate
/// resolves on its own timeout when the initial session check is WEDGED
/// (`stores/auth_ready.ts`), so the fetch can still run with `auth.user`
/// null. supabase-js has the persisted token by then regardless, so PostgREST
/// answers as the owner while the caller believes it is anon — which is how
/// `fetchRouteById` handed an owner their own route privacy-clipped, with
/// nothing re-fetching when the store caught up. `getSession()` awaits the
/// client's own initialisation and reads the same persisted session the
/// request carried, so it cannot disagree with what PostgREST saw.
///
/// The store is the fallback for a THROWN session read only, and it can only
/// ever name the viewer themselves — never another account — so a stale
/// answer can widen nothing it would not already have widened.
async function currentViewerId(): Promise<string | null> {
	try {
		const { data } = await supabase.auth.getSession();
		return data.session?.user?.id ?? null;
	} catch {
		return auth.user?.id ?? null;
	}
}

/// Read a route by id. The OWNER gets the full `routes` row directly.
/// Anon, non-owner, and non-owner club-member callers all get a
/// privacy-clipped route: the polyline is routed through
/// `clip_route_for_viewer` and `geom` / `start_point` are nulled, so
/// unclipped geometry never crosses the wire to anyone but the owner.
/// RLS also lets an active club member SELECT the base row, so the
/// owner check here — not RLS — is what stops a non-owner club member
/// from reading the unclipped waypoints. Closes the audit/public-rows
/// + audit/privacy-zones High finding.
///
/// Returns null ONLY when the row genuinely is not there (or is not
/// visible to the caller — RLS filters rows, it does not error). A
/// transport or permission failure throws, so a caller can tell "this
/// route was deleted" apart from "we could not reach the server" and
/// offer a retry instead of a headstone.
export async function fetchRouteById(id: string): Promise<Route | null> {
	const viewerId = await currentViewerId();
	const ownerRead = await supabase
		.from('routes')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (ownerRead.error) throw dbError(ownerRead.error);
	if (ownerRead.data) {
		const owned = asRoute(ownerRead.data);
		if (owned.user_id !== viewerId) {
			// RLS surfaced this base row to a non-owner (active club member).
			// Never hand back the unclipped polyline / `geom` / `start_point`;
			// route the waypoints through the same server-side privacy clip the
			// non-owner branch below uses and drop the raw geometry columns.
			const clipped = await fetchClippedRouteForViewer(id);
			return { ...owned, geom: null, start_point: null, waypoints: clipped };
		}
		return owned;
	}

	// The metadata read and the server-clip RPC both key only on `id`, so
	// fire them concurrently instead of serialising two round trips.
	//
	// A route that is not public may still be shared with this viewer — a
	// followers-only route whose owner they follow, or a named-person grant
	// (20270802000003). `shared_routes` has `public_routes`' projection, and
	// `clip_route_for_viewer` admits the same audience, so the assembled
	// shape is identical and the polyline is clipped exactly as for a public
	// route.
	const assembled = await assemblePublicRoute(
		async () => {
			const read = await supabase.from('public_routes').select('*').eq('id', id).maybeSingle();
			if (read.error) throw dbError(read.error);
			if (read.data || !viewerId) return read.data;
			const shared = await supabase.from('shared_routes').select('*').eq('id', id).maybeSingle();
			if (shared.error) throw dbError(shared.error);
			return shared.data;
		},
		() => fetchClippedRouteForViewer(id),
	);
	if (!assembled) return null;

	// public_routes intentionally omits `waypoints`, `geom`, `start_point`,
	// and `is_starred`; pad them out so downstream consumers that read
	// these keys still get a defined shape (empty arrays / nulls).
	return {
		...assembled.meta,
		waypoints: assembled.clipped,
		is_starred: false,
	} as Route;
}

/// Public-share read path. Same redaction shape as `fetchRouteById`'s
/// non-owner branch — kept as a separate export so call sites that
/// only ever intend to read a public route stay explicit.
export async function fetchPublicRoute(id: string): Promise<Route | null> {
	// Both reads key only on `id`; run them concurrently so the anon
	// share / OG-image path pays one round trip's latency, not two.
	const assembled = await assemblePublicRoute(
		async () =>
			(await supabase.from('public_routes').select('*').eq('id', id).maybeSingle()).data,
		() => fetchClippedRouteForViewer(id),
	);
	if (!assembled) return null;
	return {
		...assembled.meta,
		waypoints: assembled.clipped,
		is_starred: false,
	} as Route;
}

export async function saveRoute(route: {
	name: string;
	waypoints: { lat: number; lng: number }[];
	distance_m: number;
	elevation_m: number | null;
	surface: 'road' | 'trail' | 'mixed';
	is_public: boolean;
	club_id?: string | null;
	description?: string | null;
}): Promise<Route> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	markListsStale('routes');
	const { data, error } = await supabase
		.from('routes')
		.insert({
			user_id: userId,
			name: route.name,
			waypoints: route.waypoints,
			distance_m: route.distance_m,
			elevation_m: route.elevation_m,
			surface: route.surface,
			is_public: route.is_public,
			club_id: route.club_id ?? null,
			description: route.description?.trim() || null,
		})
		.select()
		.single();

	if (error) {
		// Surface the create_route rate-limit P0001 (migration
		// 20260907_001 — 30 routes / hour per user, generous enough for
		// bulk Strava / Garmin imports) as a friendlier "wait N minutes"
		// message instead of the raw postgres exception.
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return asRoute(data);
}

export async function deleteRoute(id: string): Promise<void> {
	const { data: photos } = await supabase
		.from(TABLES.route_photos)
		.select('storage_path, thumb_512_path')
		.eq('route_id', id);
	if (photos && photos.length > 0) {
		// Sweep route-photo blobs before the row delete. The FK cascade
		// removes the route_photos rows (so the Storage SELECT join hides
		// the bytes), but the blobs would otherwise orphan in the bucket —
		// the same gap deleteRun closes for run photos. Best-effort.
		const paths = photos
			.flatMap((p: { storage_path: string | null; thumb_512_path: string | null }) => [
				p.storage_path,
				p.thumb_512_path,
			])
			.filter((p: string | null): p is string => !!p);
		if (paths.length > 0) {
			try {
				await supabase.storage.from(BUCKETS.route_photos).remove(paths);
			} catch (e) {
				console.warn('deleteRoute: photo storage removal failed (orphaned files)', { route_id: id, count: paths.length, error: e });
			}
		}
	}
	markListsStale('routes');
	const { error } = await supabase.from('routes').delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Dashboard stats ---

export async function fetchPersonalRecords() {
	// Read the trigger-maintained `personal_records` cache rather than
	// recomputing from `runs`. The cache is already user-scoped by RLS,
	// but we add an explicit `auth.user.id` filter as defence in depth
	// — every other personal-data query in this file does the same, and
	// silently relying on RLS for the canonical read path is fragile if
	// a future policy edit slips. See migration 20260508_001.
	const userId = auth.user?.id;
	if (!userId) return [];

	const { data } = await supabase
		.from(TABLES.personal_records)
		.select('distance, best_time_s, achieved_at')
		.eq('user_id', userId);

	if (!data || data.length === 0) return [];

	// Named for the column, not for what they hold: both are registered
	// against `personal_records.distance` in check_constraint_unions.mjs, and
	// that registry keys on the declaration name inside this ten-thousand-line
	// file. `labels` and `order` are not unique by construction.
	const PR_BRACKET_LABELS: Record<string, string> = {
		'1_mile': 'Mile',
		'5k': '5k',
		'8k': '8k',
		'10k': '10k',
		'12k': '12k',
		half_marathon: 'Half Marathon',
		marathon: 'Marathon',
	};
	const PR_BRACKET_ORDER: Record<string, number> = {
		'1_mile': 0,
		'5k': 1,
		'8k': 2,
		'10k': 3,
		'12k': 4,
		half_marathon: 5,
		marathon: 6,
	};

	return data
		.slice()
		.sort((a, b) => (PR_BRACKET_ORDER[a.distance] ?? 99) - (PR_BRACKET_ORDER[b.distance] ?? 99))
		.map((r) => ({
			key: r.distance as string,
			distance: PR_BRACKET_LABELS[r.distance] ?? r.distance,
			time_s: r.best_time_s,
			date: r.achieved_at.slice(0, 10),
		}));
}

// --- Integrations ---

export async function fetchIntegrations(): Promise<Integration[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	// Filter out rows with `disconnected_at is not null` — those are
	// integrations the user disconnected (or whose grant Strava
	// revoked). The integrations row stays around for the audit
	// trail + so the UI can show "Reconnect Strava", but the
	// connected-integration list shown on /settings/integrations
	// should treat them as gone. /audit/strava High #1 + H2.
	const { data } = await supabase
		.from(TABLES.integrations)
		.select('*')
		.eq('user_id', userId)
		.is('disconnected_at', null);

	// `provider` is a CHECK-constrained union (`integrations_provider_check`)
	// that the generated row types as a bare `string`; a row whose provider the
	// build has not heard of is dropped rather than handed on as an
	// `IntegrationProvider` it is not — every consumer switches on it, and the
	// card for a provider with no branch renders as nothing either way.
	return (data ?? []).flatMap((row) => {
		const provider = parseIntegrationProvider(row.provider);
		return provider ? [{ ...row, provider }] : [];
	});
}

export async function connectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const { error } = await supabase.from(TABLES.integrations).upsert(
		{ user_id: userId, provider },
		{ onConflict: 'user_id,provider' }
	);
	if (error) throw dbError(error);
}

export async function disconnectIntegration(provider: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	// audit/strava May 2026 High #1 — Strava goes through the EF
	// so the access token gets revoked at Strava's end + vault rows
	// get wiped + `disconnected_at` is stamped. Pre-fix the path was
	// a bare DELETE on the integrations row which left vault material
	// orphaned + the Strava-side connection live indefinitely.
	if (provider === 'strava') {
		const { error: fnError } = await supabase.functions.invoke('strava-import', {
			body: { action: 'disconnect' },
		});
		// The caller renders this into "Couldn't disconnect: {error}", a slot
		// written for a reason — so it gets the function's own code, not
		// supabase-js's fixed non-2xx sentence (decisions § 904).
		if (fnError) throw new Error(await edgeFunctionErrorMessage(fnError, 'disconnect_failed'));
		return;
	}

	const { error } = await supabase
		.from(TABLES.integrations)
		.delete()
		.eq('user_id', userId)
		.eq('provider', provider);
	if (error) throw dbError(error);
}

// --- Clubs ---

// Column-level grant lockdown: `invite_token` is revoked from anon +
// authenticated (migration 20260801_001 + 20260818_001 redo). Selecting
// `*` raises 42501. Every read enumerates these safe columns; admin
// reads of `invite_token` go through the SECURITY DEFINER RPC
// `get_club_invite_token`. The arch-guard test
// `tests-e2e/cross-cutting/select-star-discipline.spec.ts` greps to
// keep this in lockstep.
// `as const` on a single-line literal — supabase-js's `.select(<cols>)`
// type-level parser needs a string-literal type to infer the row shape,
// not the `string` widening that `'a' + 'b'` concatenation produces.
// Without `as const`, every `.from('clubs').select(CLUB_SELECT_COLS)`
// falls back to `GenericStringError` and downstream type assertions
// fail svelte-check.
const CLUB_SELECT_COLS =
	'id, owner_id, name, slug, description, avatar_url, location_label, is_public, is_verified, join_policy, member_count, requires_activity_waiver, website_url, instagram_url, strava_url, facebook_url, shadow_hidden, created_at, updated_at' as const;

// Column-level grant lockdown: `meet_lat` / `meet_lng` are revoked
// from anon + authenticated (migrations 20260723_001 + 20260806_001 +
// 20260818_001 redo). Selecting `*` raises 42501. Every read
// enumerates these safe columns; the two coords are write-only
// today (no UI consumer).
const EVENT_SELECT_COLS =
	'id, club_id, title, description, starts_at, timezone, duration_min, meet_label, route_id, distance_m, pace_target_sec, capacity, author_id, created_at, updated_at, recurrence_freq, recurrence_byday, recurrence_until, recurrence_count, category, discipline, gym_template, session_plan_id, gym_routine_id, is_public' as const;

/** Browse public clubs. Most recently created first. */
export async function browseClubsWithError(
	search?: string
): Promise<{ clubs: ClubWithMeta[]; error: string | null }> {
	let query = supabase.from('clubs').select(CLUB_SELECT_COLS).eq('is_public', true);
	if (search && search.trim()) {
		// Quoted per filter: the raw term inside the `or=` tree let `,` start a
		// new filter and `)` close the tree, and ilike read `*` `%` `_` as wildcards.
		const term = search.trim();
		query = query.or(
			`${literalSubstringTerm('name', term)},${literalSubstringTerm('location_label', term)}`
		);
	}
	const { data, error } = await query.order('created_at', { ascending: false }).limit(60);
	if (error) return { clubs: [], error: error.message };
	return data ? enrichClubs(data.map(asClub)) : { clubs: [], error: null };
}

export async function browseClubs(search?: string): Promise<ClubWithMeta[]> {
	return (await browseClubsWithError(search)).clubs;
}

/// Region-aware club search. Tries to geocode the query first
/// (so "Virginia" → centroid + ~470km radius → ST_DWithin against
/// `clubs.location_point`); falls back to the same literal name /
/// label match `browseClubs` uses when geocoding doesn't resolve
/// (short query, MapTiler offline, no key, etc.). See
/// [migration 20260905_001] for the RPC.
export async function searchClubsWithError(
	query: string
): Promise<{ clubs: ClubWithMeta[]; error: string | null }> {
	const term = query.trim();
	if (!term) return browseClubsWithError();

	// Geocode in the background while we kick off the RPC. The RPC's
	// text-only path doesn't need the geocode, so we can race the two
	// only if we accept "geographic matches appear on the second
	// render" — for now, await geocoding first so the first render
	// has both branches. Geocoding usually settles in <300ms.
	const { geocodePlace } = await import('../routes/geocoding');
	const place = await geocodePlace(term);

	const { data, error } = await supabase.rpc('search_clubs', {
		p_query: term,
		p_center_lng: place?.center.lng ?? undefined,
		p_center_lat: place?.center.lat ?? undefined,
		p_radius_m: place?.radiusM ?? undefined,
		p_limit: 60,
	}, { get: true });
	if (error) {
		console.warn('search_clubs RPC failed, falling back to the name/label match', error);
		return browseClubsWithError(term);
	}
	// The RPC returns `setof clubs` — strip the columns the client
	// shape doesn't include (location_point, invite_token).
	const rows = ((data ?? []) as Record<string, unknown>[]).map((r) => ({
		id: r.id as string,
		owner_id: r.owner_id as string,
		name: r.name as string,
		slug: r.slug as string,
		description: (r.description ?? null) as string | null,
		avatar_url: (r.avatar_url ?? null) as string | null,
		location_label: (r.location_label ?? null) as string | null,
		is_public: r.is_public as boolean,
		is_verified: (r.is_verified as boolean | undefined) ?? false,
		join_policy: parseJoinPolicy(r.join_policy as string | null),
		member_count: (r.member_count ?? 0) as number,
		requires_activity_waiver: (r.requires_activity_waiver as boolean | undefined) ?? false,
		website_url: (r.website_url ?? null) as string | null,
		instagram_url: (r.instagram_url ?? null) as string | null,
		strava_url: (r.strava_url ?? null) as string | null,
		facebook_url: (r.facebook_url ?? null) as string | null,
		shadow_hidden: (r.shadow_hidden as boolean | undefined) ?? false,
		created_at: r.created_at as string,
		updated_at: r.updated_at as string,
	}));
	return enrichClubs(rows);
}

export async function searchClubs(query: string): Promise<ClubWithMeta[]> {
	return (await searchClubsWithError(query)).clubs;
}

export type EventWeekday = 'MO' | 'TU' | 'WE' | 'TH' | 'FR' | 'SA' | 'SU';

export interface PublicEventFilters {
	query?: string;
	category?: 'run' | 'cycle' | 'class' | 'social';
	cadence?: 'one_off' | 'weekly' | 'biweekly' | 'monthly';
	byday?: EventWeekday;
	paid?: 'free' | 'paid';
	/// Local time-of-day bucket — resolved against each event's timezone
	/// (UTC fallback for legacy rows). morning 05–11, afternoon 12–16, evening 17–04.
	time?: 'morning' | 'afternoon' | 'evening';
	/// "Near me / near a place" centroid. Filters by the CLUB's geocoded
	/// location_point (never the event's revoked precise meet point), so clubs
	/// without a geocoded point are excluded when this is set. See migration
	/// 20270112_001 + decisions §147.
	center?: { lng: number; lat: number };
	/// Radius in metres around `center`. Defaults to 50km server-side.
	radiusM?: number;
	limit?: number;
}

/// A discoverable public-club event (the `search_public_events` row shape:
/// event + its club's name/slug + cheapest price, if any). Distinct from
/// EventWithMeta — this is the cross-club discovery projection, not a
/// club-scoped detail row.
export interface PublicEventResult {
	id: string;
	club_id: string;
	club_name: string;
	club_slug: string;
	title: string;
	category: string;
	discipline: string | null;
	starts_at: string;
	timezone: string | null;
	duration_min: number | null;
	recurrence_freq: string | null;
	recurrence_byday: string[] | null;
	capacity: number | null;
	price_cents: number | null;
	currency: string | null;
	/// Metres from the search center to the event's club, when a `center` was
	/// supplied — else null. Derived from the already-public club point, so
	/// surfacing it as a "2.3 km away" label leaks nothing.
	distance_m: number | null;
}

/// Cross-club activity discovery (migration 20270110_001). Searches PUBLIC
/// clubs' events across the typed-events model by category / discipline /
/// cadence / weekday / paid-or-free. Backs the /social Discover tab.
export async function searchPublicEvents(
	f: PublicEventFilters = {}
): Promise<PublicEventResult[]> {
	const { data, error } = await supabase.rpc('search_public_events', {
		p_query: f.query?.trim() || undefined,
		p_category: f.category ?? undefined,
		p_cadence: f.cadence ?? undefined,
		p_byday: f.byday ?? undefined,
		p_paid: f.paid ?? undefined,
		p_time: f.time ?? undefined,
		p_center_lng: f.center?.lng ?? undefined,
		p_center_lat: f.center?.lat ?? undefined,
		p_radius_m: f.radiusM ?? undefined,
		p_limit: f.limit ?? 60,
	}, { get: true });
	if (error) {
		throw dbError(error);
	}
	return (data ?? []) as PublicEventResult[];
}

// ── Race calendar + results import (race_calendar.md, migration 20270214_001) ──

export type RaceDistanceBand = '5k' | '10k' | 'half' | 'marathon' | 'ultra';

export interface RaceListingFilters {
	query?: string;
	distance?: RaceDistanceBand;
	from?: string; // ISO date
	to?: string; // ISO date
	center?: { lng: number; lat: number };
	radiusM?: number;
	limit?: number;
	newestFirst?: boolean;
}

/// A discoverable race calendar entry (the search_race_listings projection:
/// listing cols + distance_m_away when a center was supplied).
export interface RaceListingResult {
	id: string;
	provider: string;
	provider_race_id: string | null;
	name: string;
	race_date: string;
	distance_m: number | null;
	location_label: string | null;
	entry_url: string | null;
	results_url: string | null;
	is_verified: boolean;
	distance_m_away: number | null;
}

/// Race discovery (security invoker, public clubs/listings). Mirrors
/// searchPublicEvents — proximity by the listing's geocoded location_point.
export async function searchRaceListings(
	f: RaceListingFilters = {}
): Promise<RaceListingResult[]> {
	const { data, error } = await supabase.rpc('search_race_listings', {
		p_query: f.query?.trim() || undefined,
		p_distance: f.distance ?? undefined,
		p_from: f.from ?? undefined,
		p_to: f.to ?? undefined,
		p_center_lng: f.center?.lng ?? undefined,
		p_center_lat: f.center?.lat ?? undefined,
		p_radius_m: f.radiusM ?? undefined,
		p_limit: f.limit ?? 60,
		p_newest_first: f.newestFirst || undefined
	}, { get: true });
	if (error) throw dbError(error);
	return (data ?? []) as RaceListingResult[];
}

/// One calendar listing, for the race detail page. Read through the redacted
/// `public_race_listings` view — the same projection a logged-out visitor gets
/// — so the page never depends on who submitted the race. A malformed id or a
/// missing row is `null`; a failed read throws, so the page can tell "this race
/// is gone" apart from "we could not load it".
export interface RaceListingDetail {
	id: string;
	provider: string;
	name: string;
	race_date: string;
	distance_m: number | null;
	location_label: string | null;
	entry_url: string | null;
	results_url: string | null;
	is_verified: boolean;
	/// The linked course's summary. The view fills it only while the route is
	/// public, so null covers "no course" and "a course nobody may see" alike
	/// (decisions § 2157).
	course: RaceListingCourse | null;
}

export interface RaceListingCourse {
	distanceM: number | null;
	ascentM: number | null;
	surface: string | null;
}

export async function fetchRaceListing(id: string): Promise<RaceListingDetail | null> {
	if (!isEntityId(id)) return null;
	const { data, error } = await supabase
		.from('public_race_listings')
		.select(
			'id, provider, name, race_date, distance_m, location_label, entry_url, results_url, is_verified, course_distance_m, course_elevation_m, course_surface'
		)
		.eq('id', id)
		.maybeSingle();
	if (error) throw dbError(error);
	if (!data || !data.id || !data.name || !data.race_date || !data.provider) return null;
	const hasCourse =
		data.course_distance_m != null || data.course_elevation_m != null || data.course_surface != null;
	return {
		id: data.id,
		provider: data.provider,
		name: data.name,
		race_date: data.race_date,
		distance_m: data.distance_m,
		location_label: data.location_label,
		entry_url: data.entry_url,
		results_url: data.results_url,
		is_verified: data.is_verified ?? false,
		course: hasCourse
			? {
					distanceM: data.course_distance_m,
					ascentM: data.course_elevation_m,
					surface: data.course_surface
				}
			: null
	};
}

/// The signed-in runner's own runs linked to a listing (an imported or
/// matched result), newest first, with the official chip time when the import
/// stamped one.
export interface RaceListingRun {
	id: string;
	started_at: string;
	distance_m: number;
	duration_s: number;
	chip_time: string | null;
}

export async function fetchMyRunsAtRace(listingId: string): Promise<RaceListingRun[]> {
	const userId = auth.user?.id;
	if (!userId || !isEntityId(listingId)) return [];
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('id, started_at, distance_m, duration_s, metadata')
		.eq('race_listing_id', listingId)
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(20);
	if (error) throw dbError(error);
	return (data ?? []).map((r) => {
		const meta = r.metadata && typeof r.metadata === 'object' && !Array.isArray(r.metadata)
			? (r.metadata as Record<string, unknown>)
			: {};
		return {
			id: r.id,
			started_at: r.started_at,
			distance_m: r.distance_m,
			duration_s: r.duration_s,
			chip_time: typeof meta.chip_time === 'string' ? meta.chip_time : null
		};
	});
}

export interface RaceListingInput {
	provider?: RaceProvider; // defaults to 'manual'
	name: string;
	race_date: string;
	distance_m?: number | null;
	location_label?: string | null;
	entry_url?: string | null;
	results_url?: string | null;
}

/// Submit a crowd-sourced race listing. is_verified is forced false by the DB
/// trigger; submitted_by is stamped to the caller (RLS requires the match).
export async function submitRaceListing(input: RaceListingInput): Promise<RaceListing> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from('race_listings')
		.insert({
			provider: input.provider ?? 'manual',
			name: input.name.trim(),
			race_date: input.race_date,
			distance_m: input.distance_m ?? null,
			location_label: input.location_label?.trim() || null,
			entry_url: input.entry_url?.trim() || null,
			results_url: input.results_url?.trim() || null,
			submitted_by: userId
		})
		.select('*')
		.single();
	if (error) throw dbError(error);
	return data as RaceListing;
}

/// Edit one's own unverified listing (RLS locks verified ones).
export async function updateRaceListing(
	id: string,
	patch: Partial<RaceListingInput>
): Promise<void> {
	const fields: Updatable<'race_listings'> = {};
	if (patch.name != null) fields.name = patch.name.trim();
	if (patch.race_date != null) fields.race_date = patch.race_date;
	if (patch.distance_m !== undefined) fields.distance_m = patch.distance_m;
	if (patch.location_label !== undefined)
		fields.location_label = patch.location_label?.trim() || null;
	if (patch.entry_url !== undefined) fields.entry_url = patch.entry_url?.trim() || null;
	if (patch.results_url !== undefined) fields.results_url = patch.results_url?.trim() || null;
	const { error } = await supabase.from('race_listings').update(fields).eq('id', id);
	if (error) throw dbError(error);
}

export interface ImportRaceResultInput {
	provider: 'runsignup' | 'ultrasignup' | 'chronotrack' | 'paste';
	listingId: string;
	/// UltraSignup: who the runner is there. Omit it and the stored link is
	/// read (`fetchUltraSignUpLink`); with neither, the call throws
	/// `ULTRASIGNUP_NOT_LINKED` before reaching the function.
	ultraSignUpPerson?: UltraSignUpPersonLink;
	/// RunSignUp / ChronoTrack: the bib the runner wore — the only scope
	/// either leg accepts (decisions § 1903 for RunSignUp).
	bib?: string;
	/// When set, enrich THIS existing run in place (the auto-match seam) instead
	/// of inserting a new race run.
	matchRunId?: string;
	/// paste-mode single result.
	result?: {
		bib?: string;
		chip_time?: string;
		gun_time?: string;
		overall_place?: number;
		age_group_place?: number;
		age_group?: string;
	};
}

export interface ImportRaceResultOutcome {
	imported: number;
	skipped: number;
	enriched: number;
	/// Whether the function read the finisher field to its end. Optional on the
	/// wire only because a deployment can predate it; grade it through
	/// `parseImportCompleteness`, which reads an absent one as partial.
	complete?: boolean;
}

/// Invoke race-results-import. Throws `RUNSIGNUP_UNAVAILABLE` /
/// `ULTRASIGNUP_UNAVAILABLE` / `CHRONOTRACK_UNAVAILABLE` when the chosen
/// provider key is unconfigured server-side (503), so the UI can show the
/// explainer rather than a generic failure.
export async function importRaceResult(
	input: ImportRaceResultInput
): Promise<ImportRaceResultOutcome> {
	// UltraSignup's feed is keyed by name and the import is scoped by the
	// person the runner picked in Settings (decisions § 1841). Without one there
	// is nothing to send, and the honest answer is "link yourself first".
	let person: UltraSignUpPersonLink | null = null;
	if (input.provider === 'ultrasignup') {
		person = input.ultraSignUpPerson ?? (await fetchUltraSignUpLink());
		if (!person) throw new Error(ULTRASIGNUP_NOT_LINKED);
	}
	markListsStale('runs', 'history', 'routes');
	const { data, error } = await supabase.functions.invoke('race-results-import', {
		body: {
			provider: input.provider,
			listingId: input.listingId,
			ultraSignUpPersonId: person?.personId,
			ultraSignUpFirstName: person?.firstName,
			ultraSignUpLastName: person?.lastName,
			bib: input.bib,
			matchRunId: input.matchRunId,
			result: input.result
		}
	});
	if (error) {
		// `paste` carries no credential, so it can never be the provider a 503
		// provider_not_configured is about — reporting one as RunSignUp's outage
		// also swallowed a plain network failure on the paste path.
		if (input.provider !== 'paste' && (await isProviderGateRefusal(error))) {
			throw new Error(RACE_IMPORT_UNAVAILABLE[input.provider]);
		}
		// The function's own code, not supabase-js's fixed non-2xx sentence, so a
		// caller can branch on what the function refused (decisions § 904).
		const code = await edgeFunctionErrorMessage(error, 'race_import_failed');
		// The stored person is no longer among the people their name answers
		// with. That is a link to redo, not a race with no result in it.
		throw new Error(code === 'ultrasignup_person_not_found' ? ULTRASIGNUP_PERSON_NOT_FOUND : code);
	}
	return data as ImportRaceResultOutcome;
}

/// `importRaceResult` refuses an UltraSignup import before the call when the
/// runner has not picked themselves in Settings.
export const ULTRASIGNUP_NOT_LINKED = 'ULTRASIGNUP_NOT_LINKED';
/// The function could not find the linked person under their name any more.
export const ULTRASIGNUP_PERSON_NOT_FOUND = 'ULTRASIGNUP_PERSON_NOT_FOUND';

/// The people UltraSignup knows by this name, for the runner to pick
/// themselves from. Throws `ULTRASIGNUP_UNAVAILABLE` when the leg is off on
/// this deployment, otherwise the function's own error code.
export async function lookupUltraSignUpPeople(
	firstName: string,
	lastName: string
): Promise<UltraSignUpCandidate[]> {
	const { data, error } = await supabase.functions.invoke('race-results-import', {
		body: {
			provider: 'ultrasignup',
			lookup: true,
			ultraSignUpFirstName: firstName.trim(),
			ultraSignUpLastName: lastName.trim()
		}
	});
	if (error) {
		if (await isProviderGateRefusal(error)) throw new Error(RACE_IMPORT_UNAVAILABLE.ultrasignup);
		throw new Error(await edgeFunctionErrorMessage(error, 'ultrasignup_lookup_failed'));
	}
	return parseUltraSignUpCandidates(data);
}

/// The runner's stored UltraSignup person, or null when they have not linked
/// one. Owner-only by RLS, like every `integrations` row.
export async function fetchUltraSignUpLink(): Promise<UltraSignUpPersonLink | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from(TABLES.integrations)
		.select('external_id, external_first_name, external_last_name')
		.eq('user_id', userId)
		.eq('provider', 'ultrasignup')
		.maybeSingle();
	if (error) throw dbError(error);
	return ultraSignUpLinkFromRow(data);
}

/// Store the person the runner picked. One row per runner per provider, so a
/// re-pick replaces the last one.
export async function linkUltraSignUpPerson(link: UltraSignUpPersonLink): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from(TABLES.integrations).upsert(
		{
			user_id: userId,
			provider: 'ultrasignup',
			external_id: link.personId,
			external_first_name: link.firstName,
			external_last_name: link.lastName
		},
		{ onConflict: 'user_id,provider' }
	);
	if (error) throw dbError(error);
}

/// Forget the stored person. Results already imported stay — they are the
/// runner's runs, not the link's.
export async function unlinkUltraSignUpPerson(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.integrations)
		.delete()
		.eq('user_id', userId)
		.eq('provider', 'ultrasignup');
	if (error) throw dbError(error);
}

/// The error `importRaceResult` throws when a leg's credentials are unset
/// server-side, keyed by leg so a provider added later cannot inherit
/// RunSignUp's message the way a fall-through ternary gave it to ChronoTrack.
export const RACE_IMPORT_UNAVAILABLE: Record<RaceImportLeg, string> = {
	runsignup: 'RUNSIGNUP_UNAVAILABLE',
	ultrasignup: 'ULTRASIGNUP_UNAVAILABLE',
	chronotrack: 'CHRONOTRACK_UNAVAILABLE'
};

/// Probe whether the parkrun import leg is reachable on this deployment.
///
/// parkrun needs no credential, so unlike its three race-results siblings this
/// asks only whether the Edge Function is deployed — the question a minimal
/// deployment answers no to and every client used to skip, rendering a Connect
/// button for a function that is not there. Same fail-closed grading: only a
/// clean 200 counts (see `probeSaysConfigured`).
export async function isParkrunConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('parkrun-import', {
		body: { probe: true }
	});
	return probeSaysConfigured(error);
}

/// Probe whether the RunSignUp RESULTS leg is configured server-side. Reports
/// available only on a clean answer — see `probeSaysConfigured` for why any
/// failure at all reads as unavailable. Drives the RunSignUp card + explainer.
///
/// Probes `race-results-import`, not `race-listings-sync`, for the reason its
/// UltraSignup sibling below gives: the card gates an IMPORT, so it has to ask
/// the leg that would run. The two legs read different credentials — the sync
/// walks an upcoming-races feed, the import fetches a finisher list — and
/// nothing makes one leg's verdict binding on the other (decisions § 1041).
export async function isRunSignUpConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('race-results-import', {
		body: { provider: 'runsignup', probe: true }
	});
	return probeSaysConfigured(error);
}

/// Probe whether the UltraSignup RESULTS leg is configured server-side. Same
/// fail-closed shape as isRunSignUpConfigured.
///
/// Probes `race-results-import`, not `race-listings-sync`. The two legs are
/// separately gated: the sync answers on ULTRASIGNUP_API_KEY, while the results
/// leg reads a keyless feed and answers on the deployment's
/// ULTRASIGNUP_RESULTS_ENABLED opt-in (decisions § 1841). The card this gates
/// says "Import trail and ultra results", so it has to ask the leg that would
/// run. `ultraSignUpFlow: 'person'` says this client speaks the person flow; a
/// client that does not is told the leg is unavailable.
export async function isUltraSignUpConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('race-results-import', {
		body: { provider: 'ultrasignup', probe: true, ultraSignUpFlow: 'person' }
	});
	return probeSaysConfigured(error);
}

/// Probe whether the ChronoTrack leg is configured server-side. Same
/// fail-closed shape as its two siblings — drives the disabled ChronoTrack
/// card + explainer. Uses the race-results-import probe mode (no listing
/// needed).
export async function isChronoTrackConfigured(): Promise<boolean> {
	const { error } = await supabase.functions.invoke('race-results-import', {
		body: { provider: 'chronotrack', probe: true }
	});
	return probeSaysConfigured(error);
}

const RACE_IMPORT_PROBES: Record<RaceImportLeg, () => Promise<boolean>> = {
	runsignup: isRunSignUpConfigured,
	ultrasignup: isUltraSignUpConfigured,
	chronotrack: isChronoTrackConfigured
};

/// Probe one import leg's credentials. The three probes above stay exported for
/// the Settings cards, which name their provider; a caller holding a leg it
/// resolved from a listing dispatches here instead of re-deciding which probe.
export function isRaceImportProviderConfigured(leg: RaceImportLeg): Promise<boolean> {
	return RACE_IMPORT_PROBES[leg]();
}

/// Whether an IMPORT's failure is the credential gate refusing, and not the
/// import itself failing. Distinct from `probeSaysConfigured`, which grades a
/// probe: an import can fail for reasons that say nothing about the credential
/// (a listing that does not exist, a bib with no match), and those must reach
/// the caller as themselves rather than as "this provider is unavailable".
async function isProviderGateRefusal(error: unknown): Promise<boolean> {
	const ctx = (error as { context?: Response })?.context;
	if (ctx && typeof ctx.status === 'number' && ctx.status > 0) {
		if (ctx.status === 503) {
			try {
				const body = await ctx.clone().json();
				return (body as { error?: string })?.error === 'provider_not_configured';
			} catch {
				return true;
			}
		}
		// The probe never confirmed the provider is live: a 429 (the EF's own
		// per-user rate limit — several probes per page/test exceed the free
		// tier) or a 5xx didn't reach (or get past) the credential gate. Honour
		// the fail-closed default and report unavailable rather than offer an
		// action that will 503/429. A readable client error (other 4xx) means
		// the function DID run past the gate, so the provider is configured.
		if (ctx.status === 429 || ctx.status >= 500) return true;
		return false;
	}
	const msg = (error as { message?: string })?.message ?? '';
	if (msg.includes('provider_not_configured') || msg.includes('503')) return true;
	// No readable HTTP status — a FunctionsFetchError (network / CORS) or a
	// status-0 opaque response. supabase-js surfaces the gated 503 this way
	// when the cross-origin error response isn't readable by the browser, so
	// the probe could not CONFIRM the provider is live. Honour the feature's
	// fail-closed default (the missing-credential rule) and report unavailable
	// rather than fail open and offer an action that 503s.
	return true;
}

/// The matched-race view for a run: the run's owner-only race metadata + its
/// linked listing (when any). Owner-scoped — reads the base runs row.
export interface RaceResultForRun {
	race_listing: RaceListingDetail | null;
	race_name: string | null;
	bib: string | null;
	chip_time: string | null;
	gun_time: string | null;
	overall_place: number | null;
	age_group_place: number | null;
	age_group: string | null;
	division_award_place: number | null;
	division_award: string | null;
}

export async function fetchRaceResultForRun(runId: string): Promise<RaceResultForRun | null> {
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('metadata, race_listing_id')
		.eq('id', runId)
		.maybeSingle();
	if (error || !data) return null;
	const meta = (data.metadata as Record<string, unknown> | null) ?? {};
	let listing: RaceListingDetail | null = null;
	if (data.race_listing_id) {
		// The listing only adds the results link; a failed read of it must not
		// hide the official result already stamped on the run.
		try {
			listing = await fetchRaceListing(data.race_listing_id);
		} catch (e) {
			console.warn('fetchRaceResultForRun: listing read failed', e);
		}
	}
	return {
		race_listing: listing,
		race_name: (meta.race_name as string) ?? null,
		bib: (meta.bib as string) ?? null,
		chip_time: (meta.chip_time as string) ?? null,
		gun_time: (meta.gun_time as string) ?? null,
		overall_place: (meta.overall_place as number) ?? null,
		age_group_place: (meta.age_group_place as number) ?? null,
		age_group: (meta.age_group as string) ?? null,
		division_award_place: (meta.division_award_place as number) ?? null,
		division_award: (meta.division_award as string) ?? null
	};
}

/// The auto-match seam: given a run's id, return same-day nearby race listings
/// to offer "Is this your race?". Reads the run's date + start point, then asks
/// search_race_listings for that day's listings near the start; scoring is the
/// pure raceMatchScore (integrations/race_match.ts), applied by the caller.
export async function findRaceMatchCandidates(runId: string): Promise<RaceListingResult[]> {
	const { data: run, error } = await supabase
		.from(TABLES.runs)
		.select('started_at, track_url')
		.eq('id', runId)
		.maybeSingle();
	if (error || !run?.started_at) return [];
	const day = (run.started_at as string).slice(0, 10);
	// The run's GPS start point isn't a column; the caller passes the recorded
	// start latlng into raceMatchScore. Here we window on the date and let the
	// caller filter by proximity + distance band. A same-day window keeps the
	// candidate set tiny.
	try {
		return await searchRaceListings({ from: day, to: day, limit: 20 });
	} catch {
		return [];
	}
}

/** Clubs the current user belongs to (owner or member). */
export async function fetchMyClubsWithError(): Promise<{
	clubs: ClubWithMeta[];
	error: string | null;
}> {
	// Fall back to the session when the JS auth store hasn't hydrated yet —
	// on a fresh page load (bookmark, refresh, hard nav to /plans/new) the
	// store's user can still be null while a valid session sits in storage.
	// Without this, the first caller in a page's onMount silently gets [].
	let userId = auth.user?.id;
	if (!userId) {
		const { data: { session } } = await supabase.auth.getSession();
		userId = session?.user?.id;
	}
	if (!userId) return { clubs: [], error: null };
	const uid = userId;
	// Walked by cursor: an unranged select is capped at `db.max-rows` (1000)
	// with no flag, and nothing bounds how many clubs one user joins (§ 1940).
	const walk = await walkKeyset(MY_CLUB_MEMBERSHIP_ORDER, (after, limit) => {
		let q = supabase
			.from(TABLES.club_members)
			.select(`club_id, role, joined_at, clubs!inner(${CLUB_SELECT_COLS})` as const)
			.eq('user_id', uid);
		if (after) q = q.or(after);
		for (const k of MY_CLUB_MEMBERSHIP_ORDER) {
			q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
		}
		return q.limit(limit);
	});
	if (!walk.complete) {
		console.error('fetchMyClubs failed', walk.error);
		const error = walk.error as { message?: unknown } | null;
		return { clubs: [], error: typeof error?.message === 'string' ? error.message : 'unavailable' };
	}
	// `(row: any)` stood here and hid that this read alone skipped `asClub`:
	// the embedded row's `join_policy` arrived as the bare `string` the
	// generated type gives it and was handed on under a type promising the
	// union. Typing the client is what made the gap visible.
	const clubs = walk.rows.map((row) => row.clubs).filter(Boolean).map(asClub);
	return enrichClubs(clubs);
}

/// Most recently joined first; `club_id` (unique within one user's
/// memberships — the key is `(club_id, user_id)`) breaks a `joined_at` tie so
/// the order is total. Mobile's `SocialService.myClubMembershipOrder` is the
/// same order.
const MY_CLUB_MEMBERSHIP_ORDER: readonly KeysetKey[] = [
	{ column: 'joined_at', ascending: false, nullsFirst: false },
	{ column: 'club_id', ascending: false, nullsFirst: false },
];

export async function fetchMyClubs(): Promise<ClubWithMeta[]> {
	return (await fetchMyClubsWithError()).clubs;
}

/// Reports the read error separately from a null row. `.maybeSingle()` gives
/// `{data: null, error: null}` for a genuine miss, so the two are already
/// distinguishable at this layer — collapsing them told a member their club
/// did not exist whenever the request merely failed.
export async function fetchClubBySlug(
	slug: string
): Promise<{ club: ClubWithMeta | null; error: string | null }> {
	const { data, error } = await supabase
		.from('clubs')
		.select(CLUB_SELECT_COLS)
		.eq('slug', slug)
		.maybeSingle();
	if (error) return { club: null, error: error.message };
	if (!data) return { club: null, error: null };
	const { clubs: enrichedClubs, error: rolesError } = await enrichClubs([asClub(data)]);
	if (rolesError) return { club: null, error: rolesError };
	const [enriched] = enrichedClubs;
	if (!enriched) return { club: null, error: null };
	if (enriched.viewer_role === 'owner' || enriched.viewer_role === 'admin') {
		const { data: token } = await supabase.rpc('get_club_invite_token', {
			target_club: enriched.id
		}, { get: true });
		return { club: { ...enriched, invite_token: (token as string | null) ?? null }, error: null };
	}
	return { club: enriched, error: null };
}

/// Resolves club ids to display names in one read. RLS already scopes this to
/// public clubs plus the ones the caller belongs to, so an id the caller may not
/// read is simply absent from the map — the caller decides what to render for a
/// miss. Used by the club-vs-club leaderboard, whose teams are mostly clubs the
/// viewer is NOT in and so are missing from `fetchMyClubs`.
export async function fetchClubNames(ids: string[]): Promise<Record<string, string>> {
	const wanted = [...new Set(ids.filter(isEntityId))];
	if (wanted.length === 0) return {};
	const { data, error } = await queryChunked(wanted, (part) =>
		supabase.from('clubs').select('id, name').in('id', part)
	);
	if (error) throw dbError(error);
	const out: Record<string, string> = {};
	for (const c of (data ?? []) as { id: string; name: string | null }[]) {
		if (c.name) out[c.id] = c.name;
	}
	return out;
}

/// Resolves a club id to its slug. The notification worker's row projection
/// carries club_id and cannot join for the slug, so its deep links address the
/// club by id and `/clubs/[slug]` forwards to the canonical URL from here.
export async function fetchClubSlugById(id: string): Promise<string | null> {
	if (!isEntityId(id)) return null;
	const { data } = await supabase.from('clubs').select('slug').eq('id', id).maybeSingle();
	return (data as { slug: string } | null)?.slug ?? null;
}

/** Attach viewer_role + viewer_status to clubs. member_count is the
 * trigger-maintained cache on the row (derived_state.md), not recomputed.
 *
 * Returns the read failure rather than absorbing it. `viewer_role: null` is
 * the assertion "you are not a member of this club", and it drives whether the
 * owner gets their admin controls, whether a member is offered "Join", and
 * whether `fetchClubBySlug` asks for an invite token at all — so deriving it
 * from a membership read nobody checked meant a transport blip logged every
 * member out of their own club while `error: null` said the answer was good.
 * `fetchClubBySlug`'s own doc comment describes that exact failure one call
 * up, for the club row; this is the same collapse for the membership row.
 *
 * The result shape matches the `{ clubs, error }` every caller already
 * returns, so three of the four hand it straight back. */
/// One `clubs` row, as `CLUB_SELECT_COLS` reads it, as the client's `Club`.
/// `join_policy` is a CHECK-constrained union the generated row types as a
/// bare `string`, and every club read handed the raw row on as a `Club`
/// without checking it — `parseJoinPolicy` falls back to `'request'`, the one
/// value that neither opens a club nor makes it unjoinable.
function asClub(row: Omit<Club, 'join_policy'> & { join_policy: string }): Club {
	return { ...row, join_policy: parseJoinPolicy(row.join_policy) };
}

async function enrichClubs(
	clubs: Club[]
): Promise<{ clubs: ClubWithMeta[]; error: string | null }> {
	if (clubs.length === 0) return { clubs: [], error: null };
	const ids = clubs.map((c) => c.id);
	const userId = auth.user?.id;

	// Chunked: a walked `fetchMyClubs` can list more clubs than one `in`
	// filter carries before the request line overflows (decisions § 653).
	type MembershipRow = { club_id: string; role: string; status: string };
	let rolesRes: { data: MembershipRow[] | null; error: { message: string; code?: string | null } | null } = {
		data: [],
		error: null,
	};
	if (userId) {
		const pages = await Promise.all(
			chunk(ids, FEED_FOLLOWEE_CHUNK).map((part) =>
				supabase
					.from(TABLES.club_members)
					.select('club_id, role, status')
					.in('club_id', part)
					.eq('user_id', userId)
			)
		);
		const failed = pages.find((p) => p.error);
		rolesRes = failed?.error
			? { data: null, error: failed.error }
			: { data: pages.flatMap((p) => p.data ?? []), error: null };
	}

	const roles = new Map<string, ClubRole>();
	const statuses = new Map<string, MembershipStatus>();
	const withMembership = (): ClubWithMeta[] =>
		clubs.map((c) => ({
			...c,
			member_count: c.member_count ?? 0,
			viewer_role: roles.get(c.id) ?? null,
			viewer_status: statuses.get(c.id) ?? null
		}));

	// A failed membership read is not non-membership — but it is not a failure
	// to read the CLUBS either, and discarding rows the caller already has
	// turns a blip into "you are in no clubs". Hand the rows back with every
	// role and status null and the error alongside, and let each surface say
	// membership is unknown rather than render the list as an error. The
	// single-club reader (fetchClubBySlug) deliberately still fails: an
	// unknown role there silently downgrades an owner to the member view.
	if (rolesRes.error) {
		console.error('enrichClubs (viewer membership) failed', rolesRes.error);
		return { clubs: withMembership(), error: describeReadError(rolesRes.error) };
	}

	for (const row of (rolesRes.data ?? []) as { club_id: string; role: string; status: string }[]) {
		if (row.status === 'active') roles.set(row.club_id, row.role as ClubRole);
		statuses.set(row.club_id, row.status as MembershipStatus);
	}
	return { clubs: withMembership(), error: null };
}

export async function createClub(input: {
	name: string;
	description?: string;
	location_label?: string;
	/// Optional WKT-style geography point (`SRID=4326;POINT(lng lat)`).
	/// ClubEditor geocodes `location_label` via MapTiler and passes
	/// this so the new row is immediately searchable by region (see
	/// `searchClubs` + migration 20260905_001). Callers that lack a
	/// geocoded point pass `undefined` and the column stays NULL —
	/// the club is still findable via the ILIKE branch of search_clubs.
	location_point_wkt?: string;
	is_public: boolean;
	join_policy: JoinPolicy;
	requires_activity_waiver?: boolean;
	website_url?: string | null;
	instagram_url?: string | null;
	strava_url?: string | null;
	facebook_url?: string | null;
}): Promise<Club & { invite_token: string | null }> {
	// invite_token is excluded from the base Club shape (column-grant
	// lockdown) but createClub knows the freshly-generated token —
	// decorate the return so callers can display the share link
	// immediately without a separate get_club_invite_token RPC.
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');

	const baseSlug = clubSlug(input.name) || CLUB_SLUG_FALLBACK;
	const inviteToken = input.join_policy === 'invite' ? genToken() : null;
	// Retry with a short random suffix up to 3 times if the slug is taken —
	// simpler than a SQL trigger and acceptable for the expected volume.
	for (let attempt = 0; attempt < 4; attempt++) {
		const candidate =
			attempt === 0 ? baseSlug : `${baseSlug}-${Math.random().toString(36).slice(2, 6)}`;
		const { data, error } = await supabase
			.from('clubs')
			.insert({
				owner_id: userId,
				name: input.name.trim(),
				slug: candidate,
				description: input.description?.trim() || null,
				location_label: input.location_label?.trim() || null,
				location_point: input.location_point_wkt ?? null,
				is_public: input.is_public,
				join_policy: input.join_policy,
				requires_activity_waiver: input.requires_activity_waiver ?? false,
				website_url: normaliseClubLink(input.website_url),
				instagram_url: normaliseClubLink(input.instagram_url),
				strava_url: normaliseClubLink(input.strava_url),
				facebook_url: normaliseClubLink(input.facebook_url),
				invite_token: inviteToken
			})
			.select(CLUB_SELECT_COLS)
			.single();
		if (!error && data) {
			return {
				...data,
				invite_token: inviteToken,
				join_policy: parseJoinPolicy(data.join_policy)
			};
		}
		// 23505 is the slug-uniqueness conflict — retry with a suffix.
		// Anything else (including the create_club rate-limit P0001 from
		// migration 20260907_001) bubbles. The rate-limit branch is
		// converted to a friendlier 'wait N minutes' message rather than
		// the raw `rate limit exceeded for create_club, retry in Ns`.
		if (error && !isDuplicateKeyError(error)) {
			const friendly = rateLimitErrorMessage(m, error);
			if (friendly) throw new Error(friendly);
			throw dbError(error);
		}
	}
	throw new Error(`Could not allocate a slug for "${input.name}" after 4 attempts`);
}

function genToken(): string {
	const bytes = new Uint8Array(16);
	crypto.getRandomValues(bytes);
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export async function regenerateInviteToken(clubId: string): Promise<string> {
	const token = genToken();
	const { error } = await supabase.from('clubs').update({ invite_token: token }).eq('id', clubId);
	if (error) throw dbError(error);
	return token;
}

export async function updateClub(
	id: string,
	patch: Partial<
		Pick<
			Club,
			| 'name'
			| 'description'
			| 'location_label'
			| 'is_public'
			| 'avatar_url'
			| 'website_url'
			| 'instagram_url'
			| 'strava_url'
			| 'facebook_url'
		>
	>
): Promise<void> {
	// Fail closed on a non-http(s) link so a javascript:/data: URL never
	// reaches the row (the DB CHECK is the backstop; this keeps the error
	// friendly + client-side). Empty string clears the link.
	const clean = { ...patch };
	for (const k of ['website_url', 'instagram_url', 'strava_url', 'facebook_url'] as const) {
		if (k in clean) clean[k] = normaliseClubLink(clean[k]);
	}
	const { error } = await supabase.from('clubs').update(clean).eq('id', id);
	if (error) throw dbError(error);
}

/// Trim a club link, returning null for empty / non-http(s) input so a
/// `javascript:`/`data:` URL can't be stored (XSS). The DB CHECK is the
/// authoritative backstop; this is the friendly client-side gate.
export function normaliseClubLink(raw: string | null | undefined): string | null {
	const v = (raw ?? '').trim();
	if (!v) return null;
	return /^https?:\/\//i.test(v) ? v : null;
}

/// A club delete cascades into its events, so a club holding an event that has
/// taken payments is refused by the same guard as `deleteEvent`.
export async function deleteClub(id: string): Promise<void> {
	const { error } = await supabase.from('clubs').delete().eq('id', id);
	if (error) {
		if (error.message === PAID_EVENT_DELETE_REFUSAL) throw new Error(PAID_EVENT_DELETE_REFUSAL);
		throw dbError(error);
	}
}

// Club logos share the public `avatars` bucket (and its 2 MB / JPEG-PNG-WebP
// limits) under `clubs/{club_id}/logo.{ext}`; the Storage policies admit only
// that exact filename, written by the club's owners and admins (migration
// 20270918000007).
const clubLogoPathsFor = (clubId: string): string[] =>
	Object.values(AVATAR_MIME_TO_EXT).map((e) => `clubs/${clubId}/logo.${e}`);

/// Upload a club logo and point `clubs.avatar_url` at it. Same shape as
/// `uploadAvatar`: EXIF stripped client-side (the bucket is public with no
/// strip worker), remove-then-insert at a stable path, `?v=` cache-bust.
export async function uploadClubLogo(clubId: string, file: File): Promise<string> {
	if (file.size > AVATAR_MAX_BYTES) throw new Error('Image too large (2 MB max)');
	const clean = await stripExifFromFile(file);
	if (!clean) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const ext = AVATAR_MIME_TO_EXT[clean.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const storagePath = `clubs/${clubId}/logo.${ext}`;

	await supabase.storage.from(BUCKETS.avatars).remove(clubLogoPathsFor(clubId));

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.avatars)
		.upload(storagePath, clean, { contentType: clean.type, upsert: false });
	if (upErr) throw dbError(upErr);

	const { data: pub } = supabase.storage.from(BUCKETS.avatars).getPublicUrl(storagePath);
	const url = `${pub.publicUrl}?v=${Date.now()}`;

	const { error: clubErr } = await supabase
		.from('clubs')
		.update({ avatar_url: url })
		.eq('id', clubId);
	if (clubErr) {
		await supabase.storage.from(BUCKETS.avatars).remove([storagePath]);
		throw dbError(clubErr);
	}
	return url;
}

/// Remove a club's logo: drops every stored logo object and clears
/// `clubs.avatar_url` so renderers fall back to the initial.
export async function removeClubLogo(clubId: string): Promise<void> {
	const { error: rmErr } = await supabase.storage
		.from(BUCKETS.avatars)
		.remove(clubLogoPathsFor(clubId));
	if (rmErr) throw dbError(rmErr);
	const { error } = await supabase.from('clubs').update({ avatar_url: null }).eq('id', clubId);
	if (error) throw dbError(error);
}

export async function joinClub(
	clubId: string,
	policy: JoinPolicy = 'open',
	ackWaiver = false,
): Promise<MembershipStatus> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const status: MembershipStatus = policy === 'request' ? 'pending' : 'active';
	const { error } = await supabase.from(TABLES.club_members).insert({
		club_id: clubId,
		user_id: userId,
		role: 'member',
		status,
		// Records the activity-risk acknowledgement when the club requires it
		// (persona #45); null when the club doesn't require a waiver.
		activity_waiver_ack_at: ackWaiver ? new Date().toISOString() : null,
	});
	if (error && !isDuplicateKeyError(error)) throw dbError(error);
	return status;
}

/** Raised by `join_club_by_token` when the club requires the activity-risk
 * acknowledgement and the call did not carry it (§ 1864). */
export const ACTIVITY_WAIVER_REQUIRED = 'activity_waiver_required';

export function isActivityWaiverRequired(e: unknown): boolean {
	return e instanceof Error && e.message === ACTIVITY_WAIVER_REQUIRED;
}

/** Redeem a shareable invite token. Returns the joined club id. */
export async function joinClubByToken(token: string, ackWaiver = false): Promise<string> {
	const { data, error } = await supabase.rpc('join_club_by_token', {
		token,
		activity_waiver_ack: ackWaiver,
	});
	if (error?.message === ACTIVITY_WAIVER_REQUIRED) throw new Error(ACTIVITY_WAIVER_REQUIRED);
	if (error) throw dbError(error);
	return data;
}

/// Fetch `display_name` + `avatar_url` for a set of user ids, chunked.
/// PostgREST serialises `.in('id', ids)` into the request URL, so a
/// club / event with more than ~100 members overflows the gateway's
/// request-line budget and the profile-join leg is lost (decisions § 653) —
/// degrading every name + avatar to a placeholder. Chunk the id set and
/// merge each chunk's rows into one map. See social/feed_merge.ts.
async function fetchProfilesByIds(
	userIds: string[]
): Promise<Map<string, { id: string; display_name: string | null; avatar_url: string | null }>> {
	if (userIds.length === 0) return new Map();
	const pages = await Promise.all(
		chunk(userIds, FEED_FOLLOWEE_CHUNK).map((part) =>
			supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', part)
		)
	);
	return mergeProfilePages(
		pages.map(
			(p) => p.data as { id: string; display_name: string | null; avatar_url: string | null }[] | null
		)
	);
}

/// One user's display name, or null when the profile is unreadable or unnamed.
export async function fetchDisplayName(userId: string): Promise<string | null> {
	const byId = await fetchProfilesByIds([userId]);
	return byId.get(userId)?.display_name ?? null;
}

export async function fetchPendingRequests(clubId: string): Promise<(ClubMember & {
	display_name: string | null;
	avatar_url: string | null;
})[]> {
	// Walked by cursor: nothing bounds how many requests a request-to-join club
	// accumulates, and an unranged select capped at `db.max-rows` (1000) hid
	// every request past the cap from the admin with no error (§ 1940).
	const walk = await walkKeyset(CLUB_MEMBER_ORDER, (after, limit) => {
		let q = supabase
			.from(TABLES.club_members)
			.select('club_id, user_id, role, status, joined_at')
			.eq('club_id', clubId)
			.eq('status', 'pending');
		if (after) q = q.or(after);
		for (const k of CLUB_MEMBER_ORDER) {
			q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
		}
		return q.limit(limit);
	});
	// Throws rather than returning the rows it reached: a queue that failed to
	// load must not read as "no one is waiting" to the admin approving it.
	if (!walk.complete) {
		throw dbError(walk.error ?? new Error('fetchPendingRequests: the walk ended short'));
	}
	const rows = walk.rows;
	if (rows.length === 0) return [];
	const userIds = (rows as ClubMember[]).map((r) => r.user_id);
	const byId = await fetchProfilesByIds(userIds);
	return (rows as ClubMember[]).map((r) => ({
		...r,
		display_name: byId.get(r.user_id)?.display_name ?? null,
		avatar_url: byId.get(r.user_id)?.avatar_url ?? null
	}));
}

export async function approveMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.club_members)
		.update({ status: 'active' })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

export async function bulkApproveMembers(clubId: string, userIds: string[]): Promise<void> {
	if (userIds.length === 0) return;
	const { error } = await queryChunked(userIds, (part) =>
		supabase
			.from(TABLES.club_members)
			.update({ status: 'active' })
			.eq('club_id', clubId)
			.eq('status', 'pending')
			.in('user_id', part)
	);
	if (error) throw dbError(error);
}

export async function setMemberRole(
	clubId: string,
	userId: string,
	role: 'admin' | 'event_organiser' | 'race_director' | 'member'
): Promise<void> {
	const { error } = await supabase
		.from(TABLES.club_members)
		.update({ role })
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

export async function rejectMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.club_members)
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

/// Admin-only: remove an active member from a club. Mechanically a
/// duplicate of rejectMember (both delete the row, both rely on the
/// `admins can manage members` RLS policy), but kept as a separate
/// export so the calling UI can speak in terms of intent — the
/// "kick a member" affordance lives next to the role selector on
/// the Members tab; the "reject a request" affordance lives on the
/// pending-requests admin panel. Either RLS check or the trigger
/// rejecting an owner-row delete will block a misuse.
export async function removeMember(clubId: string, userId: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.club_members)
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

export async function leaveClub(clubId: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.club_members)
		.delete()
		.eq('club_id', clubId)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

/// One page of a club roster / event attendee list. A club with hundreds
/// of members must be reachable via load-more rather than fetched whole on
/// every view — see `fetchFollowers` / `FOLLOW_PAGE_SIZE` for the same shape.
export const ROSTER_PAGE_SIZE = 50;

/// Oldest member first; `user_id` (unique within one club) breaks a
/// `joined_at` tie so the order is total. `joined_at` is nullable, and a null
/// sorts last as it always has. Served by `club_members_club_roster
/// (club_id, joined_at, user_id)`, whose ascending-nulls-last keys are this
/// order exactly.
const CLUB_MEMBER_ORDER: readonly KeysetKey[] = [
	{ column: 'joined_at', ascending: true, nullsFirst: false },
	{ column: 'user_id', ascending: true, nullsFirst: false },
];

/// A club's roster, one keyset page at a time: pass the previous page's
/// `next` as `after` to load more. A cursor rather than an offset because a
/// member who leaves between two reads moves every later member up one, and
/// offset 50 then starts a row late, so one member is never shown.
export async function fetchClubMembers(
	clubId: string,
	opts?: { limit?: number; after?: KeysetCursor | null }
): Promise<KeysetPage<ClubMember & {
	display_name: string | null;
	avatar_url: string | null;
}>> {
	const limit = opts?.limit ?? ROSTER_PAGE_SIZE;
	const after = opts?.after ? keysetAfter(CLUB_MEMBER_ORDER, opts.after) : undefined;
	if (after === null) return { rows: [], next: null };
	let q = supabase
		.from(TABLES.club_members)
		// Enumerate columns rather than `*`: on a public club anyone can
		// read this list, and `activity_waiver_ack_at` (when a member
		// signed the liability waiver) is the member's own business, not
		// public roster data.
		.select('club_id, user_id, role, status, joined_at')
		.eq('club_id', clubId);
	if (after) q = q.or(after);
	for (const k of CLUB_MEMBER_ORDER) {
		q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
	}
	const { data: members } = await q.limit(limit);
	if (!members) return { rows: [], next: null };
	const userIds = (members as ClubMember[]).map((m) => m.user_id);
	const byId = await fetchProfilesByIds(userIds);
	return {
		rows: (members as ClubMember[]).map((m) => ({
			...m,
			display_name: byId.get(m.user_id)?.display_name ?? null,
			avatar_url: byId.get(m.user_id)?.avatar_url ?? null
		})),
		next: nextCursor(CLUB_MEMBER_ORDER, members, limit),
	};
}

// --- Events ---

/// Read a small run of RSVP rows rather than one, because the soonest may have
/// been called off and the card wants the soonest that is still on. A viewer
/// with more than this many cancelled RSVPs inside one window sees no card
/// rather than a live one further down — the fail-closed side of the trade.
const RSVP_CANDIDATE_LIMIT = 10;

/// The next event the signed-in user has RSVP'd `going` to within the
/// given window. Returns null when nothing matches — the dashboard
/// card hides itself. Fail-closed on a run of cancellations: with every
/// candidate called off it shows nothing rather than a cancelled event.
///
/// Mirrors `SocialService.fetchNextRsvpedEvent` on Android so both
/// surfaces show the same card at the same moment in time.
export async function fetchNextRsvpedEvent(
	windowHours = 48,
): Promise<{
	event_id: string;
	instance_start: string;
	club_slug: string;
	title: string;
	meet_label: string | null;
} | null> {
	const { data: { user } } = await supabase.auth.getUser();
	if (!user) return null;
	const now = new Date();
	const horizon = new Date(now.getTime() + windowHours * 3600_000);
	const { data } = await supabase
		.from(TABLES.event_attendees)
		.select(
			'event_id, instance_start, events(title, meet_label, clubs(slug))',
		)
		.eq('user_id', user.id)
		.eq('status', 'going')
		.gte('instance_start', now.toISOString())
		.lte('instance_start', horizon.toISOString())
		.order('instance_start', { ascending: true })
		.limit(RSVP_CANDIDATE_LIMIT);
	const rows = (data as Array<Record<string, unknown>> | null) ?? [];
	if (rows.length === 0) return null;

	// An RSVP row survives its occurrence being called off — the organiser can
	// reinstate it — so the card has to subtract `event_exceptions` itself
	// rather than trust that a `going` row means the run is on.
	const { data: exceptionRows } = await supabase
		.from('event_exceptions')
		.select('event_id, instance_start')
		.in('event_id', rows.map((r) => r.event_id as string))
		.gte('instance_start', now.toISOString());
	const cancelled = new Map<string, string[]>();
	for (const x of (exceptionRows ?? []) as { event_id: string; instance_start: string }[]) {
		const list = cancelled.get(x.event_id);
		if (list) list.push(x.instance_start);
		else cancelled.set(x.event_id, [x.instance_start]);
	}

	for (const row of rows) {
		const eventId = row.event_id as string;
		const instanceStart = row.instance_start as string;
		if (isOccurrenceCancelled(cancelled.get(eventId) ?? [], instanceStart)) continue;
		const ev = row.events as
			| {
					title: string;
					meet_label: string | null;
					clubs: { slug: string } | { slug: string }[] | null;
			  }
			| null;
		if (!ev) continue;
		// The card's whole job is to deep-link the club. A missing slug would
		// route it at /clubs/undefined, so skip the candidate and try the next.
		const slug = singleEmbed(ev.clubs)?.slug;
		if (!slug) continue;
		return {
			event_id: eventId,
			instance_start: instanceStart,
			club_slug: slug,
			title: ev.title,
			meet_label: ev.meet_label ?? null,
		};
	}
	return null;
}

export async function fetchUpcomingEvents(clubId: string): Promise<EventWithMeta[]> {
	// For recurring series, `starts_at` can be in the past even though the next
	// instance is in the future, so the candidate set is (a) one-off in the
	// future OR (b) recurring and not past its until-date. That predicate has
	// to run SERVER-side: ordering `starts_at` ascending under a cap returns
	// the club's OLDEST rows, so a club with more than `limit` finished
	// one-offs — a weekly series is 200 rows in four years — pushed every
	// future event past the cap and its Events tab went permanently empty.
	// (The same shape `fetchRunsForDashboard` documents: an ascending cap over
	// a growing history windows the wrong end of it.)
	//
	// A count-limited series carries no until-date, so it lands in the
	// candidate set and `nextLiveInstance` retires it once exhausted — the
	// filter below is deliberately a superset of what is actually live. The
	// two recurring clauses are spelled separately rather than as one nested
	// `or(...)` because a single `and(...)` inside an `or=` is the only nesting
	// depth this file already exercises, and a filter PostgREST cannot parse
	// 400s into the discarded `error` and empties the tab exactly as the bug
	// being fixed did.
	const nowIso = new Date().toISOString();
	const { data } = await supabase
		.from('events')
		.select(EVENT_SELECT_COLS)
		.eq('club_id', clubId)
		.or(
			`starts_at.gte.${nowIso},` +
				`and(recurrence_freq.not.is.null,recurrence_until.is.null),` +
				`and(recurrence_freq.not.is.null,recurrence_until.gte.${nowIso})`
		)
		.order('starts_at', { ascending: true })
		.limit(200);
	const events = (data as Event[]) ?? [];
	const now = new Date();
	const enriched = await enrichEvents(events);
	return enriched
		.filter((e) => e.next_instance_start != null && new Date(e.next_instance_start) >= now)
		.sort(
			(a, b) =>
				new Date(a.next_instance_start!).getTime() - new Date(b.next_instance_start!).getTime()
		);
}

export async function fetchPastEvents(clubId: string, limit = 12): Promise<EventWithMeta[]> {
	const nowIso = new Date().toISOString();
	const { data } = await supabase
		.from('events')
		.select(EVENT_SELECT_COLS)
		.eq('club_id', clubId)
		.lt('starts_at', nowIso)
		.order('starts_at', { ascending: false })
		.limit(limit);
	return enrichEvents((data as Event[]) ?? []);
}

/// Resolves an event id to its club's slug so the stable-id `/events/[id]`
/// route can forward to the canonical `/clubs/{slug}/events/{id}`. That route
/// exists because the notification worker addresses an event by id alone — its
/// row projection has no slug to join — and because an id URL survives a club
/// rename that would break every already-sent nested link.
export async function fetchEventClubSlug(eventId: string): Promise<string | null> {
	if (!isEntityId(eventId)) return null;
	const { data } = await supabase
		.from('events')
		.select('id, clubs(slug)')
		.eq('id', eventId)
		.maybeSingle();
	if (!data) return null;
	const clubs = (data as { clubs: { slug: string } | { slug: string }[] | null }).clubs;
	const club = singleEmbed(clubs);
	return club?.slug ?? null;
}

export async function fetchEventById(id: string): Promise<EventWithMeta | null> {
	const { data } = await supabase.from('events').select(EVENT_SELECT_COLS).eq('id', id).maybeSingle();
	if (!data) return null;
	const [enriched] = await enrichEvents([data as Event]);
	return enriched ?? null;
}

async function enrichEvents(events: Event[]): Promise<EventWithMeta[]> {
	if (events.length === 0) return [];

	const ids = events.map((e) => e.id);
	const now = new Date();

	// Called-off occurrences (`event_exceptions`) have to be known BEFORE the
	// next instance is picked, so this read cannot join the parallel batch
	// below — the counts RPC is keyed on the instant this resolves to. Only
	// future exceptions can move the answer, so the scan stays small.
	const { data: exceptionRows } = await queryChunked(ids, (part) =>
		supabase
			.from('event_exceptions')
			.select('event_id, instance_start')
			.in('event_id', part)
			.gte('instance_start', now.toISOString())
	);
	const cancelledByEvent = new Map<string, string[]>();
	for (const row of (exceptionRows ?? []) as { event_id: string; instance_start: string }[]) {
		const list = cancelledByEvent.get(row.event_id);
		if (list) list.push(row.instance_start);
		else cancelledByEvent.set(row.event_id, [row.instance_start]);
	}

	// Each event's next occurrence that is still ON — null once the series has
	// none left (exhausted, or every remaining one called off). Counts and the
	// viewer's RSVP scope to that occurrence, falling back to `starts_at` so a
	// past event still reports who attended it.
	const liveMap = new Map<string, string>();
	const countMap = new Map<string, string>();
	for (const e of events) {
		const evt = normaliseEvent(e);
		const next = nextLiveInstance(evt, cancelledByEvent.get(e.id) ?? [], now);
		if (next) liveMap.set(e.id, next.toISOString());
		countMap.set(e.id, (next ?? new Date(evt.starts_at)).toISOString());
	}

	const nextStarts = ids.map((id) => countMap.get(id)!);
	const userId = auth.user?.id;

	// The going-count is scoped to each event's NEXT instance and computed
	// server-side: the event_next_instance_going_counts RPC pairs each event id
	// with its next-instance timestamp (by ordinality) and returns one integer
	// per event. The prior client-side approach fetched EVERY all-time
	// status='going' row for the listed events with no limit and tallied the
	// matching instance locally — tens of thousands of rows on the wire to
	// produce N integers. The viewer's RSVPs are a single bounded per-user
	// fetch, so those still come back as rows and are matched to the next
	// instance client-side.
	const countsPromise = supabase.rpc('event_next_instance_going_counts', {
		p_event_ids: ids,
		p_next_starts: nextStarts,
	});
	const rsvpPromise = userId
		? queryChunked(ids, (part) =>
				supabase
					.from(TABLES.event_attendees)
					.select('event_id, status, instance_start')
					.in('event_id', part)
					.eq('user_id', userId)
			)
		: Promise.resolve({ data: [] as { event_id: string; status: string; instance_start: string }[] });

	const [countRes, rsvpRes] = await Promise.all([countsPromise, rsvpPromise]);

	// Compare instants, not raw strings: countMap holds toISOString() ('…Z')
	// while Postgres returns timestamptz as '…+00:00', so a string `===`
	// never matches and every RSVP would be dropped (regression from the
	// client-side debatch in 7e386e57 — the prior per-event `.eq()` compared
	// timestamptz server-side).
	const sameInstant = (a: string, b: string | undefined): boolean =>
		b != null && new Date(a).getTime() === new Date(b).getTime();
	const counts = new Map<string, number>();
	for (const row of countRes.data ?? []) {
		counts.set(row.event_id, Number(row.going_count));
	}
	const rsvps = new Map<string, RsvpStatus | null>();
	for (const row of (rsvpRes.data ?? []) as { event_id: string; status: string; instance_start: string }[]) {
		if (sameInstant(row.instance_start, countMap.get(row.event_id))) {
			rsvps.set(row.event_id, (row.status ?? null) as RsvpStatus | null);
		}
	}

	return events.map((e) => ({
		...normaliseEvent(e),
		attendee_count: counts.get(e.id) ?? 0,
		viewer_rsvp: rsvps.get(e.id) ?? null,
		next_instance_start: liveMap.get(e.id) ?? null
	}));
}

/** Coerce server-side string[]/string into typed unions. */
function normaliseEvent(e: Event): Event {
	return {
		...e,
		recurrence_freq: (e.recurrence_freq ?? null) as RecurrenceFreq | null,
		recurrence_byday: (e.recurrence_byday ?? null) as Weekday[] | null,
		// Legacy rows predate the category column; treat them as athletic runs.
		category: (e.category ?? 'run') as EventCategory,
		// Raw jsonb on the row -> the typed seam shape (null for empty/malformed).
		gym_template: parseGymTemplate(e.gym_template as unknown)
	};
}

/// The caller's IANA timezone (e.g. 'America/New_York'), or null if the
/// runtime can't resolve one — events anchor to this so discovery can filter
/// by local time-of-day.
function localTimezone(): string | null {
	try {
		return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
	} catch {
		return null;
	}
}

export async function createEvent(input: {
	club_id: string;
	title: string;
	category: EventCategory;
	discipline?: string | null;
	// The class -> gym seam hint. Only persisted for category === 'class';
	// null (no template) for every other category.
	gym_template?: EventGymTemplate | null;
	description?: string;
	starts_at: string; // ISO
	timezone?: string | null; // IANA; defaults to the organiser's browser tz
	duration_min?: number;
	meet_label?: string;
	meet_lat?: number;
	meet_lng?: number;
	route_id?: string | null;
	distance_m?: number;
	pace_target_sec?: number;
	capacity?: number;
	recurrence_freq?: RecurrenceFreq | null;
	recurrence_byday?: Weekday[] | null;
	recurrence_until?: string | null;
	recurrence_count?: number | null;
	// When false, the event is members-only: hidden from non-members + discovery.
	// Defaults to public. Only meaningful in a public club (a private club's
	// events are already members-only via the club gate).
	is_public?: boolean;
}): Promise<Event> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('events')
		.insert({
			club_id: input.club_id,
			title: input.title.trim(),
			category: input.category,
			is_public: input.is_public ?? true,
			discipline: input.discipline?.trim() || null,
			gym_template: input.category === 'class' ? (input.gym_template ?? null) : null,
			description: input.description?.trim() || null,
			starts_at: input.starts_at,
			// Anchor the event to the organiser's local timezone so discovery's
			// time-of-day filter resolves "7pm" as local, not the UTC instant.
			timezone: input.timezone ?? localTimezone(),
			duration_min: input.duration_min ?? null,
			meet_label: input.meet_label?.trim() || null,
			meet_lat: input.meet_lat ?? null,
			meet_lng: input.meet_lng ?? null,
			route_id: input.route_id ?? null,
			distance_m: input.distance_m ?? null,
			pace_target_sec: input.pace_target_sec ?? null,
			capacity: input.capacity ?? null,
			recurrence_freq: input.recurrence_freq ?? null,
			recurrence_byday: input.recurrence_byday ?? null,
			recurrence_until: input.recurrence_until ?? null,
			recurrence_count: input.recurrence_count ?? null,
			author_id: userId
		})
		.select(EVENT_SELECT_COLS)
		.single();
	if (error) throw dbError(error);
	return normaliseEvent(data as Event);
}

export async function updateEvent(
	id: string,
	patch: Partial<{
		title: string;
		category: EventCategory;
		discipline: string | null;
		gym_template: EventGymTemplate | null;
		description: string | null;
		starts_at: string;
		duration_min: number | null;
		meet_label: string | null;
		route_id: string | null;
		distance_m: number | null;
		pace_target_sec: number | null;
		capacity: number | null;
		is_public: boolean;
	}>
): Promise<void> {
	// RLS `is_event_organiser` gates the UPDATE; owner/admin/event_organiser
	// only. `events` stays bare here per the F11 registry tail (see schema.ts).
	//
	// `gym_template` is left out of the update entirely when the caller did not
	// patch it — putting the key back with an `undefined` would turn "leave it
	// alone" into a write.
	const { gym_template, ...fields } = patch;
	const { error } = await supabase
		.from('events')
		.update(gym_template === undefined ? fields : { ...fields, gym_template })
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Whether an event carries any race session or finisher result across ANY of
/// its instances. Drives the editor's warning before an organiser switches an
/// athletic event to a non-athletic category — the athletic surfaces gate on
/// isAthleticCategory, so the switch hides the leaderboard/race controls and
/// orphans those rows. Fail-safe: a read error returns true so we still warn
/// when we can't be sure.
export async function eventHasAthleticData(eventId: string): Promise<boolean> {
	try {
		const [resultsRes, sessionsRes] = await Promise.all([
			supabase
				.from(TABLES.event_results)
				.select('event_id', { count: 'exact', head: true })
				.eq('event_id', eventId),
			supabase
				.from('race_sessions')
				.select('event_id', { count: 'exact', head: true })
				.eq('event_id', eventId)
		]);
		if (resultsRes.error || sessionsRes.error) return true;
		return (resultsRes.count ?? 0) > 0 || (sessionsRes.count ?? 0) > 0;
	} catch {
		return true;
	}
}

/// The message `guard_paid_event_delete` (20270731000001) raises when a client
/// deletes an event, or a club holding one, that has taken payments. The event
/// is cancelled instead, and its payment records stay (decisions § 1867).
export const PAID_EVENT_DELETE_REFUSAL = 'paid_event_has_orders';

/// Throws `Error(PAID_EVENT_DELETE_REFUSAL)` when the event has taken payments,
/// so the page can say why rather than show the database's raw message.
export async function deleteEvent(id: string): Promise<void> {
	const { error } = await supabase.from('events').delete().eq('id', id);
	if (error) {
		if (error.message === PAID_EVENT_DELETE_REFUSAL) throw new Error(PAID_EVENT_DELETE_REFUSAL);
		throw dbError(error);
	}
}

export interface EventException {
	event_id: string;
	instance_start: string;
	cancelled_by: string | null;
	reason: string | null;
	cancelled_at: string;
}

export async function fetchEventExceptions(eventId: string): Promise<EventException[]> {
	const { data } = await supabase
		.from('event_exceptions')
		.select('event_id, instance_start, cancelled_by, reason, cancelled_at')
		.eq('event_id', eventId);
	return (data as EventException[] | null) ?? [];
}

/// Event meetup coordinates, gated to active club members by the
/// `get_event_meet_point` SECURITY DEFINER RPC. `meet_lat` / `meet_lng`
/// are column-revoked from every client role (precise meeting points
/// leak organiser home addresses — migrations 20260723_001 /
/// 20260806_001), so a direct column select can't reach them. Returns
/// null for non-members and events without a meet point set.
/// Persona-hunt social-group #10.
export async function fetchEventMeetPoint(
	eventId: string
): Promise<{ lat: number; lng: number } | null> {
	const { data, error } = await supabase.rpc(
		'get_event_meet_point',
		{ p_event_id: eventId },
		{ get: true }
	);
	if (error || !data || data.length === 0) return null;
	const row = data[0];
	if (typeof row.meet_lat !== 'number' || typeof row.meet_lng !== 'number') return null;
	return { lat: row.meet_lat, lng: row.meet_lng };
}

// ─────────────────────── Paid registration (club_events.md slice P1) ───────────────────────

/// Boolean-only view of the signed-in host's Stripe payout capability.
/// The raw `stripe_connect_account_id` is column-revoked from clients
/// (migration 20261229_001) — this reads the surfacing columns + the
/// `host_can_take_payment` RPC for the capability flags. Returns null
/// when the host has never started onboarding.
export interface PayoutAccountStatus {
	charges_enabled: boolean;
	payouts_enabled: boolean;
	details_submitted: boolean;
	country: string | null;
	default_currency: string | null;
}

export async function fetchPayoutAccount(): Promise<PayoutAccountStatus | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	// The own-row SELECT policy lets a host read their own account row;
	// `stripe_connect_account_id` is revoked at the column level, so we
	// never project it. The capability booleans live on the row directly.
	const { data, error } = await supabase
		.from('instructor_payout_accounts')
		.select('charges_enabled, payouts_enabled, details_submitted, country, default_currency')
		.eq('user_id', userId)
		.maybeSingle();
	if (error || !data) return null;
	return {
		charges_enabled: Boolean(data.charges_enabled),
		payouts_enabled: Boolean(data.payouts_enabled),
		details_submitted: Boolean(data.details_submitted),
		country: (data.country as string | null) ?? null,
		default_currency: (data.default_currency as string | null) ?? null
	};
}

/// The signed-in host's earnings, one row per (class instance, currency):
/// what they were PAID for, keyed on `event_orders.host_user_id`, which is
/// not the organiser scope the table's own SELECT policy grants
/// (instructor_business.md M7, migration 20270723000001). Throws on a failed
/// read so the page can offer a retry instead of a false "no earnings yet".
export async function fetchHostEarnings(): Promise<HostEarningsInstance[]> {
	if (!auth.user?.id) return [];
	const { data, error } = await supabase.rpc('host_earnings_summary', undefined, { get: true });
	if (error) throw dbError(error);
	const rows: HostEarningsInstance[] = [];
	for (const raw of data ?? []) {
		const row = parseHostEarningsRow(raw);
		if (row) rows.push(row);
	}
	return rows;
}

/// Start (or resume) Stripe Connect onboarding for the signed-in host.
/// Invokes the events-connect-onboard Edge Function, which creates/reuses
/// an Express account and returns a hosted Account Link URL. The caller
/// redirects the browser there.
export async function startConnectOnboarding(): Promise<{ url: string }> {
	const { data, error } = await supabase.functions.invoke('events-connect-onboard', {
		body: {}
	});
	if (error) {
		// As in startEventCheckout: supabase-js's FunctionsHttpError message
		// is the fixed "Edge Function returned a non-2xx status code", so the
		// caller's not-configured branch could never match on it and every
		// keyless build reported a red failure carrying that internal string.
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (appErrorMessage(error) ?? 'onboard_failed'));
	}
	const url = (data as { url?: string } | null)?.url;
	if (!url) throw new Error('No onboarding URL returned');
	return { url };
}

/// Effective pricing for an event instance. Per-instance override wins
/// over the series default (instance_start IS NULL). Readable with the
/// event per RLS.
export async function fetchEventPricing(
	eventId: string,
	instanceStart?: string | null
): Promise<EventPricing | null> {
	const { data, error } = await supabase
		.from('event_pricing')
		.select('*')
		.eq('event_id', eventId);
	if (error || !data || data.length === 0) return null;
	return selectEffectivePricing(data as EventPricing[], instanceStart);
}

/// Persist series-level (or per-instance) pricing for an event. Kept
/// separate from createEvent so the price write goes through its own
/// charges_enabled-gated RLS surface — folding it into the events insert
/// would couple two RLS surfaces (club_events.md, the race/results
/// precedent). The DB trigger rejects the write if the host lacks a
/// charges-enabled payout account, so a stale UI can't slip a price past.
export async function setEventPricing(
	eventId: string,
	input: {
		price_cents: number;
		currency: string;
		refund_policy: EventPricing['refund_policy'];
		sales_close_offset_minutes: number;
		instance_start?: string | null;
	}
): Promise<void> {
	const { error } = await supabase.from('event_pricing').upsert(
		{
			event_id: eventId,
			instance_start: input.instance_start ?? null,
			price_cents: input.price_cents,
			currency: input.currency,
			modality: 'in_person',
			refund_policy: input.refund_policy,
			sales_close_offset_minutes: input.sales_close_offset_minutes
		},
		// One arbiter for both branches: event_pricing_event_instance_uniq is
		// non-partial (NULLS NOT DISTINCT), so a NULL instance_start conflicts
		// with the existing series row instead of inserting a second one.
		{ onConflict: 'event_id,instance_start' }
	);
	if (error) throw dbError(error);
}

/// Begin a Stripe Checkout for a paid registration. The events-checkout
/// Edge Function validates the sales window + capacity, holds a soft
/// reservation (a pending order), and returns a hosted destination-charge
/// Checkout URL. The caller redirects the browser there.
export async function startEventCheckout(
	eventId: string,
	instanceStart: string
): Promise<{ url: string }> {
	const { data, error } = await supabase.functions.invoke('events-checkout', {
		body: { event_id: eventId, instance_start: instanceStart }
	});
	if (error) {
		// supabase-js reports every non-2xx as a FunctionsHttpError whose
		// message is the fixed internal string "Edge Function returned a
		// non-2xx status code"; the function's own `{ error: '<code>' }`
		// envelope rides on `context`. Rethrowing as-is put that internal
		// sentence in front of the buyer for sold-out, sales-closed and a
		// host who cannot take money alike. Same unwrap as cancelEventOrder.
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (appErrorMessage(error) ?? 'checkout_failed'));
	}
	// `checkout_url`, matching what the Edge Function actually returns and the
	// `startDonationCheckout` sibling below. Reading `url` here meant this
	// never resolved: the function had already created a live Stripe session
	// and a capacity-holding pending order by then, so every Register press
	// burned a reservation and then threw before the buyer reached Stripe.
	const url = (data as { checkout_url?: string } | null)?.checkout_url;
	if (!url) throw new Error('No checkout URL returned');
	return { url };
}

/// The signed-in buyer's most recent order for an event instance, used
/// by the post-checkout success poll (?paid=1). Buyer-reads-own RLS scopes
/// this to the caller's own orders.
export async function fetchMyOrder(
	eventId: string,
	instanceStart: string
): Promise<EventOrder | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from('event_orders')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.eq('buyer_user_id', userId)
		.order('created_at', { ascending: false })
		.limit(1);
	if (error || !data || data.length === 0) return null;
	return data[0] as EventOrder;
}

/// The viewer's own attendee row for one occurrence, as far as the paid
/// waitlist needs it: whether they are queued, and whether a seat is being
/// held for them (`offer_expires_at`, migration 20270726000002). Read through
/// RLS, which shows every user their own RSVP. A failed read throws rather
/// than answering "not on the waitlist", which would offer the viewer a
/// second place in a queue they are already in.
export async function fetchMyWaitlistPlace(
	eventId: string,
	instanceStart: string
): Promise<{ status: RsvpStatus; offer_expires_at: string | null } | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from(TABLES.event_attendees)
		.select('status, offer_expires_at')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.eq('user_id', userId)
		.maybeSingle();
	if (error) throw dbError(error);
	if (!data) return null;
	return { status: data.status as RsvpStatus, offer_expires_at: data.offer_expires_at };
}

/// Buyer self-cancel of their OWN paid/pending registration for an event
/// instance (club_events.md slice P2). Calls the events-cancel Edge
/// Function, which initiates the Stripe refund (paid order, refund-eligible
/// per the event's refund_policy) or expires the soft reservation (pending
/// order). The stripe-events webhook — still the sole writer of
/// event_orders.status — performs the actual status transition + seat
/// release when Stripe delivers the resulting event, so this returns the
/// initiated `action` and the caller polls/refreshes for the terminal state.
export async function cancelEventOrder(
	eventId: string,
	instanceStart: string
): Promise<{ action: string }> {
	const { data, error } = await supabase.functions.invoke('events-cancel', {
		body: { event_id: eventId, instance_start: instanceStart }
	});
	if (error) {
		// A non-2xx (e.g. 409 policy_no_refund, 503 stripe_not_configured)
		// arrives as a FunctionsHttpError carrying the Response in `context`.
		// Re-throw an Error whose message is the EF's machine `error` code so
		// the caller can map it to a localized string.
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (appErrorMessage(error) ?? 'cancel_failed'));
	}
	const action = (data as { action?: string } | null)?.action;
	if (!action) throw new Error('cancel_failed');
	return { action };
}

/// Cancel a single occurrence of a recurring event (the rest of the series
/// is untouched), or a one-off event, whose only occurrence is its
/// `starts_at`. Organiser-only via RLS; the fan-out trigger notifies every
/// going / maybe / waitlisted attendee of this instance.
///
/// An occurrence that still holds money (a pending, paid or partially
/// refunded order) cannot be cancelled by this insert:
/// `guard_paid_occurrence_cancel` refuses it, and the cancel is handed to the
/// events-cancel function, which calls it off and refunds every registrant in
/// one request (M8). The database decides, not the page, so a class whose
/// price was removed after people paid is still refunded. `refunds` is that
/// function's per-order summary, or null when no money was involved.
export async function cancelEventInstance(
	eventId: string,
	instanceStart: string,
	reason: string | null
): Promise<{ refunds: OccurrenceRefundSummary | null }> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	// Idempotent: two organisers cancelling the same occurrence (or a
	// double-click) must not surface a raw 23505 on the (event_id,
	// instance_start) PK. First cancellation wins — ignore the duplicate.
	const { error } = await supabase.from('event_exceptions').upsert(
		{
			event_id: eventId,
			instance_start: instanceStart,
			cancelled_by: userId,
			reason: reason?.trim() || null
		},
		{ onConflict: 'event_id,instance_start', ignoreDuplicates: true }
	);
	if (error) {
		if (error.message === PAID_OCCURRENCE_REFUSAL) {
			return { refunds: await cancelPaidEventInstance(eventId, instanceStart, reason) };
		}
		throw dbError(error);
	}
	return { refunds: null };
}

/// The message `guard_paid_occurrence_cancel` (20270723000003) raises.
const PAID_OCCURRENCE_REFUSAL = 'paid_occurrence_requires_refund';

/// Call off a paid occurrence and refund everyone registered for it, through
/// the events-cancel function's `occurrence` scope. Also what "Refund now"
/// calls on an already-cancelled occurrence: the function's exception insert
/// is idempotent and each refund is keyed by its order, so re-running it
/// resumes the refunds that failed and replays the ones that did not.
/// Throws an Error whose message is the function's machine code
/// (`stripe_not_configured`, `not_event_organiser`, …) on a non-2xx.
export async function cancelPaidEventInstance(
	eventId: string,
	instanceStart: string,
	reason: string | null
): Promise<OccurrenceRefundSummary> {
	const { data, error } = await supabase.functions.invoke('events-cancel', {
		body: {
			event_id: eventId,
			instance_start: instanceStart,
			scope: 'occurrence',
			reason: reason?.trim() || null
		}
	});
	if (error) {
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (appErrorMessage(error) ?? 'cancel_failed'));
	}
	const refunds = parseOccurrenceRefundSummary((data as { refunds?: unknown } | null)?.refunds);
	if (!refunds) throw new Error('cancel_failed');
	return refunds;
}

/// End a recurring series now and call off every remaining occurrence anyone
/// signed up for, refunding all of their registrations, through the
/// events-cancel function's `series` scope (decisions § 1868). The function
/// moves `recurrence_until` to the moment of the cancel, so later occurrences
/// stop existing rather than each being cancelled. Re-running it resumes any
/// refund that failed, exactly as an occurrence cancel does. Throws an Error
/// whose message is the function's machine code on a non-2xx.
export async function cancelEventSeries(
	eventId: string,
	reason: string | null
): Promise<{ cancelledOccurrences: number; refunds: OccurrenceRefundSummary }> {
	const { data, error } = await supabase.functions.invoke('events-cancel', {
		body: { event_id: eventId, scope: 'series', reason: reason?.trim() || null }
	});
	if (error) {
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (appErrorMessage(error) ?? 'cancel_failed'));
	}
	const body = data as { refunds?: unknown; cancelled_occurrences?: unknown } | null;
	const refunds = parseOccurrenceRefundSummary(body?.refunds);
	if (!refunds) throw new Error('cancel_failed');
	const n = body?.cancelled_occurrences;
	return { cancelledOccurrences: typeof n === 'number' && n >= 0 ? n : 0, refunds };
}

/// What is still owed on each cancelled occurrence of an event, for its
/// organisers: one entry per occurrence with anything unsettled, in date
/// order, past occurrences included (a class called off last week can still
/// owe someone their money). Reads only the orders that are not settled; the
/// organiser RLS policy on event_orders is what lets a non-host organiser see
/// them.
export async function fetchCancelledOccurrenceRefunds(
	eventId: string,
	cancelledInstanceStarts: readonly string[]
): Promise<Array<{ instanceStart: string; state: OccurrenceRefundState }>> {
	if (cancelledInstanceStarts.length === 0) return [];
	const { data, error } = await supabase
		.from('event_orders')
		.select('instance_start, status, refund_initiated_at')
		.eq('event_id', eventId)
		.in('status', ['pending', 'paid', 'partially_refunded', 'refund_failed']);
	if (error) throw dbError(error);
	return cancelledOccurrenceRefunds(data ?? [], cancelledInstanceStarts);
}

export async function reinstateEventInstance(
	eventId: string,
	instanceStart: string
): Promise<void> {
	const { error } = await supabase
		.from('event_exceptions')
		.delete()
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart);
	if (error) throw dbError(error);
}

/// Upsert the caller's RSVP and return the *effective* status. When the
/// requested status is 'going' but the event is at capacity, the
/// enforce_event_capacity trigger (migration 20261018_001) demotes the row to
/// 'waitlisted', so the persisted status can differ from what was requested —
/// we read it back via the upsert's returning row so the UI can show the
/// waitlist state without a second fetch.
///
/// `courseId` is the racer's chosen course on a multi-course event
/// (`event_courses`). Leaving it undefined omits the column from the upsert,
/// so a status change keeps the course already on the row; the server refuses
/// a going / waitlisted RSVP with no course when the event has more than one.
export async function rsvpEvent(
	eventId: string,
	status: RsvpStatus,
	instanceStart: string,
	courseId?: string | null
): Promise<RsvpStatus> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const row: Insertable<'event_attendees'> = {
		event_id: eventId,
		user_id: userId,
		status,
		instance_start: instanceStart,
	};
	if (courseId !== undefined) row.course_id = courseId;
	const { data, error } = await supabase
		.from(TABLES.event_attendees)
		.upsert(row, { onConflict: 'event_id,user_id,instance_start' })
		.select('status')
		.single();
	if (error) throw dbError(error);
	return (data?.status as RsvpStatus | undefined) ?? status;
}

export async function clearRsvp(eventId: string, instanceStart: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.event_attendees)
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw dbError(error);
}

// Host-only: mark whether an attendee actually showed up. Orthogonal to the
// attendee's RSVP status — routes through the mark_attendance SECURITY DEFINER
// RPC (instructor_business.md M6) which enforces organiser-only writes and
// touches only the attendance column. Pass null to clear a prior mark.
export async function markAttendance(
	eventId: string,
	userId: string,
	instanceStart: string,
	attendance: EventAttendance | null
): Promise<void> {
	const { error } = await supabase.rpc('mark_attendance', {
		p_event_id: eventId,
		p_user_id: userId,
		p_instance_start: instanceStart,
		p_attendance: attendance
	});
	if (error) throw dbError(error);
}

/// Earliest RSVP first; `user_id` (unique within one occurrence — the primary
/// key is `(event_id, user_id, instance_start)`) breaks a `joined_at` tie so
/// the order is total. `joined_at` is nullable and a null sorts last, as it
/// always has. Served by `event_attendees_instance_roster (event_id,
/// instance_start, joined_at, user_id)`; mobile's `ApiClient.eventAttendeeOrder`
/// is the same order.
const EVENT_ATTENDEE_ORDER: readonly KeysetKey[] = [
	{ column: 'joined_at', ascending: true, nullsFirst: false },
	{ column: 'user_id', ascending: true, nullsFirst: false },
];

/// One occurrence's attendee list, one keyset page at a time: pass the
/// previous page's `next` as `after` to load more. A cursor rather than an
/// offset because an RSVP withdrawn between two reads moves every later
/// attendee up one, and offset 50 then starts a row late.
export async function fetchEventAttendees(
	eventId: string,
	instanceStart: string,
	opts?: { limit?: number; after?: KeysetCursor | null }
): Promise<KeysetPage<EventAttendee & {
	display_name: string | null;
	avatar_url: string | null;
}>> {
	const limit = opts?.limit ?? ROSTER_PAGE_SIZE;
	const after = opts?.after ? keysetAfter(EVENT_ATTENDEE_ORDER, opts.after) : undefined;
	if (after === null) return { rows: [], next: null };
	let q = supabase
		.from(TABLES.event_attendees)
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart);
	if (after) q = q.or(after);
	for (const k of EVENT_ATTENDEE_ORDER) {
		q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
	}
	const { data: attendees } = await q.limit(limit);
	if (!attendees) return { rows: [], next: null };
	const userIds = (attendees as EventAttendee[]).map((a) => a.user_id);
	const byId = await fetchProfilesByIds(userIds);
	return {
		rows: (attendees as EventAttendee[]).map((a) => ({
			...a,
			display_name: byId.get(a.user_id)?.display_name ?? null,
			avatar_url: byId.get(a.user_id)?.avatar_url ?? null
		})),
		next: nextCursor(EVENT_ATTENDEE_ORDER, attendees, limit),
	};
}

/// Exact per-status RSVP tallies + the viewer's own status for an event
/// instance, independent of the paginated `fetchEventAttendees` roster.
/// The going / maybe / declined / waitlisted counts drive the capacity +
/// waitlist math and the RSVP pills, which must stay exact even when the
/// displayed roster is only its first page — so this reads the status
/// column alone (no profile join) rather than the full member records.
export interface EventRsvpSummary {
	going: number;
	maybe: number;
	declined: number;
	waitlisted: number;
	viewerStatus: RsvpStatus | null;
}

export async function fetchEventRsvpSummary(
	eventId: string,
	instanceStart: string
): Promise<EventRsvpSummary> {
	const viewerId = auth.user?.id ?? null;

	// Counted in the database, one HEAD request per status, rather than by
	// pulling every attendee row and tallying here. PostgREST caps a returned
	// result at 1000 rows and says nothing when it does, so the old read
	// silently became a count of the first thousand: past that the capacity
	// and waitlist math believed a full event had room, and the viewer's own
	// row could fall outside the page entirely — `viewerStatus` then read null
	// and the page re-showed "Register for £X" to someone who had already
	// paid, burning a Stripe session and a capacity-holding pending order.
	// `count: 'exact'` is a `count(*)` over the filtered set and is not
	// subject to that cap; `head: true` transfers no rows at all.
	//
	// The viewer's own status is a separate one-row read for the same reason:
	// it must not depend on their row appearing in any page.
	const statuses = ['going', 'maybe', 'declined', 'waitlisted'] as const;
	const [counts, viewerRow] = await Promise.all([
		Promise.all(
			statuses.map((status) =>
				supabase
					.from(TABLES.event_attendees)
					.select('user_id', { count: 'exact', head: true })
					.eq('event_id', eventId)
					.eq('instance_start', instanceStart)
					.eq('status', status)
			)
		),
		viewerId
			? supabase
					.from(TABLES.event_attendees)
					.select('status')
					.eq('event_id', eventId)
					.eq('instance_start', instanceStart)
					.eq('user_id', viewerId)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null })
	]);

	// A failed read must not come back as a zeroed summary: `viewerStatus`
	// null is what tells the page the viewer has no slot, so a swallowed
	// error re-shows "Register for £X" to someone who has already paid. A
	// missing count is the same claim about capacity, so it throws too.
	for (const res of counts) {
		if (res.error) throw dbError(res.error);
	}
	if (viewerRow.error) throw dbError(viewerRow.error);

	const summary: EventRsvpSummary = {
		going: counts[0].count ?? 0,
		maybe: counts[1].count ?? 0,
		declined: counts[2].count ?? 0,
		waitlisted: counts[3].count ?? 0,
		viewerStatus: ((viewerRow.data as { status?: string } | null)?.status ??
			null) as RsvpStatus | null
	};
	return summary;
}

// --- Event results (leaderboard) ---

export interface EventResultRow {
	id: string;
	// Null for bib-only finishers imported from a chip-timing CSV
	// (persona #43) — those rows carry `bib` + `finisher_name` instead.
	user_id: string | null;
	bib: string | null;
	finisher_name: string | null;
	run_id: string | null;
	duration_s: number;
	distance_m: number;
	rank: number | null;
	finisher_status: FinisherStatus;
	age_grade_pct: number | null;
	note: string | null;
	created_at: string;
	organiser_approved: boolean;
	// Race provenance (migration 20270727000001). `course_id` picks the
	// leaderboard; `duration_s` stays the ranked time, which on a gun-started
	// race is `gun_time_s`.
	course_id: string | null;
	gun_time_s: number | null;
	chip_time_s: number | null;
	finish_method: FinishMethod | null;
	// organiser_approved_by / organiser_approved_at are admin-side
	// columns; intentionally omitted from `fetchEventResults`'s public
	// read path. Add them back via a service-role-only fetcher if/when
	// an admin moderation UI needs them.
}

export interface EventResultWithUser extends EventResultRow {
	display_name: string | null;
	avatar_url: string | null;
}

export async function fetchEventResults(
	eventId: string,
	instanceStart: string
): Promise<EventResultWithUser[]> {
	// Don't request organiser_approved_by / organiser_approved_at on
	// the public read path — those are admin-operational fields with
	// no UI consumer here. The boolean `organiser_approved` is what
	// the leaderboard actually shows. Audit pass 3 caught the wider
	// projection leaking the approving admin's UUID to anon.
	//
	// Read from the redaction view rather than the base table —
	// `event_results_redacted` nulls `run_id` for non-owner rows so
	// the public leaderboard can't bridge to a participant's private
	// run via the linked run_id. (Migration 20260805_001.)
	const { data: results } = await supabase
		.from('event_results_redacted')
		.select(
			'id, user_id, bib, finisher_name, run_id, duration_s, distance_m, rank, finisher_status, age_grade_pct, note, created_at, organiser_approved, course_id, gun_time_s, chip_time_s, finish_method'
		)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('rank', { ascending: true, nullsFirst: false })
		.order('created_at', { ascending: true });
	if (!results) return [];
	const rows = results as EventResultRow[];
	if (rows.length === 0) return [];
	const userIds = rows.map((r) => r.user_id).filter((id): id is string => id !== null);
	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	if (userIds.length > 0) {
		const { data: profiles } = await queryChunked(userIds, (part) =>
			supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', part)
		);
		for (const p of profiles ?? [])
			byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });
	}
	return rows.map((r) => ({
		...r,
		// Bib-only imported finishers have no profile — fall back to the
		// name printed on the results sheet.
		display_name: r.user_id ? (byId.get(r.user_id)?.display_name ?? null) : r.finisher_name,
		avatar_url: r.user_id ? (byId.get(r.user_id)?.avatar_url ?? null) : null,
	}));
}

export async function submitEventResult(params: {
	eventId: string;
	instanceStart: string;
	durationS: number;
	distanceM: number;
	runId?: string | null;
	finisherStatus?: FinisherStatus;
	ageGradePct?: number | null;
	note?: string | null;
	// Set on a raced occurrence: a time the racer submitted themselves is
	// `manual`, and its run's own duration is the chip time.
	finishMethod?: FinishMethod | null;
	chipTimeS?: number | null;
	courseId?: string | null;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const noteTrimmed = params.note?.trim();
	const { error } = await supabase.from(TABLES.event_results).upsert(
		{
			event_id: params.eventId,
			instance_start: params.instanceStart,
			user_id: userId,
			run_id: params.runId ?? null,
			duration_s: params.durationS,
			distance_m: params.distanceM,
			finisher_status: params.finisherStatus ?? 'finished',
			age_grade_pct: params.ageGradePct ?? null,
			// Trim + collapse empty-after-trim to null so a whitespace
			// note from the result-submit dialog doesn't survive to the
			// DB. Mobile's `SocialService.submitEventResult` applies the
			// same normalisation.
			note: noteTrimmed && noteTrimmed.length > 0 ? noteTrimmed : null,
			...(params.finishMethod !== undefined ? { finish_method: params.finishMethod } : {}),
			...(params.chipTimeS !== undefined ? { chip_time_s: params.chipTimeS } : {}),
			...(params.courseId !== undefined ? { course_id: params.courseId } : {}),
			updated_at: new Date().toISOString(),
		},
		{ onConflict: 'event_id,instance_start,user_id' }
	);
	if (error) throw dbError(error);
	markListsStale('runs', 'history', 'routes');
	// Best-effort back-link so the run-detail page can show "ran at {event}".
	if (params.runId) {
		await supabase
			.from(TABLES.runs)
			.update({ event_id: params.eventId })
			.eq('id', params.runId)
			.eq('user_id', userId);
	}
}

export async function removeEventResult(
	eventId: string,
	instanceStart: string
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.event_results)
		.delete()
		.eq('event_id', eventId)
		.eq('user_id', userId)
		.eq('instance_start', instanceStart);
	if (error) throw dbError(error);
}

// Organiser bulk-import of chip-timing results (persona #43). Rows are
// bib-only finishers (no account) keyed on bib; the upsert arbiter is the
// `(event_id, instance_start, bib)` unique constraint so re-importing a
// corrected sheet updates in place rather than duplicating. RLS gates the
// write to the event's organiser via `event_results_insert_organiser`.
//
// `user_id` is deliberately NOT in the payload: on a fresh bib it defaults
// to NULL (account-less), and on a re-import of a bib that a runner has
// since claimed (persona #43 claim flow → user_id set by an organiser
// approval) the column is left untouched so a corrected re-upload can't
// silently revert the result to account-less and wipe the claim.
export async function bulkImportEventResults(params: {
	eventId: string;
	instanceStart: string;
	rows: ParsedResultRow[];
}): Promise<void> {
	if (params.rows.length === 0) return;
	const payload = params.rows.map((r) => ({
		event_id: params.eventId,
		instance_start: params.instanceStart,
		bib: r.bib,
		finisher_name: r.finisherName,
		duration_s: r.durationS,
		distance_m: r.distanceM,
		finisher_status: r.finisherStatus,
		updated_at: new Date().toISOString(),
	}));
	const { error } = await supabase
		.from(TABLES.event_results)
		.upsert(payload, { onConflict: 'event_id,instance_start,bib' });
	if (error) throw dbError(error);
}

export interface EventResultClaim {
	id: string;
	result_id: string;
	claimant_id: string;
	status: 'pending' | 'approved' | 'rejected';
	created_at: string;
}

export interface EventResultClaimWithUser extends EventResultClaim {
	claimant_name: string | null;
	// The bib + finisher_name of the result being claimed, for the
	// organiser's approval queue ("Bob claims bib 102 — Alice Anon").
	bib: string | null;
	finisher_name: string | null;
}

// A logged-in runner claims a bib-only imported result (persona #43).
// Organiser-approve trust model — the row stays bib-only until an organiser
// approves via approveEventResultClaim. Returns the created/re-opened claim.
export async function requestEventResultClaim(resultId: string): Promise<void> {
	const { error } = await supabase.rpc('claim_event_result', { p_result_id: resultId });
	if (error) throw dbError(error);
}

// The current user's claims for a given (event, instance), keyed by
// result_id so the leaderboard can show a "claim pending" state on the row
// the viewer claimed. Reads through the RLS SELECT policy (claimant sees own).
export async function fetchMyEventResultClaims(
	eventId: string,
	instanceStart: string
): Promise<Map<string, EventResultClaim['status']>> {
	const userId = auth.user?.id;
	if (!userId) return new Map();
	const { data } = await supabase
		.from('event_result_claims')
		.select('result_id, status, event_results!inner(event_id, instance_start)')
		.eq('claimant_id', userId)
		.eq('event_results.event_id', eventId)
		.eq('event_results.instance_start', instanceStart);
	const map = new Map<string, EventResultClaim['status']>();
	for (const r of (data ?? []) as Array<{ result_id: string; status: EventResultClaim['status'] }>)
		map.set(r.result_id, r.status);
	return map;
}

// Pending claims an organiser needs to adjudicate for a given (event,
// instance). RLS gates this to organisers of the parent event.
export async function fetchPendingEventResultClaims(
	eventId: string,
	instanceStart: string
): Promise<EventResultClaimWithUser[]> {
	const { data } = await supabase
		.from('event_result_claims')
		.select(
			'id, result_id, claimant_id, status, created_at, event_results!inner(event_id, instance_start, bib, finisher_name)'
		)
		.eq('status', 'pending')
		.eq('event_results.event_id', eventId)
		.eq('event_results.instance_start', instanceStart)
		.order('created_at', { ascending: true });
	const rows = data ?? [];
	if (rows.length === 0) return [];
	const claimantIds = [...new Set(rows.map((r) => r.claimant_id))];
	const { data: profiles } = await queryChunked(claimantIds, (part) =>
		supabase.from('user_profiles').select('id, display_name').in('id', part)
	);
	const byId = new Map<string, string | null>();
	for (const p of profiles ?? []) byId.set(p.id, p.display_name);
	return rows.map((r) => ({
		id: r.id,
		result_id: r.result_id,
		claimant_id: r.claimant_id,
		status: parseClaimStatus(r.status),
		created_at: r.created_at,
		claimant_name: byId.get(r.claimant_id) ?? null,
		bib: r.event_results.bib,
		finisher_name: r.event_results.finisher_name
	}));
}

/// Defensive narrow on read for `event_result_claims.status`, which carries a
/// CHECK the generated row types as a bare `string`. An unrecognised status
/// reads as `'pending'`: the two other values are terminal decisions an
/// organiser made, and inventing one from a value this build cannot interpret
/// would either approve a claim nobody approved or bury it as rejected.
function parseClaimStatus(raw: string): EventResultClaim['status'] {
	switch (raw) {
		case 'approved':
		case 'rejected':
			return raw;
		default:
			return 'pending';
	}
}

// Organiser approves or rejects a claim. Approving attaches the claimant's
// account to the result row and auto-rejects competing claims (server-side).
export async function decideEventResultClaim(claimId: string, approve: boolean): Promise<void> {
	const { error } = await supabase.rpc('decide_event_result_claim', {
		p_claim_id: claimId,
		p_approve: approve
	});
	if (error) throw dbError(error);
}

export interface RecentRunOption {
	id: string;
	started_at: string;
	duration_s: number;
	distance_m: number;
	activity_type: string;
}

export async function fetchRecentRunsForPicker(limit = 20): Promise<RecentRunOption[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from(TABLES.runs)
		.select('id, started_at, duration_s, distance_m, activity_type')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (!data) return [];
	return data.map((r) => ({
		id: r.id,
		started_at: r.started_at,
		duration_s: r.duration_s,
		distance_m: r.distance_m,
		activity_type: r.activity_type ?? 'run',
	}));
}

// --- Race sessions (live race mode) ---

export interface RaceSessionRow {
	event_id: string;
	instance_start: string;
	status: RaceSessionStatus;
	started_at: string | null;
	started_by: string | null;
	finished_at: string | null;
	is_auto_approve: boolean;
	created_at: string;
	updated_at: string;
}

export async function fetchRaceSession(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow | null> {
	// Read from the redaction view rather than the base table —
	// `race_sessions_redacted` masks `started_by` + `is_auto_approve`
	// for non-admin viewers (decisions per /audit/all 2026-05-07,
	// migration 20260813_001). Admin row-level mutations
	// (armRace / startRace / endRace) below keep writing the base
	// table so the columns reach Postgres unmasked.
	const { data } = await supabase
		.from('race_sessions_redacted')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.maybeSingle();
	return (data as RaceSessionRow | null) ?? null;
}

export async function armRace(
	eventId: string,
	instanceStart: string,
	autoApprove: boolean
): Promise<RaceSessionRow> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('race_sessions')
		.upsert(
			{
				event_id: eventId,
				instance_start: instanceStart,
				status: 'armed',
				started_at: null,
				started_by: null,
				finished_at: null,
				is_auto_approve: autoApprove,
				updated_at: new Date().toISOString(),
			},
			{ onConflict: 'event_id,instance_start' }
		)
		.select()
		.single();
	if (error) throw dbError(error);
	return data as RaceSessionRow;
}

export async function startRace(
	eventId: string,
	instanceStart: string
): Promise<RaceSessionRow> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('race_sessions')
		.update({
			status: 'running',
			started_at: new Date().toISOString(),
			started_by: userId,
			updated_at: new Date().toISOString(),
		})
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.select()
		.single();
	if (error) throw dbError(error);
	return data as RaceSessionRow;
}

export async function endRace(
	eventId: string,
	instanceStart: string,
	status: 'finished' | 'cancelled' = 'finished'
): Promise<RaceSessionRow> {
	// The `race_sessions_status_temporal_invariant` CHECK constraint
	// (migration `20260529000003`) requires `finished_at IS NULL`
	// when `status='cancelled'` and `finished_at IS NOT NULL` when
	// `status='finished'`. Stamping finished_at on a cancel write
	// violates the constraint — the UPDATE errors with
	// check_violation, the page's `raceSession` state never updates,
	// and the Arm-race button never re-appears. The
	// `event-race-control.spec.ts:170` Cancel-from-armed test timed
	// out on every CI run for this reason. Only stamp finished_at
	// when transitioning to `finished`.
	const patch: Updatable<'race_sessions'> = {
		status,
		updated_at: new Date().toISOString(),
	};
	if (status === 'finished') {
		patch.finished_at = new Date().toISOString();
	}
	const { data, error } = await supabase
		.from('race_sessions')
		.update(patch)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.select()
		.single();
	if (error) throw dbError(error);
	return data as RaceSessionRow;
}

export async function approveEventResult(
	eventId: string,
	instanceStart: string,
	userId: string,
	approve: boolean
): Promise<void> {
	const { error } = await supabase.rpc('approve_event_result', {
		p_event_id: eventId,
		p_instance_start: instanceStart,
		p_user_id: userId,
		p_approve: approve,
	});
	if (error) throw dbError(error);
}

// Approve / unverify a single result by its row id. The `approve_event_result`
// RPC keys on (event, instance, user_id) so it can only touch account-linked
// rows — a bib-only imported finisher has user_id = NULL and is unreachable
// through it. This path goes straight at the row, gated by the
// `event_results_update_self_or_director` RLS policy (a race_director of the
// event's club may update any of its result rows). Audit columns are written
// client-side from the signed-in director to mirror what the RPC's auth.uid()
// would set.
export async function approveEventResultById(
	resultId: string,
	approve: boolean
): Promise<void> {
	const directorId = auth.user?.id;
	if (!directorId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.event_results)
		.update({
			organiser_approved: approve,
			organiser_approved_by: directorId,
			organiser_approved_at: new Date().toISOString(),
			updated_at: new Date().toISOString(),
		})
		.eq('id', resultId)
		// This path is for bib-only (unmatched) results; matched-user rows
		// approve via approve_event_result. Constrain to null-user rows so a
		// stray caller can't reach a matched runner's result through here
		// (the director RLS policy already bounds it to their own events).
		.is('user_id', null);
	if (error) throw dbError(error);
}

/// Organiser edit of one result's time and / or status. Gated by the
/// `event_results_update_self_or_director` policy (race director) or, for a
/// bib-only row, `event_results_update_organiser_bib`; the
/// `event_results_race_guard` trigger stamps `finish_method = 'host'` because
/// the editor is not the result's runner.
export async function editEventResultAsHost(
	resultId: string,
	patch: { duration_s: number; gun_time_s?: number; finisher_status: FinisherStatus }
): Promise<void> {
	const update: Updatable<'event_results'> = {
		duration_s: patch.duration_s,
		finisher_status: patch.finisher_status,
		updated_at: new Date().toISOString(),
	};
	if (patch.gun_time_s !== undefined) update.gun_time_s = patch.gun_time_s;
	const { error } = await supabase.from(TABLES.event_results).update(update).eq('id', resultId);
	if (error) throw dbError(error);
}

/// How many racers End would mark DNF (pinged the race, filed no result).
/// Null when the caller is not a race director for the event's club, or the
/// count could not be read — the End dialog then omits the figure rather than
/// stating a wrong one.
export async function fetchRaceDnfPreview(
	eventId: string,
	instanceStart: string
): Promise<number | null> {
	const { data, error } = await supabase.rpc(
		'race_pending_dnf_count',
		{ p_event_id: eventId, p_instance_start: instanceStart },
		{ get: true }
	);
	if (error) {
		console.warn('fetchRaceDnfPreview failed', error);
		return null;
	}
	return typeof data === 'number' ? data : null;
}

// --- Event courses (multi-course races) ---

/// An event's courses in display order. Empty for an event with no route and
/// no courses — a plain club run.
export async function fetchEventCourses(eventId: string): Promise<EventCourse[]> {
	const { data, error } = await supabase
		.from(TABLES.event_courses)
		.select('id, event_id, route_id, name, distance_m, sort_order')
		.eq('event_id', eventId)
		.order('sort_order', { ascending: true })
		.order('name', { ascending: true });
	if (error) throw dbError(error);
	return sortCourses(data ?? []);
}

/// Persist the event editor's course list (a dropped course's RSVPs and
/// results fall back to no course). The write order and the refused-write
/// check live in `applyCourseSave`; each statement returns its ids so a write
/// RLS filtered to nothing is reported, not taken for success. Organiser-only
/// through the `event_courses_organiser_*` policies.
export async function saveEventCourses(
	eventId: string,
	existing: EventCourse[],
	drafts: CourseDraft[]
): Promise<void> {
	const table = () => supabase.from(TABLES.event_courses);
	await applyCourseSave(planCourseSave(existing, drafts), {
		delete: async (ids) => {
			const { data, error } = await queryChunked(ids, (part) =>
				table().delete().in('id', part).select('id')
			);
			return { error, rows: data?.length ?? 0 };
		},
		update: async (id, patch) => {
			const { data, error } = await table().update(patch).eq('id', id).select('id');
			return { error, rows: data?.length ?? 0 };
		},
		insert: async (rows) => {
			const { data, error } = await table()
				.insert(rows.map((w) => ({ ...w, event_id: eventId })))
				.select('id');
			return { error, rows: data?.length ?? 0 };
		}
	});
}

/// Each attendee's chosen course for one occurrence, keyed by user id; an
/// attendee with no pick is absent. Read under the same club-visibility gate
/// as `race_pings`, so whoever can see a runner on course can see their
/// course. Throws on a failed read so the spectator page can keep the split
/// it already has rather than collapse every runner into "no course".
export async function fetchAttendeeCourses(
	eventId: string,
	instanceStart: string
): Promise<Map<string, string>> {
	const { data, error } = await supabase
		.from(TABLES.event_attendees)
		.select('user_id, course_id')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.not('course_id', 'is', null);
	if (error) throw dbError(error);
	const out = new Map<string, string>();
	for (const r of data ?? []) if (r.course_id) out.set(r.user_id, r.course_id);
	return out;
}

/// The signed-in viewer's chosen course for one occurrence, or null.
export async function fetchMyEventCourse(
	eventId: string,
	instanceStart: string
): Promise<string | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data } = await supabase
		.from(TABLES.event_attendees)
		.select('course_id')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.eq('user_id', userId)
		.maybeSingle();
	return data?.course_id ?? null;
}

export interface RacePingRow {
	id: number;
	event_id: string;
	instance_start: string;
	user_id: string;
	at: string;
	lat: number;
	lng: number;
	distance_m: number | null;
	elapsed_s: number | null;
	bpm: number | null;
	coarse: boolean;
}

/// Recent pings for a race instance, newest first. The spectator page
/// derives both the leaderboard (latest per user) and per-user trails
/// from this single fetch. Capped at `limit` rows; the index on
/// (event_id, instance_start, at desc) makes this cheap.
export async function fetchRecentRacePings(
	eventId: string,
	instanceStart: string,
	limit = 1000
): Promise<RacePingRow[]> {
	const { data } = await supabase
		.from('race_pings')
		.select('*')
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('at', { ascending: false })
		.limit(limit);
	return (data as RacePingRow[]) ?? [];
}

/// Latest ping per runner for the live leaderboard, ordered furthest-
/// first with a deterministic tie-break (see `compareLeaderboard`).
///
/// Backed by the `latest_race_pings` RPC (DISTINCT ON (user_id)) rather
/// than a flat newest-N fetch: a flat cap is spent on the high-cadence
/// front-of-pack pings, so a slow back-of-pack runner whose newest ping
/// has aged past the window would silently drop off the board. The RPC
/// returns exactly one row per runner, so every runner who has pinged
/// is always represented regardless of total ping volume. It is
/// SECURITY INVOKER, so the same race_pings RLS that gated the bare-
/// table read still applies.
export async function fetchLatestRacePings(
	eventId: string,
	instanceStart: string
): Promise<RacePingRow[]> {
	const { data } = await supabase.rpc('latest_race_pings', {
		p_event_id: eventId,
		p_instance_start: instanceStart
	}, { get: true });
	const rows = (data as RacePingRow[]) ?? [];
	return rows.sort(compareLeaderboard);
}

export async function postRacePing(params: {
	eventId: string;
	instanceStart: string;
	lat: number;
	lng: number;
	distanceM?: number;
	elapsedS?: number;
	bpm?: number;
}): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase.from('race_pings').insert({
		event_id: params.eventId,
		instance_start: params.instanceStart,
		user_id: userId,
		lat: params.lat,
		lng: params.lng,
		distance_m: params.distanceM ?? null,
		elapsed_s: params.elapsedS ?? null,
		bpm: params.bpm ?? null,
	});
	if (error) throw dbError(error);
}

// --- Club posts (owner updates) ---

export async function fetchClubPosts(
	clubId: string,
	limit = 20
): Promise<ClubPostWithAuthor[]> {
	// Top-level posts only; replies are loaded lazily per-post.
	const { data: posts } = await supabase
		.from(TABLES.club_posts)
		.select('*')
		.eq('club_id', clubId)
		.is('parent_post_id', null)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (!posts) return [];
	return enrichPosts(posts as ClubPost[]);
}

export async function fetchPostReplies(parentId: string, limit = 200): Promise<ClubPostWithAuthor[]> {
	const { data: posts } = await supabase
		.from(TABLES.club_posts)
		.select('*')
		.eq('parent_post_id', parentId)
		.order('created_at', { ascending: true })
		.limit(limit);
	if (!posts) return [];
	return enrichPosts(posts as ClubPost[]);
}

async function enrichPosts(posts: ClubPost[]): Promise<ClubPostWithAuthor[]> {
	if (posts.length === 0) return [];
	const authorIds = Array.from(new Set(posts.map((p) => p.author_id)));
	const topLevelIds = posts.filter((p) => !p.parent_post_id).map((p) => p.id);

	const [profilesRes, repliesRes] = await Promise.all([
		queryChunked(authorIds, (part) =>
			supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', part)
		),
		topLevelIds.length > 0
			? queryChunked(topLevelIds, (part) =>
					supabase
						.from(TABLES.club_posts)
						.select('parent_post_id')
						.in('parent_post_id', part)
						.limit(5000)
				)
			: Promise.resolve({ data: [] as { parent_post_id: string }[] })
	]);

	const byId = new Map<string, { display_name: string | null; avatar_url: string | null }>();
	for (const p of profilesRes.data ?? []) byId.set(p.id, { display_name: p.display_name, avatar_url: p.avatar_url });

	const replyCounts = new Map<string, number>();
	for (const row of (repliesRes.data ?? []) as { parent_post_id: string }[]) {
		replyCounts.set(row.parent_post_id, (replyCounts.get(row.parent_post_id) ?? 0) + 1);
	}

	return posts.map((post) => ({
		...post,
		author_display_name: byId.get(post.author_id)?.display_name ?? null,
		author_avatar_url: byId.get(post.author_id)?.avatar_url ?? null,
		reply_count: replyCounts.get(post.id) ?? 0
	}));
}

export async function createClubPost(input: {
	club_id: string;
	body: string;
	event_id?: string | null;
	event_instance_start?: string | null;
	parent_post_id?: string | null;
}): Promise<ClubPost> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from(TABLES.club_posts)
		.insert({
			club_id: input.club_id,
			event_id: input.event_id ?? null,
			event_instance_start: input.event_instance_start ?? null,
			parent_post_id: input.parent_post_id ?? null,
			author_id: userId,
			body: input.body.trim()
		})
		.select()
		.single();
	if (error) throw dbError(error);
	return data as ClubPost;
}

export async function deleteClubPost(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.club_posts).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Training plans ---

/// Same as `fetchMyPlans` but surfaces the error alongside the rows, so
/// a caller can show a "couldn't load — retry" state instead of an empty
/// list that's indistinguishable from "user has no plans". Mirrors the
/// `fetchRoutesWithError` convention.
export async function fetchMyPlansWithError(
	limit = 100
): Promise<{ plans: TrainingPlan[]; error: string | null }> {
	// RLS also lets a coach read their linked athletes' plans, so the owner
	// filter is what keeps those out of the coach's own list; templates live
	// in the same table and are filtered out too (decisions §35).
	const userId = await currentViewerId();
	if (!userId) return { plans: [], error: 'Not signed in' };
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('user_id', userId)
		.eq('is_template', false)
		.order('created_at', { ascending: false })
		.limit(limit);
	return { plans: (data ?? []) as TrainingPlan[], error: error?.message ?? null };
}

export async function fetchMyPlans(limit = 100): Promise<TrainingPlan[]> {
	return (await fetchMyPlansWithError(limit)).plans;
}

/// Plan templates owned by `clubId`. Visible to club members; admins
/// can write. See decisions §35.
export async function fetchClubTemplates(clubId: string, limit = 100): Promise<TrainingPlan[]> {
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_template', true)
		.eq('club_id', clubId)
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error) {
		console.error('fetchClubTemplates failed', error);
		return [];
	}
	return (data ?? []) as TrainingPlan[];
}

/// Plan templates for many clubs in one query, grouped by club id — the
/// /plans/new picker used to call fetchClubTemplates once per club (N+1).
/// Per-club ordering matches fetchClubTemplates (created_at desc); the
/// limit scales with the club count so no club is starved by another's
/// template volume.
export async function fetchClubTemplatesForClubs(
	clubIds: string[],
	limitPerClub = 100
): Promise<Map<string, TrainingPlan[]>> {
	const grouped = new Map<string, TrainingPlan[]>();
	if (clubIds.length === 0) return grouped;
	// Each club lands in exactly one chunk, so its own created_at order
	// survives the merge — the grouping below is per club.
	const { data, error } = await queryChunked(clubIds, (part) =>
		supabase
			.from('training_plans')
			.select('*')
			.eq('is_template', true)
			.in('club_id', part)
			.order('created_at', { ascending: false })
			.limit(limitPerClub * part.length)
	);
	if (error) {
		console.error('fetchClubTemplatesForClubs failed', error);
		return grouped;
	}
	for (const row of (data ?? []) as TrainingPlan[]) {
		if (!row.club_id) continue;
		const list = grouped.get(row.club_id);
		if (list) list.push(row);
		else grouped.set(row.club_id, [row]);
	}
	return grouped;
}

/// Clone a template into a user-owned active plan, anchored at
/// new_start_date. Returns the new plan's id; caller should navigate
/// to /plans/{id}. The RPC enforces authorisation server-side and resolves
/// overlapping active plans per `overlap` in the same transaction.
export async function clonePlanTemplate(
	templateId: string,
	newStartDate: string,
	overlap: PlanOverlapChoice = 'refuse'
): Promise<string> {
	markListsStale('plans');
	const { data, error } = await supabase.rpc('clone_plan_template', {
		template_id: templateId,
		new_start_date: newStartDate,
		p_overlap: overlap,
	});
	if (error) {
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data as string;
}

/// Toggle is_template on an existing plan (admin / coach action). When
/// flipping a club-owned plan to a template the caller must already
/// be a club admin via RLS.
export async function setPlanIsTemplate(
	planId: string,
	isTemplate: boolean,
	clubId: string | null = null
): Promise<void> {
	const patch: Updatable<'training_plans'> = {
		is_template: isTemplate,
		updated_at: new Date().toISOString(),
	};
	// If we're flagging it as a template, drop active status so it
	// doesn't claim the per-user "one active plan" slot — the
	// training_plans_template_status CHECK forbids active+template.
	if (isTemplate) {
		patch.status = 'completed';
		if (clubId !== null) patch.club_id = clubId;
	} else {
		// Un-templating MUST also release the club. Both RLS WITH CHECKs on
		// training_plans require a club-owned row to be a template
		// ("users own their plans" allows club_id IS NULL *or* is_template),
		// so clearing only is_template left the new row satisfying neither
		// policy and the update 403'd — the Unpublish button never worked.
		patch.club_id = null;
	}
	markListsStale('plans');
	const { error } = await supabase.from('training_plans').update(patch).eq('id', planId);
	if (error) throw dbError(error);
}

export type PublicPlanLibraryEntry = TrainingPlan & {
	author_handle: string | null;
};

/// Browse the public plan library — published plans any user can clone
/// (migration 20270126_001). Optional case-insensitive name search, every
/// character matched literally (`literalSubstringPattern`, decisions § 1937).
/// Each entry carries the author's public display name (handle) joined
/// from user_profiles; no other author data is exposed. Mirrors mobile
/// `TrainingService.fetchPublicPlanLibrary`.
export async function fetchPublicPlanLibrary(
	query = '',
	limit = 100
): Promise<{ plans: PublicPlanLibraryEntry[]; error: string | null }> {
	let q = supabase
		.from('training_plans')
		.select('*')
		.eq('is_public_template', true)
		.order('created_at', { ascending: false })
		.limit(limit);
	const trimmed = query.trim();
	if (trimmed) q = q.regexIMatch('name', literalSubstringPattern(trimmed));
	const { data, error } = await q;
	if (error) return { plans: [], error: error.message };
	const rows = (data ?? []) as TrainingPlan[];
	const authorIds = [...new Set(rows.map((r) => r.user_id))];
	const byId = new Map<string, string | null>();
	if (authorIds.length > 0) {
		const { data: profiles } = await supabase
			.from('user_profiles')
			.select('id, display_name')
			.in('id', authorIds);
		for (const p of profiles ?? []) byId.set(p.id, p.display_name);
	}
	return {
		plans: rows.map((r) => ({ ...r, author_handle: byId.get(r.user_id) ?? null })),
		error: null,
	};
}

/// Clone a public-library plan into a user-owned active plan, anchored
/// at new_start_date. Returns the new plan's id. The clone_public_plan
/// RPC authorises on public visibility server-side and strips the
/// publisher's private fitness data.
export async function clonePublicPlan(
	templateId: string,
	newStartDate: string,
	overlap: PlanOverlapChoice = 'refuse'
): Promise<string> {
	markListsStale('plans');
	const { data, error } = await supabase.rpc('clone_public_plan', {
		template_id: templateId,
		new_start_date: newStartDate,
		p_overlap: overlap,
	});
	if (error) {
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data as string;
}

/// Publish one of the viewer's plans to the public library: copy the
/// plan row + every plan_week + plan_workout into a new
/// `is_public_template = true` sibling, leaving the original plan
/// untouched on the user's list (mirrors `publishPlanAsTemplate`, in the
/// public direction). Publisher fitness data (vdot/current_5k_seconds)
/// is stripped so it can't leak to cloners. Returns the new template id.
export async function publishPlanToLibrary(sourcePlanId: string): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const source = await fetchPlan(sourcePlanId);
	if (!source.plan) throw new Error('Source plan not found');
	if (source.plan.user_id !== userId) {
		throw new Error('Only the plan owner can publish');
	}
	const src = source.plan;

	markListsStale('plans');
	const { data: tmpl, error: planErr } = await supabase
		.from('training_plans')
		.insert({
			...planHeadCopyFields(src),
			user_id: userId,
			vdot: null,
			current_5k_seconds: null,
			notes: null,
			status: 'completed',
			is_template: true,
			is_public_template: true,
			club_id: null,
			parent_template_id: null,
		})
		.select('id')
		.single();
	if (planErr || !tmpl) throw planErr ? dbError(planErr) : new Error('Template insert failed');
	const newPlanId = tmpl.id as string;

	if (source.weeks.length === 0) return newPlanId;

	const weekRows = planWeekCopyRows(source.weeks, newPlanId);
	const { data: weekRes, error: weekErr } = await supabase
		.from('plan_weeks')
		.insert(weekRows)
		.select('id, week_index');
	if (weekErr || !weekRes) throw weekErr ? dbError(weekErr) : new Error('Weeks insert failed');

	const byIdx = new Map<number, string>();
	for (const w of weekRes as { id: string; week_index: number }[]) {
		byIdx.set(w.week_index, w.id);
	}
	const oldToNew = new Map<string, string>();
	for (const old of source.weeks) {
		const newId = byIdx.get(old.week_index);
		if (newId) oldToNew.set(old.id, newId);
	}

	const workoutRows = planWorkoutCopyRows(source.workouts, oldToNew);
	if (workoutRows.length > 0) {
		const { error: woErr } = await supabase.from('plan_workouts').insert(workoutRows);
		if (woErr) throw dbError(woErr);
	}

	return newPlanId;
}

/// Unpublish a public-library template the viewer owns — deletes the
/// published copy (weeks + workouts cascade). Owner-only via RLS.
export async function unpublishFromLibrary(templateId: string): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase
		.from('training_plans')
		.delete()
		.eq('id', templateId)
		.eq('is_public_template', true);
	if (error) throw dbError(error);
}

/// The viewer's own published public-library plans (so the plan-detail
/// page can show whether a plan is already published and offer Unpublish).
export async function fetchMyPublishedPlans(): Promise<TrainingPlan[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from('training_plans')
		.select('*')
		.eq('is_public_template', true)
		.eq('user_id', userId)
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchMyPublishedPlans failed', error);
		return [];
	}
	return (data ?? []) as TrainingPlan[];
}

/**
 * Clone a user's plan into a new club-owned template, leaving the
 * original plan untouched on the user's /plans list. Mirrors
 * `clone_plan_template` but in the publish direction: copy the plan
 * row + every plan_week + every plan_workout into a new
 * `is_template = true, club_id = X` sibling. Completion fields are
 * intentionally not copied — templates start fresh.
 */
export async function publishPlanAsTemplate(
	sourcePlanId: string,
	clubId: string
): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const source = await fetchPlan(sourcePlanId);
	if (!source.plan) throw new Error('Source plan not found');
	if (source.plan.user_id !== userId) {
		throw new Error('Only the plan owner can publish');
	}
	const src = source.plan;

	markListsStale('plans');
	// vdot, current_5k_seconds and notes are the publisher's private
	// fields — fitness proxies and their own free text (training
	// constraints, injury history). They aren't template-design values;
	// copying them into a row every club member can SELECT leaks
	// personal data. Stripped here and enforced by the trigger in
	// migration 20270508_001, which is what actually holds — this
	// insert is reachable by REST without it.
	const { data: tmpl, error: planErr } = await supabase
		.from('training_plans')
		.insert({
			...planHeadCopyFields(src),
			user_id: userId,
			vdot: null,
			current_5k_seconds: null,
			notes: null,
			status: 'completed',
			is_template: true,
			club_id: clubId,
			parent_template_id: null,
		})
		.select('id')
		.single();
	if (planErr || !tmpl) throw planErr ? dbError(planErr) : new Error('Template insert failed');
	const newPlanId = tmpl.id as string;

	if (source.weeks.length === 0) return newPlanId;

	const weekRows = planWeekCopyRows(source.weeks, newPlanId);
	const { data: weekRes, error: weekErr } = await supabase
		.from('plan_weeks')
		.insert(weekRows)
		.select('id, week_index');
	if (weekErr || !weekRes) throw weekErr ? dbError(weekErr) : new Error('Weeks insert failed');

	const byIdx = new Map<number, string>();
	for (const w of weekRes as { id: string; week_index: number }[]) {
		byIdx.set(w.week_index, w.id);
	}
	const oldToNew = new Map<string, string>();
	for (const old of source.weeks) {
		const newId = byIdx.get(old.week_index);
		if (newId) oldToNew.set(old.id, newId);
	}

	const workoutRows = planWorkoutCopyRows(source.workouts, oldToNew);
	if (workoutRows.length > 0) {
		const { error: woErr } = await supabase.from('plan_workouts').insert(workoutRows);
		if (woErr) throw dbError(woErr);
	}

	return newPlanId;
}

export async function fetchPlan(id: string): Promise<{
	plan: TrainingPlan | null;
	weeks: PlanWeek[];
	workouts: PlanWorkout[];
	error: string | null;
}> {
	// One round trip: the embed needs no `in (...)` list of week ids, so no
	// chunking either. Ordered here because an embed's order is per parent.
	const { data, error } = await supabase
		.from('training_plans')
		.select('*, plan_weeks(*, plan_workouts(*))')
		.eq('id', id)
		.maybeSingle();
	// Surface a query error so the detail page can show a "couldn't load —
	// retry" state instead of the not-found page (a real error otherwise
	// reads as a missing plan when the row just comes back null).
	if (!data) return { plan: null, weeks: [], workouts: [], error: error?.message ?? null };
	const { plan_weeks: weekRows, ...plan } = data;
	const weeks: PlanWeek[] = [];
	const workouts: PlanWorkout[] = [];
	for (const { plan_workouts: woRows, ...week } of weekRows ?? []) {
		weeks.push(week as PlanWeek);
		workouts.push(...((woRows ?? []) as PlanWorkout[]));
	}
	weeks.sort((a, b) => a.week_index - b.week_index);
	workouts.sort((a, b) =>
		a.scheduled_date < b.scheduled_date ? -1 : a.scheduled_date > b.scheduled_date ? 1 : 0
	);
	return { plan: plan as TrainingPlan, weeks, workouts, error: null };
}

export async function fetchWorkout(
	id: string
): Promise<{ workout: PlanWorkout | null; error: string | null }> {
	// Thread the query error so the detail page can show a "couldn't load —
	// retry" state instead of the not-found page (a transient error otherwise
	// reads as a deleted workout when the row just comes back null), mirroring
	// fetchPlan above.
	const { data, error } = await supabase
		.from('plan_workouts')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	return { workout: (data as PlanWorkout | null) ?? null, error: error?.message ?? null };
}

/// Distances of the runs linked to plan workouts, by run id, for the
/// "Done · +3 km" status. Ids the caller cannot read (a coach looking at an
/// athlete's plan, a deleted run) are simply absent.
export async function fetchRunDistances(ids: readonly string[]): Promise<Map<string, number>> {
	const wanted = [...new Set(ids)];
	const rows = await readChunked(wanted, async (part) => {
		const { data, error } = await supabase.from(TABLES.runs).select('id, distance_m').in('id', part);
		if (error) throw dbError(error);
		return data ?? [];
	});
	const out = new Map<string, number>();
	for (const r of rows) if (r.distance_m != null) out.set(r.id, r.distance_m);
	return out;
}

/// The runs and records the end-of-plan recap (`assemblePlanRecap`) reads,
/// each dated on the runner's local day. Runs reach two days past either end
/// of the plan, the run-to-workout matcher's cross-day reach (decisions
/// § 2079), so a linked run on the window's edge is still found by id.
export async function fetchPlanRecapSources(
	startIso: string,
	endIso: string,
): Promise<{ runs: PlanRecapRun[]; records: PlanRecapRecord[] }> {
	const userId = auth.user?.id;
	if (!userId) return { runs: [], records: [] };
	// Imported here, not at the top: a static import pulls the whole plan
	// generator into this module's chunk, which nearly every route loads.
	const { formatISO, parseISO } = await import('../training/training');
	const [runs, recordsRes] = await Promise.all([
		fetchRuns({
			columns: ['id', 'started_at', 'distance_m', 'duration_s', 'activity_type', 'is_dnf'] as const,
			startedAtFrom: parseISO(shiftIsoDate(startIso, -2)).toISOString(),
			startedAtBefore: parseISO(shiftIsoDate(endIso, 3)).toISOString(),
			throwOnError: true,
		}),
		supabase
			.from(TABLES.personal_records)
			.select('distance, best_time_s, achieved_at, run_id')
			.eq('user_id', userId),
	]);
	if (recordsRes.error) throw dbError(recordsRes.error);
	return {
		runs: runs.map((r) => ({
			id: r.id,
			date: formatISO(new Date(r.started_at)),
			distanceM: r.distance_m,
			durationS: r.duration_s,
			activityType: r.activity_type,
			isDnf: r.is_dnf,
		})),
		records: (recordsRes.data ?? []).map((r) => ({
			distance: r.distance,
			timeS: r.best_time_s,
			date: formatISO(new Date(r.achieved_at)),
			runId: r.run_id,
		})),
	};
}

/// Who owns a plan, for the "updated by your coach" line on a workout
/// (`isEditedByCoach`). Null when the row can't be read; the line then stays
/// hidden rather than guessing.
export async function fetchPlanOwnerId(planId: string): Promise<string | null> {
	const { data, error } = await supabase
		.from('training_plans')
		.select('user_id')
		.eq('id', planId)
		.maybeSingle();
	if (error) return null;
	return data?.user_id ?? null;
}

/// A plan overview read. `error` is set when a read failed, so a caller can
/// say "couldn't load your plan" instead of showing the no-plan state over a
/// plan that exists.
export type PlanOverviewRead = {
	overview: ActivePlanOverview | null;
	error: string | null;
	/// The runner's most recently paused plan, read only when there is no
	/// active one to show, so Home can offer to resume it instead of acting
	/// as though they have no plan.
	paused?: Pick<TrainingPlan, 'id' | 'name'> | null;
};

export async function fetchActivePlanOverview(): Promise<PlanOverviewRead> {
	const userId = auth.user?.id;
	if (!userId) return { overview: null, error: null };
	const read = await planOverviewFor(userId);
	if (read.overview || read.error) return read;
	const { data, error } = await supabase
		.from('training_plans')
		.select('id, name')
		.eq('user_id', userId)
		.eq('status', 'paused')
		.eq('is_template', false)
		.order('paused_at', { ascending: false, nullsFirst: false })
		.limit(1)
		.maybeSingle();
	// A failed read of the paused plan is not a failed plan load: the
	// dashboard falls back to the no-plan card, as it did before.
	if (error) console.error('Reading the paused plan failed', { message: error.message });
	return { ...read, paused: data ?? null };
}

/// The overview of `userId`'s current plan (plan_current.ts), or of the next
/// one to start when nothing is current, so a runner whose only plan is queued
/// sees it counting down rather than an empty card. `upcoming` is the plan
/// after the one shown.
async function planOverviewFor(userId: string): Promise<PlanOverviewRead> {
	const { data: rows, error: rowsErr } = await supabase
		.from('training_plans')
		.select('*')
		.eq('user_id', userId)
		.eq('status', 'active')
		.eq('is_template', false);
	if (rowsErr) return { overview: null, error: rowsErr.message };
	const active = (rows ?? []) as TrainingPlan[];
	if (active.length === 0) return { overview: null, error: null };
	// Local-tz today — `toISOString().slice(0,10)` returns the UTC date,
	// which rolls a calendar day early/late depending on the viewer's TZ.
	const { todayISO } = await import('../training/training');
	const { pickCurrentPlan } = await import('../training/plan_current');
	const { planWorkoutProgress } = await import('../training/plan_progress');
	const today = todayISO();
	const picked = pickCurrentPlan(active, today);
	const plan = picked.current ?? picked.upcoming;
	if (!plan) return { overview: null, error: null };
	const next = active
		.filter((p) => p.start_date > plan.end_date)
		.reduce<TrainingPlan | null>((a, p) => (!a || p.start_date < a.start_date ? p : a), null);
	const { weeks, workouts, error: planErr } = await fetchPlan(plan.id);
	if (planErr) return { overview: null, error: planErr };
	const todayWorkout = workouts.find((w) => w.scheduled_date === today) ?? null;
	const completionPct = planWorkoutProgress(workouts).pct;
	return {
		overview: {
			plan,
			weeks: weeks ?? [],
			workouts: workouts ?? [],
			todayWorkout,
			completionPct,
			upcoming: next
				? { id: next.id, name: next.name, start_date: next.start_date, end_date: next.end_date }
				: null,
			activePlans: active.map((p) => ({ id: p.id, name: p.name, start_date: p.start_date, end_date: p.end_date }))
		},
		error: null
	};
}

/// What creating or cloning a plan does to the active plans its window
/// overlaps: 'refuse' (fail with a PlanOverlapError, the default, so nothing
/// the runner did not name is changed), 'replace' (abandon them) or 'trim'
/// (end each the day before the new plan starts). Decisions § 2050.
export type PlanOverlapChoice = 'refuse' | 'replace' | 'trim';

/**
 * Persist a freshly generated plan — plan row, weeks and workouts — through
 * `create_training_plan`, which resolves overlapping active plans per
 * `overlap` and writes everything in one transaction (decisions § 2050).
 */
export async function createTrainingPlan(input: {
	name: string;
	goalEvent: GoalEvent;
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	startDate: string; // ISO date
	daysPerWeek: number;
	notes?: string;
	generated: GeneratedPlan;
	/// The race listing the plan is built for. The RPC writes null for an id
	/// that names no listing rather than refusing the plan.
	raceListingId?: string | null;
	overlap?: PlanOverlapChoice;
}): Promise<TrainingPlan> {
	// Read the id from the session directly rather than from the auth store.
	// The store's `user` object is populated by a background profile fetch
	// which races with "Create plan" — using the session avoids the
	// spurious "Not authenticated" when the session is valid but the profile
	// hasn't loaded.
	const { data: { session } } = await supabase.auth.getSession();
	const userId = session?.user?.id;
	if (!userId) throw new Error('Please sign in to create a plan.');

	// Pre-flight validation — the RPC enforces the same rules, but a
	// readable message here beats a raw 22023 / 23xxx code.
	if (!input.name.trim()) throw new Error('Name is required.');
	if (!(input.goalDistanceM > 0)) throw new Error('Goal distance must be positive.');
	// Imported here, not at the top: a static import pulls the whole plan
	// generator into this module's chunk, which nearly every route loads.
	const { minDaysPerWeek } = await import('../training/training');
	const minDays = minDaysPerWeek(input.generated.weeks);
	if (input.daysPerWeek < minDays || input.daysPerWeek > 7) {
		throw new Error(`Days per week must be between ${minDays} and 7.`);
	}
	if (input.goalTimeSec != null && input.goalTimeSec <= 0) {
		throw new Error('Goal time must be positive.');
	}
	if (input.recent5kSec != null && input.recent5kSec <= 0) {
		throw new Error('Recent 5K time must be positive.');
	}
	if (!input.generated.weeks.length) {
		throw new Error('Generated plan has no weeks.');
	}
	// Defence in depth for the null-kind bug we fixed in training.ts —
	// if some future change lets a kindless workout escape the generator,
	// catch it here instead of losing the context in a server-side error.
	for (const w of input.generated.weeks) {
		for (const wo of w.workouts) {
			if (!wo.kind) {
				throw new Error(
					`Generator produced a workout with no kind (week ${w.week_index}, ${wo.scheduled_date}).`
				);
			}
		}
	}

	markListsStale('plans');
	const { data: planId, error } = await supabase.rpc('create_training_plan', {
		p_plan: {
			name: input.name.trim(),
			goal_event: input.goalEvent,
			goal_distance_m: input.goalDistanceM,
			goal_time_seconds: input.goalTimeSec ?? null,
			start_date: input.startDate,
			end_date: input.generated.endDate,
			days_per_week: input.daysPerWeek,
			vdot: input.generated.vdot ?? null,
			current_5k_seconds: input.recent5kSec ?? null,
			notes: input.notes?.trim() || null,
			race_listing_id: input.raceListingId ?? null
		},
		p_weeks: input.generated.weeks.map((w) => ({
			week_index: w.week_index,
			phase: w.phase,
			target_volume_m: w.target_volume_m,
			notes: w.notes ?? null,
			workouts: w.workouts.map((wo) => ({
				scheduled_date: wo.scheduled_date,
				kind: wo.kind,
				target_distance_m: wo.target_distance_m ?? null,
				target_duration_seconds: wo.target_duration_seconds ?? null,
				target_pace_sec_per_km: wo.target_pace_sec_per_km ?? null,
				target_pace_tolerance_sec: wo.target_pace_tolerance_sec ?? null,
				structure: (wo.structure ?? null) as unknown as Json,
				notes: wo.notes ?? null,
				race_name: wo.kind === 'race' ? wo.race_name?.trim() || null : null,
				race_priority: wo.kind === 'race' ? (wo.race_priority ?? null) : null,
				race_taper_applied_at: wo.race_taper_applied_at ?? null
			}))
		})),
		p_overlap: input.overlap ?? 'refuse'
	});
	if (error) throw dbError(error);

	const { data: plan, error: readErr } = await supabase
		.from('training_plans')
		.select('*')
		.eq('id', planId)
		.single();
	if (readErr || !plan) throw readErr ? dbError(readErr) : new Error('Plan read failed');
	return plan as TrainingPlan;
}

export async function updatePlanStatus(
	id: string,
	status: PlanStatus
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase
		.from('training_plans')
		.update({ status })
		.eq('id', id);
	if (error) throw dbError(error);
}

export async function deletePlan(id: string): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.from('training_plans').delete().eq('id', id);
	if (error) throw dbError(error);
}

/// Pause an active plan — a first-class, reversible primitive distinct from
/// abandon/complete (persona runner-woman, decisions §231). Sets status
/// 'paused', which frees the one-active slot so the runner can resume later.
export async function pausePlan(id: string): Promise<void> {
	await updatePlanStatus(id, 'paused');
}

/// File an active plan whose dates have run out under Completed (the "Finish
/// plan" prompt, `isPlanFinished`). Scoped to `status = 'active'` so a plan
/// paused or abandoned in another tab is never relabelled as finished.
export async function finishPlan(id: string): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase
		.from('training_plans')
		.update({ status: 'completed' })
		.eq('id', id)
		.eq('status', 'active');
	if (error) throw dbError(error);
}

/// Thrown by resumePlan when another active plan overlaps the paused plan's
/// window — `training_plans_active_no_overlap` would reject the resume, so we
/// refuse up front with a clear signal the UI can translate rather than
/// silently completing the other plan.
export class ActivePlanExistsError extends Error {
	constructor() {
		super('active_plan_exists');
		this.name = 'ActivePlanExistsError';
	}
}

/// The signed-in user's active plans a new plan over [startIso, endIso] would
/// collide with — what the plan creator names before offering replace / trim.
/// Session-read for the same reason createTrainingPlan is.
export async function fetchMyOverlappingActivePlans(
	startIso: string,
	endIso: string
): Promise<Pick<TrainingPlan, 'id' | 'name' | 'start_date' | 'end_date'>[]> {
	const { data: { session } } = await supabase.auth.getSession();
	const userId = session?.user?.id;
	if (!userId) return [];
	return fetchOverlappingActivePlans(userId, startIso, endIso);
}

/// The user's active plans whose inclusive window shares a day with
/// [startIso, endIso]. No template filter is needed: a template can never be
/// active (training_plans_template_status).
async function fetchOverlappingActivePlans(
	userId: string,
	startIso: string,
	endIso: string
): Promise<Pick<TrainingPlan, 'id' | 'name' | 'start_date' | 'end_date'>[]> {
	const { data, error } = await supabase
		.from('training_plans')
		.select('id, name, start_date, end_date')
		.eq('user_id', userId)
		.eq('status', 'active')
		.lte('start_date', endIso)
		.gte('end_date', startIso)
		.order('start_date', { ascending: true });
	if (error) throw dbError(error);
	return data ?? [];
}

/// Resume a paused plan back to 'active'. Refuses (throws
/// ActivePlanExistsError) when another active plan overlaps its window; a
/// plan queued before or after it does not block. Non-destructive by design.
/// Resume a paused plan through `resume_training_plan`, pushing the weeks
/// `shift` names back when the runner's pause spanned whole weeks
/// (`resumeShift`), so they come back as upcoming rather than missed. The
/// overlap pre-check covers the end date the shift will give the plan.
export async function resumePlan(
	id: string,
	userId: string,
	shift: ResumeShift | null = null
): Promise<void> {
	const { data: plan, error: planErr } = await supabase
		.from('training_plans')
		.select('start_date, end_date')
		.eq('id', id)
		.maybeSingle();
	if (planErr) throw dbError(planErr);
	if (!plan) throw new Error('Plan not found.');
	const endDate = shift ? shiftIsoDate(plan.end_date, 7 * shift.weeks) : plan.end_date;
	const others = (await fetchOverlappingActivePlans(userId, plan.start_date, endDate)).filter(
		(p) => p.id !== id
	);
	if (others.length > 0) throw new ActivePlanExistsError();
	markListsStale('plans');
	const { error } = await supabase.rpc('resume_training_plan', {
		p_plan_id: id,
		p_from_week_index: shift?.fromWeekIndex ?? null,
		p_shift_weeks: shift?.weeks ?? 0
	});
	if (error) throw dbError(error);
}

/// The signed-in user's active plans, for checking a date shift against the
/// plans around it (plan_shift.ts) before it runs.
export async function fetchMyActivePlanWindows(): Promise<
	Pick<TrainingPlan, 'id' | 'name' | 'start_date' | 'end_date'>[]
> {
	const { data: { session } } = await supabase.auth.getSession();
	const userId = session?.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from('training_plans')
		.select('id, name, start_date, end_date')
		.eq('user_id', userId)
		.eq('status', 'active')
		.order('start_date', { ascending: true });
	if (error) throw dbError(error);
	return data ?? [];
}

/// Move a plan's workouts and dates by `days` in one transaction
/// (shift_training_plan). With `shiftFollowing`, the active plans queued after
/// it move by the same days. A shift that would overlap another active plan
/// fails whole with a PlanOverlapError and nothing moves.
export async function shiftTrainingPlan(
	planId: string,
	days: number,
	shiftFollowing: boolean
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.rpc('shift_training_plan', {
		p_plan_id: planId,
		p_days: days,
		p_shift_following: shiftFollowing
	});
	if (error) throw dbError(error);
}

/// Re-anchor a plan on a new race date (`raceDateChange` picks the weeks;
/// `change_plan_race_date` applies them in one transaction).
export async function changePlanRaceDate(
	planId: string,
	change: RaceDateChange,
	todayIso: string
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.rpc('change_plan_race_date', {
		p_plan_id: planId,
		p_race_date: change.raceDateIso,
		p_today: todayIso,
		p_drop_week_ids: change.dropWeekIds,
		p_insert_at: change.insertAt,
		p_insert_count: change.insertCount,
		p_repeat_week_id: change.repeatWeekId,
		p_race_workout_id: change.raceWorkoutId
	});
	if (error) throw dbError(error);
}

/// Runs the latest weeks again after a break and records the offer as
/// answered (`planBreakChange`, decisions § 2128), in one transaction.
export async function reschedulePlanAfterBreak(
	planId: string,
	change: BreakChange,
	breakFromIso: string,
	todayIso: string
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.rpc('reschedule_plan_after_break', {
		p_plan_id: planId,
		p_today: todayIso,
		p_break_from: breakFromIso,
		p_repeat_week_ids: change.repeatWeekIds,
		p_drop_week_ids: change.dropWeekIds
	});
	if (error) throw dbError(error);
}

/// "Too hard? Repeat this week": runs the week again next week and pushes the
/// rest back one, keeping race day by dropping `change.dropWeekId`
/// (`repeatWeekChange`), in one transaction.
export async function repeatPlanWeek(
	planId: string,
	change: RepeatWeekChange,
	todayIso: string
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.rpc('repeat_plan_week', {
		p_plan_id: planId,
		p_today: todayIso,
		p_week_id: change.weekId,
		p_drop_week_id: change.dropWeekId
	});
	if (error) throw dbError(error);
}

export async function markWorkoutCompleted(
	workoutId: string,
	runId: string | null,
	options: { manual?: boolean } = {}
): Promise<void> {
	const manual = options.manual === true;
	const isCompleting = runId != null || manual;
	const { error } = await supabase
		.from('plan_workouts')
		.update({
			completed_run_id: runId,
			manually_completed: manual,
			completed_at: isCompleting ? new Date().toISOString() : null,
			// Completing clears any prior skip — the two states are mutually
			// exclusive. Un-completing (runId null + manual false) leaves the
			// skip flag untouched so it isn't a back-door un-skip.
			...(isCompleting ? { skipped_at: null } : {})
		})
		.eq('id', workoutId);
	if (error) throw dbError(error);
}

/**
 * Toggle a planned workout's intentionally-skipped state. Marking it
 * skipped stamps `skipped_at` and clears any completion (a row is never
 * both skipped and done); un-skipping clears `skipped_at`. Distinct from
 * `markWorkoutCompleted(id, null)` — that path is "didn't do it / undo a
 * tick", this one is "deliberately dropping this session".
 */
export async function markWorkoutSkipped(
	workoutId: string,
	skipped: boolean
): Promise<void> {
	const { error } = await supabase
		.from('plan_workouts')
		.update(
			skipped
				? {
						skipped_at: new Date().toISOString(),
						completed_run_id: null,
						manually_completed: false,
						completed_at: null
					}
				: { skipped_at: null }
		)
		.eq('id', workoutId);
	if (error) throw dbError(error);
}

export type PlanWorkoutLinkCandidate =
	Database['public']['Functions']['plan_workout_link_candidates']['Returns'][number];

/**
 * Planned workouts within two days of a run that it could have been, for the
 * run-detail "did you do Thursday's workout early?" prompt. The database
 * links a run on its own local day only (decisions § 2079); this list is
 * never linked without the runner saying yes. Empty unless the caller owns
 * the run and it is not linked yet. Nearest day first.
 */
export async function fetchPlanWorkoutLinkCandidates(
	runId: string
): Promise<PlanWorkoutLinkCandidate[]> {
	const { data, error } = await supabase.rpc(
		'plan_workout_link_candidates',
		{ p_run_id: runId },
		{ get: true }
	);
	if (error) throw dbError(error);
	return data ?? [];
}

/** "Not this one" on that prompt: the pair is never offered again. */
export async function dismissPlanWorkoutLink(workoutId: string, runId: string): Promise<void> {
	const { error } = await supabase.rpc('dismiss_plan_workout_link', {
		p_workout_id: workoutId,
		p_run_id: runId
	});
	if (error) throw dbError(error);
}

export type { RelinkCandidateRun } from '../training/relink_candidates';

/**
 * Candidate runs the owner can re-link to a planned workout.
 *
 * Owner-scoped (RLS + an explicit `user_id` filter), within ±7 days of
 * the workout's `scheduled_date`, and — crucially — EXCLUDING any run
 * already linked (`completed_run_id`) to a *different* plan workout, so
 * re-linking can't double-count a single run across two workouts in
 * `plan_progress`. The workout's own current run stays in the list so
 * the current pick is visible. Newest-first.
 */
export async function fetchRelinkCandidateRuns(
	workout: PlanWorkout
): Promise<RelinkCandidateRun[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	// The set of run ids already linked anywhere in this owner's plans.
	// Scope through the owner's plan_weeks (RLS chains the same way, but
	// the explicit scope is defence in depth: a future RLS edit that broke
	// the chain must not widen it). A run linked to ANOTHER workout must not
	// be offered.
	const { data: plans } = await supabase
		.from('training_plans')
		.select('id, plan_weeks(id)')
		.eq('user_id', userId);
	const weekIds = (plans ?? []).flatMap((p) =>
		((p as { plan_weeks: { id: string }[] }).plan_weeks ?? []).map((w) => w.id)
	);
	const linkedRunIds: string[] = [];
	if (weekIds.length > 0) {
		const { data: linkedRows } = await queryChunked(weekIds, (part) =>
			supabase
				.from('plan_workouts')
				.select('completed_run_id')
				.in('week_id', part)
				.not('completed_run_id', 'is', null)
		);
		for (const row of linkedRows ?? []) {
			const id = (row as { completed_run_id: string | null }).completed_run_id;
			if (id) linkedRunIds.push(id);
		}
	}

	// Owner's runs, explicitly scoped (RLS + user_id), scalars only — bounded
	// to a date window around the workout instead of the whole run history.
	// filterRelinkCandidates keeps only runs within ±DEFAULT_RELINK_WINDOW_DAYS
	// calendar days of scheduled_date (plus the current pick regardless), so a
	// generous ±(window+2)-day UTC pre-filter — wide enough to cover ±window
	// LOCAL calendar days across any timezone — returns a handful of rows
	// instead of every run a heavy-history user ever logged. The current
	// completed_run_id is OR-ed in so a re-link pick outside the window still
	// surfaces (filterRelinkCandidates always keeps it). Backed by the
	// (user_id, started_at desc) index.
	const currentRunId = workout.completed_run_id ?? null;
	const schedMs = Date.parse(`${workout.scheduled_date}T00:00:00Z`);
	const bufferMs = (DEFAULT_RELINK_WINDOW_DAYS + 2) * 86_400_000;
	const loIso = new Date(schedMs - bufferMs).toISOString();
	const hiIso = new Date(schedMs + bufferMs).toISOString();
	let runQuery = supabase
		.from(TABLES.runs)
		.select('id, started_at, distance_m, duration_s')
		.eq('user_id', userId);
	runQuery = currentRunId
		? runQuery.or(
				`and(started_at.gte.${loIso},started_at.lte.${hiIso}),id.eq.${currentRunId}`
			)
		: runQuery.gte('started_at', loIso).lte('started_at', hiIso);
	const { data: runRows } = await runQuery.order('started_at', { ascending: false });

	const runs: RelinkCandidateRun[] = (runRows ?? []).map((r) => ({
		id: (r as { id: string }).id,
		started_at: (r as { started_at: string }).started_at,
		distance_m: (r as { distance_m: number }).distance_m,
		duration_s: (r as { duration_s: number }).duration_s
	}));

	return filterRelinkCandidates({
		runs,
		linkedRunIds,
		currentRunId,
		scheduledDate: workout.scheduled_date
	});
}

/**
 * Patch a single plan workout — supports the inline editor. Only the
 * provided fields are updated; leave others out of the `patch` map to keep
 * them untouched.
 */
export async function updatePlanWorkout(
	id: string,
	patch: Partial<{
		kind: string;
		target_distance_m: number | null;
		target_duration_seconds: number | null;
		target_pace_sec_per_km: number | null;
		target_pace_end_sec_per_km: number | null;
		target_pace_tolerance_sec: number | null;
		pace_zone: string | null;
		notes: string | null;
		scheduled_date: string;
		structure: JsonObject | null;
		race_name: string | null;
		race_priority: RacePriority | null;
		target_rpe_min: number | null;
		target_rpe_max: number | null;
		target_hr_min_bpm: number | null;
		target_hr_max_bpm: number | null;
	}>
): Promise<void> {
	// Normalise the `notes` patch the same way `createTrainingPlan`
	// does on insert — trim + collapse empty-after-trim to null.
	// Mobile's `TrainingService.updateWorkout` applies the same
	// normalisation so the two clients write identical rows. Logic
	// lives in data_normalise.ts so the contract can be unit-tested.
	const normalisedPatch: typeof patch = { ...patch };
	if ('notes' in normalisedPatch) {
		normalisedPatch.notes = normalisePlanWorkoutNotes(normalisedPatch.notes);
	}
	// `kind` stays a `string` on the parameter because two of the three callers
	// are TS<->Dart parity modules (`plan_replan`, `cycle_plan`) whose patch
	// types spell it that way; the column's CHECK is what constrains it.
	// Restated field-by-field rather than casting the whole patch, so the other
	// fields stay checked against the table they are sent to.
	if ('race_name' in normalisedPatch) {
		normalisedPatch.race_name = normalisedPatch.race_name?.trim() || null;
	}
	const { kind, ...fields } = normalisedPatch;
	const update: Updatable<'plan_workouts'> = fields;
	if (kind !== undefined) update.kind = kind as Updatable<'plan_workouts'>['kind'];
	// The race columns are only legal on a race (plan_workouts_race_fields_only_on_race),
	// so moving a workout to any other kind clears them in the same write.
	if (kind !== undefined && kind !== 'race') {
		update.race_name = null;
		update.race_priority = null;
	}
	const { error } = await supabase.from('plan_workouts').update(update).eq('id', id);
	if (error) throw dbError(error);
}

/// Move one planned workout to another day of its week (`move_plan_workout`,
/// decisions § 2073). When the day already holds a row, the two trade days;
/// the swapped workout's id is returned, or null when the day was free.
export async function movePlanWorkout(workoutId: string, date: string): Promise<string | null> {
	const { data, error } = await supabase.rpc('move_plan_workout', {
		p_workout_id: workoutId,
		p_date: date
	});
	if (error) throw dbError(error);
	return data ?? null;
}

/// Set the dates of several workouts of one plan in one transaction
/// (`reschedule_plan_workouts`, decisions § 2073), so moves and swaps that
/// pass through each other's days land together or not at all.
export async function reschedulePlanWorkouts(
	planId: string,
	moves: { id: string; date: string }[]
): Promise<void> {
	if (moves.length === 0) return;
	const { error } = await supabase.rpc('reschedule_plan_workouts', {
		p_plan_id: planId,
		p_moves: moves
	});
	if (error) throw dbError(error);
}

/// One workout's patch for `applyWorkoutAdjustments`. A key present is
/// written (null clears the column); a key absent leaves it alone.
export type WorkoutAdjustment = { id: string } & Partial<{
	kind: string;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	target_pace_sec_per_km: number | null;
	target_pace_tolerance_sec: number | null;
	pace_zone: string | null;
	structure: JsonObject | null;
	notes: string | null;
	race_name: string | null;
	race_priority: RacePriority | null;
	race_taper_applied_at: string | null;
}>;

/// Write a batch of workout patches to one plan and restate the volume of
/// every week they touch, all in one transaction (`apply_workout_adjustments`,
/// decisions § 2062): either every workout changes or none does. The patches
/// are normalised as `updatePlanWorkout` normalises one.
export async function applyWorkoutAdjustments(
	planId: string,
	changes: WorkoutAdjustment[]
): Promise<void> {
	const normalised = changes.map((c) => {
		const out: WorkoutAdjustment = { ...c };
		if ('notes' in out) out.notes = normalisePlanWorkoutNotes(out.notes);
		if ('race_name' in out) out.race_name = out.race_name?.trim() || null;
		if (out.kind !== undefined && out.kind !== 'race') {
			out.race_name = null;
			out.race_priority = null;
		}
		return out;
	});
	const { error } = await supabase.rpc('apply_workout_adjustments', {
		p_plan_id: planId,
		p_changes: normalised
	});
	if (error) throw dbError(error);
}

/// Record the runner's answer to the missed-workout prompt on each named
/// workout (`answer_missed_workouts`, decisions § 2122), so it is never asked
/// again on any device. "Make it up" passes the previewed make-up as
/// `changes`; it is written in the same transaction as the answer, so the two
/// land together or not at all.
export async function answerMissedWorkouts(
	planId: string,
	workoutIds: string[],
	changes: WorkoutAdjustment[] = []
): Promise<void> {
	const { error } = await supabase.rpc('answer_missed_workouts', {
		p_plan_id: planId,
		p_workout_ids: workoutIds,
		p_changes: changes
	});
	if (error) throw dbError(error);
}

export async function updatePlanWeek(
	id: string,
	patch: Partial<{ phase: PlanPhase; target_volume_m: number | null; notes: string | null }>
): Promise<void> {
	const { error } = await supabase.from('plan_weeks').update(patch).eq('id', id);
	if (error) throw dbError(error);
}

export async function updatePlanMeta(
	id: string,
	patch: Partial<{
		name: string;
		notes: string | null;
		goal_time_seconds: number | null;
		days_per_week: number;
		rules: Json[] | null;
		start_date: string;
		end_date: string;
	}>
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.from('training_plans').update(patch).eq('id', id);
	if (error) throw dbError(error);
}

/// Restart one of the runner's plans as a fresh active copy starting on
/// `startIso` (`restart_training_plan`). The overlapped active plans and the
/// source, while live, are retired as abandoned in the same transaction; the
/// source keeps its history. Returns the new plan's id.
export async function restartTrainingPlan(planId: string, startIso: string): Promise<string> {
	markListsStale('plans');
	const { data, error } = await supabase.rpc('restart_training_plan', {
		p_plan_id: planId,
		p_start_date: startIso
	});
	if (error) {
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data;
}

/// Set a plan's goal time with the re-derived workout paces
/// (`goalTimeRepacePatches`) and VDOT in one transaction
/// (`set_plan_goal_time`), so the goal and the paces never disagree.
export async function setPlanGoalTime(
	planId: string,
	goalTimeSec: number | null,
	vdot: number | null,
	changes: RepacePatch[]
): Promise<void> {
	markListsStale('plans');
	const { error } = await supabase.rpc('set_plan_goal_time', {
		p_plan_id: planId,
		p_goal_time_seconds: goalTimeSec,
		p_vdot: vdot,
		p_changes: changes as unknown as Json
	});
	if (error) throw dbError(error);
}

/// Duplicate the plan week at `weekIndex`, inserting the copy right after
/// it. Every later week shifts up one index (+7 days), the copy lands 7
/// days after its source, and the plan end_date extends a week. Atomic
/// server-side because the (plan_id, week_index) unique constraint makes
/// a client-side multi-update unsafe — see the duplicate_plan_week RPC.
/// Returns the new week's id.
export async function duplicatePlanWeek(planId: string, weekIndex: number): Promise<string> {
	const { data, error } = await supabase.rpc('duplicate_plan_week', {
		p_plan_id: planId,
		p_week_index: weekIndex
	});
	if (error) throw dbError(error);
	return data as string;
}

// ─────────────────────── Following + activity feed (decisions §31) ───────────────────────

export interface PublicProfile {
	id: string;
	display_name: string | null;
	avatar_url: string | null;
}

export interface ProfileSummary extends PublicProfile {
	follower_count: number;
	following_count: number;
	viewer_follows: boolean;
	/// The owner made the profile private (decisions § 1967): follows become
	/// requests and the runs / follower lists open only to approved followers.
	profile_private: boolean;
	/// The viewer has a pending request to follow this profile.
	viewer_requested: boolean;
	/// Whether the viewer may read the profile's activity and lists — the
	/// owner, anyone for a public profile, an approved follower for a private one.
	content_visible: boolean;
}

/// User profile lookup. The counts and the viewer's own follow / request
/// state come from `profile_follow_summary`, because on a private profile the
/// follow rows behind the counts are closed to a viewer who is not an
/// approved follower. Returns null when the user doesn't exist, is hidden, or
/// a block stands between the two.
export async function fetchPublicProfile(
	userId: string
): Promise<{ profile: ProfileSummary | null; error: string | null }> {
	const [profileRes, summaryRes] = await Promise.all([
		supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.eq('id', userId)
			.maybeSingle(),
		supabase.rpc('profile_follow_summary', { p_user_id: userId }, { get: true }).maybeSingle(),
	]);

	// Surface a query error so the profile page can show a "couldn't load —
	// retry" state instead of the not-found page (a real error otherwise
	// reads as a missing user when the row just comes back null).
	const error =
		(profileRes as { error?: { message?: string } | null }).error?.message ??
		(summaryRes as { error?: { message?: string } | null }).error?.message ??
		null;
	if (!profileRes.data || !summaryRes.data) return { profile: null, error };
	const summary = summaryRes.data;

	return {
		profile: {
			id: profileRes.data.id,
			display_name: profileRes.data.display_name,
			avatar_url: profileRes.data.avatar_url,
			follower_count: Number(summary.follower_count) || 0,
			following_count: Number(summary.following_count) || 0,
			viewer_follows: summary.viewer_follows === true,
			profile_private: summary.profile_private === true,
			viewer_requested: summary.viewer_requested === true,
			content_visible: summary.content_visible === true,
		},
		error: null
	};
}

/// What a follow tap did: followed a public profile at once, or filed a
/// request with a private one.
export type FollowOutcome = 'following' | 'requested';

/// Follow `targetUserId`, or ask to when their profile is private. One RPC so
/// the client never has to read the target's privacy and race its change; the
/// server writes through the same RLS a direct insert would hit.
export async function followUser(targetUserId: string): Promise<FollowOutcome> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	if (userId === targetUserId) throw new Error("Can't follow yourself");
	const { data, error } = await supabase.rpc('request_follow', { p_target: targetUserId });
	if (error) throw dbError(error);
	return data === 'requested' ? 'requested' : 'following';
}

/// Withdraw the viewer's pending request to follow `targetUserId`.
export async function cancelFollowRequest(targetUserId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.follow_requests)
		.delete()
		.eq('requester_id', userId)
		.eq('target_id', targetUserId);
	if (error) throw dbError(error);
}

export interface IncomingFollowRequest extends PublicProfile {
	requested_at: string;
}

/// Requests to follow the signed-in user, newest first.
export async function fetchIncomingFollowRequests(): Promise<IncomingFollowRequest[]> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from(TABLES.follow_requests)
		.select('requester_id, requested_at')
		.eq('target_id', userId)
		.order('requested_at', { ascending: false })
		.order('requester_id', { ascending: false })
		.limit(200);
	if (error) throw dbError(error);
	const rows = data ?? [];
	const profiles = await profilesInEdgeOrder(rows.map((r) => r.requester_id));
	const at = new Map(rows.map((r) => [r.requester_id, r.requested_at]));
	return profiles.map((p) => ({ ...p, requested_at: at.get(p.id) ?? '' }));
}

export async function approveFollowRequest(requesterId: string): Promise<void> {
	const { error } = await supabase.rpc('approve_follow_request', { p_requester: requesterId });
	if (error) throw dbError(error);
}

export async function declineFollowRequest(requesterId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.follow_requests)
		.delete()
		.eq('requester_id', requesterId)
		.eq('target_id', userId);
	if (error) throw dbError(error);
}

/// The signed-in user's own private-profile switch.
export async function fetchMyProfilePrivate(): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return false;
	const { data, error } = await supabase
		.from('user_profiles')
		.select('profile_private')
		.eq('id', userId)
		.maybeSingle();
	if (error) throw dbError(error);
	return data?.profile_private === true;
}

/// Turning it off approves every pending request (a trigger does it in the
/// same statement), so nobody is left asking a profile that no longer asks.
export async function setProfilePrivate(next: boolean): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('user_profiles')
		.update({ profile_private: next })
		.eq('id', userId);
	if (error) throw dbError(error);
}

export async function unfollowUser(targetUserId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from('user_follows')
		.delete()
		.eq('follower_id', userId)
		.eq('followee_id', targetUserId);
	if (error) throw dbError(error);
}

/// Block `targetUserId` — see migration 20261012_001_user_blocks.sql.
/// `block_user` is SECURITY DEFINER and also drains existing follow
/// rows in either direction, so a viewer-initiated block subsumes
/// unfollow on both sides. Re-calling with a new reason updates the
/// reason in place (the RPC upserts on conflict).
export async function blockUser(targetUserId: string, reason?: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	if (userId === targetUserId) throw new Error("Can't block yourself");
	const { error } = await supabase.rpc('block_user', {
		p_target: targetUserId,
		p_reason: reason ?? null,
	});
	if (error) throw dbError(error);
}

export async function unblockUser(targetUserId: string): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase.rpc('unblock_user', { p_target: targetUserId });
	if (error) throw dbError(error);
}

/// Returns true when the viewer has blocked `targetUserId`. Reads
/// `user_blocks` directly — RLS already gates the read to rows where
/// the viewer is the blocker, so no SECURITY DEFINER needed.
export async function isBlockedByViewer(targetUserId: string): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return false;
	const { data } = await supabase
		.from(TABLES.user_blocks)
		.select('blocker_id')
		.eq('blocker_id', userId)
		.eq('blocked_id', targetUserId)
		.maybeSingle();
	return data != null;
}

export interface PeopleSuggestion extends PublicProfile {
	public_runs_count: number;
	shared_clubs: number;
	viewer_follows: boolean;
	// Public @handle (issue #465). Null until the runner claims one.
	handle: string | null;
}

/// Free-text people search for /social People tab. Used to do a
/// direct ILIKE against `user_profiles`; now routes through the
/// `search_user_profiles` SECURITY DEFINER RPC so it can filter by
/// the `discoverable_in_search` opt-out pref (persona-hunt Round 3
/// finding Woman #2 — a runner who's been stalked needs a way to
/// remove themselves from name search; user_settings has owner-only
/// RLS so the join can't run client-side).
///
/// Excludes self, hydrates viewer→target follow edges + per-result
/// public-runs count so the row's Follow toggle starts in the right
/// state. Results are ranked by `public_runs_count` descending so a
/// bot mass-creating dummy accounts can't push real runners off the
/// top — anti-spam phase 1 of 3 in `docs/architecture/decisions.md § search ranking`.
///
/// `limit` caps the returned list. We fetch `limit * 3` candidates
/// from the RPC (capped server-side at 200) so the rank step has more
/// to chew on; with > N exact-name hits, the cap still defines the
/// visible page and the user can refine the query.
export async function searchPeople(q: string, limit = 20): Promise<PeopleSuggestion[]> {
	const term = q.trim();
	if (term.length < 1) return [];
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id ?? null;

	// Direct-id / profile-URL lookup: a pasted uuid (or `/u/<uuid>` link)
	// resolves that exact runner. Safe — it needs the full uuid, so there's
	// no enumeration surface, and it deliberately bypasses the
	// discoverable_in_search opt-out the same way the public /u/[id] page
	// already does. shadow_hidden + block filters still apply because the
	// resolve goes through the same hydrate path (issue #465).
	const { extractProfileId } = await import('../social/profile_query');
	const directId = extractProfileId(term);
	if (directId) {
		if (directId === viewerId) return [];
		return hydratePeopleSuggestions([directId], viewerId);
	}

	const candidateLimit = Math.min(limit * 3, 120);
	const { data: profiles, error } = await supabase.rpc('search_user_profiles', {
		p_query: term,
		p_limit: candidateLimit,
	}, { get: true });
	if (error || !profiles) return [];
	const ids = (profiles as Array<{ id: string }>)
		.map((p) => p.id)
		.filter((id) => id !== viewerId);
	if (ids.length === 0) return [];
	const hydrated = await hydratePeopleSuggestions(ids, viewerId);
	// Reputation-weighted sort lives in `search_ranking.ts` so the
	// comparator can be unit-tested without booting Supabase. Accounts
	// with 0 public runs aren't hidden (a friend you search for by
	// exact name may not have posted any runs yet), they just rank
	// last within the result set.
	const { comparePeopleRank } = await import('../social/search_ranking');
	const ranked = hydrated.sort(comparePeopleRank);
	// A searched-for exact @handle floats above the reputation sort, so
	// `@janedoe` surfaces janedoe first even if a busier account also
	// prefix-matches the handle (mirrors the RPC's exact-handle-first order,
	// which the reputation re-sort would otherwise mask).
	const handleTerm = term.replace(/^@/, '').toLowerCase();
	if (!handleTerm) return ranked.slice(0, limit);
	const exact = ranked.filter((p) => p.handle?.toLowerCase() === handleTerm);
	if (exact.length === 0) return ranked.slice(0, limit);
	const rest = ranked.filter((p) => p.handle?.toLowerCase() !== handleTerm);
	return [...exact, ...rest].slice(0, limit);
}

/// Suggested people for the Social People tab: members of the viewer's
/// clubs they don't already follow, plus self-exclusion. Ordered by
/// shared-club count desc, then by display_name. Single round-trip via
/// client-composed queries (no SECURITY DEFINER RPC — every table read
/// is covered by existing RLS).
export async function fetchSuggestedPeople(limit = 12): Promise<PeopleSuggestion[]> {
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id ?? null;
	if (!viewerId) return [];

	// Signal 1: co-members of the viewer's clubs, weighted by shared-club count.
	const sharedClubs = new Map<string, number>();
	const { data: myMemberRows } = await supabase
		.from(TABLES.club_members)
		.select('club_id')
		.eq('user_id', viewerId)
		.eq('status', 'active');
	const myClubIds = (myMemberRows ?? []).map((r) => r.club_id as string);
	if (myClubIds.length > 0) {
		const { data: coMemberRows } = await queryChunked(myClubIds, (part) =>
			supabase
				.from(TABLES.club_members)
				.select('user_id, club_id')
				.in('club_id', part)
				.eq('status', 'active')
				.neq('user_id', viewerId)
		);
		for (const row of coMemberRows ?? []) {
			const uid = row.user_id as string;
			sharedClubs.set(uid, (sharedClubs.get(uid) ?? 0) + 1);
		}
	}

	// Signal 2: co-attendees of the local events the viewer is going to — the
	// "runners around you" path that needs NO person-location surface. RLS on
	// event_attendees only exposes co-attendees of events the viewer can see
	// (public-club or member events), so this stays a plain invoker read.
	const sharedEvents = new Map<string, number>();
	const { data: myRsvpRows } = await supabase
		.from(TABLES.event_attendees)
		.select('event_id')
		.eq('user_id', viewerId)
		.eq('status', 'going');
	const myEventIds = (myRsvpRows ?? []).map((r) => r.event_id as string);
	if (myEventIds.length > 0) {
		const { data: coAttendeeRows } = await queryChunked(myEventIds, (part) =>
			supabase
				.from(TABLES.event_attendees)
				.select('user_id, event_id')
				.in('event_id', part)
				.eq('status', 'going')
				.neq('user_id', viewerId)
		);
		for (const row of coAttendeeRows ?? []) {
			const uid = row.user_id as string;
			sharedEvents.set(uid, (sharedEvents.get(uid) ?? 0) + 1);
		}
	}

	const candidateIds = new Set<string>([...sharedClubs.keys(), ...sharedEvents.keys()]);
	if (candidateIds.size === 0) return [];

	const { data: followedRows } = await queryChunked([...candidateIds], (part) =>
		supabase
			.from('user_follows')
			.select('followee_id')
			.eq('follower_id', viewerId)
			.in('followee_id', part)
	);
	for (const r of followedRows ?? []) {
		candidateIds.delete(r.followee_id as string);
	}
	if (candidateIds.size === 0) return [];

	const ids = [...candidateIds];
	const hydrated = await hydratePeopleSuggestions(ids, viewerId);
	// Rank by combined local signal (shared clubs + shared events) desc, then
	// shared-club count desc, then display_name. `shared_clubs` stays the
	// displayed count so the existing People-tab subtitle is unchanged. The
	// name term is `search_ranking.ts`'s, id tiebreak included, so this list
	// and the People search agree about two runners sharing a display name.
	const { comparePersonName } = await import('../social/search_ranking');
	return hydrated
		.map((p) => ({
			...p,
			shared_clubs: sharedClubs.get(p.id) ?? 0,
			_score: (sharedClubs.get(p.id) ?? 0) + (sharedEvents.get(p.id) ?? 0),
		}))
		.sort((a, b) => {
			if (b._score !== a._score) return b._score - a._score;
			if (b.shared_clubs !== a.shared_clubs) return b.shared_clubs - a.shared_clubs;
			return comparePersonName(a, b);
		})
		.slice(0, limit)
		.map(({ _score, ...p }) => p);
}

export interface NearbyRunner {
	id: string;
	display_name: string | null;
	avatar_url: string | null;
	bucket: number;
	viewer_follows: boolean;
}

/// Opt-in coarse-location "runners nearby" discovery (issue #466). Calls the
/// `discoverable_runners_near` SECURITY DEFINER RPC, which centres on the
/// CALLER's own stored coarse area and applies every eligibility filter
/// (opt-in, minor exclusion, shadow_hidden, search opt-out, blocks) server-
/// side, returning only a coarse distance BUCKET per runner — never a
/// coordinate. Gated in the UI behind the default-off `PUBLIC_ENABLE_NEARBY_RUNNERS`
/// flag pending owner + CISO/counsel sign-off; this data function is inert
/// (returns []) for anyone who has not opted in with an area set.
export async function fetchNearbyRunners(radiusM = 25000): Promise<NearbyRunner[]> {
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id ?? null;
	if (!viewerId) return [];

	const { data, error } = await supabase.rpc('discoverable_runners_near', {
		p_radius_m: radiusM,
	}, { get: true });
	if (error || !data) return [];
	const rows = data as Array<{
		id: string;
		display_name: string | null;
		avatar_url: string | null;
		bucket: number;
	}>;
	if (rows.length === 0) return [];

	const ids = rows.map((r) => r.id);
	const { data: followedRows } = await queryChunked(ids, (part) =>
		supabase
			.from('user_follows')
			.select('followee_id')
			.eq('follower_id', viewerId)
			.in('followee_id', part)
	);
	const following = new Set((followedRows ?? []).map((r) => r.followee_id as string));

	return rows.map((r) => ({
		id: r.id,
		display_name: r.display_name,
		avatar_url: r.avatar_url,
		bucket: r.bucket,
		viewer_follows: following.has(r.id),
	}));
}

/// Store the caller's coarse discoverable area (a geocoded city / area
/// centroid, rounded server-side to ~1 km). Never live GPS. Returns the
/// stored label so the settings UI can echo it back.
export async function setDiscoverableArea(
	lng: number,
	lat: number,
	label: string | null
): Promise<string | null> {
	const { data, error } = await supabase.rpc('set_discoverable_area', {
		p_lng: lng,
		p_lat: lat,
		p_label: label,
	});
	if (error) throw dbError(error);
	return (data as string | null) ?? null;
}

/// Forget the caller's stored coarse area — removes them from nearby discovery
/// regardless of the `discoverable_nearby` pref.
export async function clearDiscoverableArea(): Promise<void> {
	const { error } = await supabase.rpc('clear_discoverable_area');
	if (error) throw dbError(error);
}

/// The caller's own stored area label (never the coordinate), for the settings
/// UI. Null when no area is set.
export async function fetchMyDiscoverableArea(): Promise<string | null> {
	const { data, error } = await supabase.rpc('my_discoverable_area', undefined, { get: true });
	if (error) return null;
	return (data as string | null) ?? null;
}

/// The subset of `candidateIds` the viewer has NOT blocked. One batched read
/// of user_blocks — the owner-read RLS policy scopes it to the viewer's own
/// blocks, so this enforces the viewer→target direction that the client is
/// authorised to read (the same direction `isBlockedByViewer` reads). The
/// symmetric target→viewer direction is gated server-side on the content
/// surfaces via `is_blocked_either_way`; a fully-symmetric discovery filter
/// would need a set-returning definer RPC (follow-up). On a read error we
/// keep all candidates rather than empty the list — the read failing is
/// independent of the profile fetch, and blanking discovery on a transient
/// blocks error would be a worse regression than the rare leak.
async function filterOutBlocked(viewerId: string, candidateIds: string[]): Promise<string[]> {
	if (candidateIds.length === 0) return candidateIds;
	const { data, error } = await queryChunked(candidateIds, (part) =>
		supabase
			.from(TABLES.user_blocks)
			.select('blocked_id')
			.eq('blocker_id', viewerId)
			.in('blocked_id', part)
	);
	if (error) return candidateIds;
	const blocked = new Set((data ?? []).map((r) => r.blocked_id as string));
	return candidateIds.filter((id) => !blocked.has(id));
}

async function hydratePeopleSuggestions(
	ids: string[],
	viewerId: string | null
): Promise<PeopleSuggestion[]> {
	if (ids.length === 0) return [];
	// Never surface a blocked account in People search / "Suggested for you".
	// Every other social surface (kudos, comments, follows, leaderboards,
	// profile) gates on the block predicate; discovery must too, or a runner
	// who blocked a harasser keeps seeing them by name + avatar. Both search
	// and suggestions funnel through this single hydrate step, so the filter
	// lives here (matches the "keep block additions in one place" note on the
	// user_blocks migration).
	const visibleIds = viewerId ? await filterOutBlocked(viewerId, ids) : ids;
	if (visibleIds.length === 0) return [];
	const [profilesRes, countsRes, followsRes] = await Promise.all([
		queryChunked(visibleIds, (part) =>
			supabase
				.from('user_profiles')
				.select('id, display_name, avatar_url, handle')
				.in('id', part)
		),
		// Public-run counts via a SECURITY DEFINER GROUP BY RPC — one small row
		// per candidate, not one row per public run (which also can't be read
		// off the base runs table by a non-owner since 20260701_001 dropped the
		// public-anyone SELECT policy, so the old client tally returned ~0 for
		// everyone but the viewer). See public_run_counts (migration 20270118_001).
		supabase.rpc('public_run_counts', { p_user_ids: visibleIds }),
		viewerId
			? queryChunked(visibleIds, (part) =>
					supabase
						.from('user_follows')
						.select('followee_id')
						.eq('follower_id', viewerId)
						.in('followee_id', part)
				)
			: Promise.resolve({ data: [] as { followee_id: string }[] } as { data: { followee_id: string }[] }),
	]);
	const counts = new Map<string, number>();
	for (const row of (countsRes.data ?? []) as {
		user_id: string;
		public_run_count: number;
	}[]) {
		counts.set(row.user_id, Number(row.public_run_count) || 0);
	}
	const follows = new Set<string>(
		((followsRes.data ?? []) as { followee_id: string }[]).map((r) => r.followee_id)
	);
	return (profilesRes.data ?? []).map((p) => ({
		id: p.id as string,
		display_name: (p.display_name as string) ?? null,
		avatar_url: (p.avatar_url as string) ?? null,
		handle: ((p as { handle?: string | null }).handle as string) ?? null,
		public_runs_count: counts.get(p.id as string) ?? 0,
		shared_clubs: 0,
		viewer_follows: follows.has(p.id as string),
	}));
}

/// Default page size for the follower / following lists. The /u/[id]
/// tabs request one page at a time and load more on demand, so a user
/// with hundreds of followers is fully reachable rather than truncated.
export const FOLLOW_PAGE_SIZE = 50;

/// Newest follow first. The other party's id breaks a `followed_at` tie, which
/// makes the order total — a keyset over a non-unique order skips a tied row.
/// Served by `user_follows_followee` / `user_follows_follower`
/// (`(<anchor>, followed_at desc)`) up to the tie-break.
const FOLLOWERS_ORDER: readonly KeysetKey[] = [
	{ column: 'followed_at', ascending: false, nullsFirst: true },
	{ column: 'follower_id', ascending: false, nullsFirst: true },
];
const FOLLOWING_ORDER: readonly KeysetKey[] = [
	{ column: 'followed_at', ascending: false, nullsFirst: true },
	{ column: 'followee_id', ascending: false, nullsFirst: true },
];

/// Resolve follow-edge ids to profiles, in edge order. An id with no readable
/// profile row is dropped here, AFTER the cursor was taken from the edge, so
/// it neither ends the list early nor shifts the next page.
async function profilesInEdgeOrder(ids: string[]): Promise<PublicProfile[]> {
	const profiles = await readChunked(ids, async (part) => {
		const { data, error } = await supabase
			.from('user_profiles')
			.select('id, display_name, avatar_url')
			.in('id', part);
		if (error) throw dbError(error);
		return data ?? [];
	});
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles) byId.set(p.id, p);
	return ids.map((id) => byId.get(id)).filter((p): p is PublicProfile => p != null);
}

/// People who follow `userId`, newest follow first, one keyset page at a time:
/// pass the previous page's `next` as `after` to load more. A cursor rather
/// than an offset because an offset is a position — a follower who unfollows
/// between two reads moves every later row up one, and offset 50 then starts a
/// row late, so one follower is never shown.
export async function fetchFollowers(
	userId: string,
	opts?: { limit?: number; after?: KeysetCursor | null }
): Promise<KeysetPage<PublicProfile>> {
	const limit = opts?.limit ?? FOLLOW_PAGE_SIZE;
	const after = opts?.after ? keysetAfter(FOLLOWERS_ORDER, opts.after) : undefined;
	if (after === null) return { rows: [], next: null };
	let q = supabase
		.from('user_follows')
		.select('follower_id, followed_at')
		.eq('followee_id', userId);
	if (after) q = q.or(after);
	for (const k of FOLLOWERS_ORDER) {
		q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
	}
	const { data: edges, error } = await q.limit(limit);
	if (error) throw dbError(error);
	const rows = edges ?? [];
	return {
		rows: await profilesInEdgeOrder(rows.map((e) => e.follower_id)),
		next: nextCursor(FOLLOWERS_ORDER, rows, limit),
	};
}

/// People `userId` follows, newest follow first, one keyset page at a time
/// (see `fetchFollowers`).
export async function fetchFollowing(
	userId: string,
	opts?: { limit?: number; after?: KeysetCursor | null }
): Promise<KeysetPage<PublicProfile>> {
	const limit = opts?.limit ?? FOLLOW_PAGE_SIZE;
	const after = opts?.after ? keysetAfter(FOLLOWING_ORDER, opts.after) : undefined;
	if (after === null) return { rows: [], next: null };
	let q = supabase
		.from('user_follows')
		.select('followee_id, followed_at')
		.eq('follower_id', userId);
	if (after) q = q.or(after);
	for (const k of FOLLOWING_ORDER) {
		q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
	}
	const { data: edges, error } = await q.limit(limit);
	if (error) throw dbError(error);
	const rows = edges ?? [];
	return {
		rows: await profilesInEdgeOrder(rows.map((e) => e.followee_id)),
		next: nextCursor(FOLLOWING_ORDER, rows, limit),
	};
}

export interface FeedEntry extends Run {
	author: PublicProfile;
}

/// Activity feed: recent public runs from people the caller follows.
/// Cursor is the started_at + id of the last entry on the previous page;
/// pass null for the first page.
export const FEED_WINDOW_DAYS = 14;

/// Resolve the viewer's followed-author id set for a feed query: the ids the
/// caller follows, narrowed to a single author when `authorId` is supplied
/// (validated against the follow set so the URL can't enumerate strangers).
/// Returns [] when not signed in, the viewer follows nobody, or the requested
/// author isn't followed — every caller treats an empty set as "show nothing".
/// Resolved ONCE by `fetchFollowingActivityFeed` and threaded into both the
/// runs + lifts branches so a default feed page issues one user_follows read,
/// not two, and the two branches can't derive a divergent followee set.
async function resolveFollowedAuthorIds(authorId?: string | null): Promise<string[]> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) return [];
	const { data: edges } = await supabase
		.from('user_follows')
		.select('followee_id')
		.eq('follower_id', userId);
	const followeeIds = (edges ?? []).map((e) => e.followee_id as string);
	if (followeeIds.length === 0) return [];
	const wantedAuthor = authorId ?? null;
	return wantedAuthor ? followeeIds.filter((id) => id === wantedAuthor) : followeeIds;
}

export async function fetchFollowingFeed(
	opts?: {
		limit?: number;
		cursor?: { started_at: string; id: string } | null;
		/** Restrict to a single followee. Pass `null` / omit for "everyone you follow". */
		authorId?: string | null;
		/** Restrict by `runs.activity_type`. Pass 'all' / omit for any activity. */
		activityType?: string | null;
	},
	/** Pre-resolved followee set (from `resolveFollowedAuthorIds`); when the
	 * cross-modal orchestrator threads it in, this skips the redundant
	 * getSession + user_follows round-trip. Standalone callers omit it. */
	preresolvedAuthors?: string[]
): Promise<FeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const filteredAuthors =
		preresolvedAuthors ?? (await resolveFollowedAuthorIds(opts?.authorId));
	if (filteredAuthors.length === 0) return [];

	const cutoff = new Date(Date.now() - FEED_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
	// Feed reads go through the public_runs view (decisions §33,
	// migration 20260626_001) — the view filters on is_public and
	// applies the column / metadata-key redaction so feed entries
	// don't leak third-party ids or sync-state internals.
	//
	// The followee set is chunked: PostgREST serialises `.in()` into the
	// URL, so a viewer following many hundreds of people overflows the
	// gateway's request-line budget and the read is lost (decisions § 653).
	// Each chunk applies the same cursor + ordering + limit; the global
	// top-`limit` is a subset of the union of per-chunk results, which
	// mergeFeedPages collapses back down.
	const queryChunk = async (part: string[]) => {
		let q = supabase
			.from('public_runs')
			.select('*')
			.in('user_id', part)
			.gte('started_at', cutoff)
			.order('started_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(limit);
		if (opts?.activityType && opts.activityType !== 'all') {
			q = q.eq('activity_type', opts.activityType);
		}
		if (opts?.cursor) {
			// Stable cursor pagination on (started_at, id) — strictly less than
			// the cursor row to skip what we've already seen.
			q = q.or(
				`started_at.lt.${opts.cursor.started_at},and(started_at.eq.${opts.cursor.started_at},id.lt.${opts.cursor.id})`
			);
		}
		// Surface the error: a swallowed `{ data: null }` (5xx, RLS, gateway
		// in-clause overflow) is indistinguishable from a genuinely empty
		// feed, so the caller's try/catch could never show the load-failed
		// toast — a silent blank feed. Throw so SocialFeed / the profile feed
		// render the error state instead.
		const { data, error } = await q;
		if (error) throw dbError(error);
		return (data ?? []) as Run[];
	};

	const pages = await Promise.all(chunk(filteredAuthors, FEED_FOLLOWEE_CHUNK).map(queryChunk));
	const runs = mergeFeedPages(pages, limit);
	if (runs.length === 0) return [];

	const authorIds = Array.from(new Set(runs.map((r) => r.user_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', authorIds);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	return runs.map((r) => ({
		...(r as Run),
		author: byId.get(r.user_id) ?? { id: r.user_id, display_name: null, avatar_url: null },
	}));
}

/// A public gym workout surfaced in the activity feed. Carries only the
/// non-sensitive headline a "lift card" renders — title, set count, total
/// working volume in canonical kg, started_at — plus the author. No notes,
/// no RPE, no per-set detail leak into the feed; the share page is the place
/// for full detail.
export interface LiftFeedEntry {
	kind: 'lift';
	id: string;
	user_id: string;
	started_at: string;
	title: string | null;
	set_count: number;
	volume_kg: number;
	author: PublicProfile;
}

/// A run feed entry tagged with its kind so the feed can render a run card vs
/// a lift card off a single discriminated union.
export type RunFeedEntry = FeedEntry & { kind: 'run' };

/// The cross-modal activity feed entry — a run or a public lift.
export type ActivityFeedEntry = RunFeedEntry | LiftFeedEntry;

/// Cross-modal following feed (multi_modal.md § Social feed): recent public
/// runs AND public gym workouts from people the caller follows, merged into
/// one reverse-chronological window.
///
/// Runs go through the redacted `public_runs` view (decisions §33) — they are
/// deliberately invisible through the `activities` view to non-owners, so the
/// feed reads them on the same path `fetchFollowingFeed` does. Lifts go
/// through the redacted `public_gym_workouts` view for the same reason: the
/// base table is owner-only since migration 20270313_001, and the view
/// projects only the headline columns (title / set_count / volume_kg) — never
/// notes / metadata / per-set data. `set_count` + `volume_kg` are the
/// trigger-maintained derived columns
/// (migration 20261214_001), so a lift card is a flat per-branch read.
///
/// `activityType`: 'all' (default) merges both; 'lift' / 'gym' returns lifts
/// only; any run activity_type ('run' / 'walk' / 'cycle' / 'hike') returns
/// runs only.
export async function fetchFollowingActivityFeed(opts?: {
	limit?: number;
	cursor?: { started_at: string; id: string } | null;
	authorId?: string | null;
	activityType?: string | null;
}): Promise<ActivityFeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const activityType = opts?.activityType ?? 'all';
	const wantsLifts = activityType === 'all' || activityType === 'lift' || activityType === 'gym';
	const wantsRuns = activityType !== 'lift' && activityType !== 'gym';

	// Resolve the followee set ONCE and thread it into both branches so the
	// default ('all') feed issues a single user_follows read instead of two,
	// and the runs + lifts branches can't derive a divergent followee set.
	const authors = await resolveFollowedAuthorIds(opts?.authorId);
	if (authors.length === 0) return [];

	const runsPromise: Promise<RunFeedEntry[]> = wantsRuns
		? fetchFollowingFeed(opts, authors).then((rows) =>
				rows.map((r) => ({ ...r, kind: 'run' as const }))
			)
		: Promise.resolve([]);

	const liftsPromise: Promise<LiftFeedEntry[]> = wantsLifts
		? fetchFollowingLifts(opts, authors)
		: Promise.resolve([]);

	const [runs, lifts] = await Promise.all([runsPromise, liftsPromise]);
	return mergeFeedPages<ActivityFeedEntry>([runs, lifts], limit);
}

async function fetchFollowingLifts(
	opts?: {
		limit?: number;
		cursor?: { started_at: string; id: string } | null;
		authorId?: string | null;
	},
	preresolvedAuthors?: string[]
): Promise<LiftFeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const filteredAuthors =
		preresolvedAuthors ?? (await resolveFollowedAuthorIds(opts?.authorId));
	if (filteredAuthors.length === 0) return [];

	const cutoff = new Date(Date.now() - FEED_WINDOW_DAYS * 24 * 60 * 60 * 1000).toISOString();
	const queryChunk = async (part: string[]) => {
		let q = supabase
			.from('public_gym_workouts')
			.select('id, user_id, started_at, title, set_count, volume_kg')
			.eq('is_public', true)
			.in('user_id', part)
			.gte('started_at', cutoff)
			.order('started_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(limit);
		if (opts?.cursor) {
			q = q.or(
				`started_at.lt.${opts.cursor.started_at},and(started_at.eq.${opts.cursor.started_at},id.lt.${opts.cursor.id})`
			);
		}
		// Surface the error rather than coercing a failed read to an empty
		// page — see the matching note in fetchFollowingFeed's queryChunk.
		const { data, error } = await q;
		if (error) throw dbError(error);
		return (data ?? []) as {
			id: string;
			user_id: string;
			started_at: string;
			title: string | null;
			set_count: number | null;
			volume_kg: number | null;
		}[];
	};

	const pages = await Promise.all(chunk(filteredAuthors, FEED_FOLLOWEE_CHUNK).map(queryChunk));
	const workouts = mergeFeedPages(pages, limit);
	if (workouts.length === 0) return [];

	const authorIds = Array.from(new Set(workouts.map((w) => w.user_id)));
	const { data: profiles } = await supabase
		.from('user_profiles')
		.select('id, display_name, avatar_url')
		.in('id', authorIds);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	return workouts.map((w) => ({
		kind: 'lift' as const,
		id: w.id,
		user_id: w.user_id,
		started_at: w.started_at,
		title: w.title,
		set_count: w.set_count ?? 0,
		volume_kg: w.volume_kg ?? 0,
		author: byId.get(w.user_id) ?? { id: w.user_id, display_name: null, avatar_url: null },
	}));
}

/// Recent public runs from a single user — used by the profile page.
/// Reads through the public_runs view (decisions §33, migration
/// 20260626_001) so the redaction applies on the wire even when the
/// caller is signed in.
export async function fetchPublicRunsByUser(userId: string, limit = 20): Promise<Run[]> {
	const { data, error } = await supabase
		.from('public_runs')
		.select('*')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (error) throw dbError(error);
	return (data ?? []) as Run[];
}

export interface ProfileRunCounts {
	/** Runs anyone can see on the profile. */
	publicCount: number;
	/** The owner's runs that are NOT on the profile; null for any other viewer. */
	privateCount: number | null;
}

/// Head counts for the profile header. The header used to show the length of
/// the loaded run page, which capped at its limit and gave the owner no hint
/// that their private runs exist but aren't listed.
export async function fetchProfileRunCounts(userId: string, isSelf: boolean): Promise<ProfileRunCounts> {
	const [pub, priv] = await Promise.all([
		supabase.from('public_runs').select('id', { count: 'exact', head: true }).eq('user_id', userId),
		isSelf
			? supabase
					.from(TABLES.runs)
					.select('id', { count: 'exact', head: true })
					.eq('user_id', userId)
					.or('is_public.is.null,is_public.eq.false')
			: Promise.resolve({ count: null, error: null }),
	]);
	if (pub.error) throw dbError(pub.error);
	if (priv.error) throw dbError(priv.error);
	return { publicCount: pub.count ?? 0, privateCount: isSelf ? (priv.count ?? 0) : null };
}

// ─────────────────────── Kudos + comments on runs (decisions §32) ───────────────────────

export interface RunKudosSummary {
	count: number;
	viewer_has_kudos: boolean;
}

export interface RunCommentWithAuthor {
	id: string;
	run_id: string;
	author_id: string;
	parent_comment_id: string | null;
	body: string;
	created_at: string;
	updated_at: string;
	author: PublicProfile;
}

/// Batch kudos + comment counts for a list of runs — used on the
/// feed where mounting a full RunSocial per card would be wasteful.
/// Returns a map keyed by run id.
export async function fetchEngagementSummaries(
	runIds: string[]
): Promise<Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>> {
	const out = new Map<string, { kudos_count: number; viewer_has_kudos: boolean; comment_count: number }>();
	if (runIds.length === 0) return out;

	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id;

	// Counts come from a server-side GROUP BY (run_engagement_counts) so the
	// wire payload is one small row per run, not every kudos + comment row on
	// the page (a popular share used to ship hundreds of rows to compute one
	// integer). viewer_has_kudos stays a narrow per-run `in` lookup, chunked
	// because the caller's run list has no ceiling of its own.
	const [counts, viewerKudos] = await Promise.all([
		supabase.rpc('run_engagement_counts', { p_run_ids: runIds }),
		viewerId
			? queryChunked(runIds, (part) =>
					supabase
						.from(TABLES.run_kudos)
						.select('run_id')
						.eq('user_id', viewerId)
						.in('run_id', part)
				)
			: Promise.resolve({ data: [] as { run_id: string }[] }),
	]);

	for (const id of runIds) out.set(id, { kudos_count: 0, viewer_has_kudos: false, comment_count: 0 });
	for (const row of (counts.data ?? []) as {
		run_id: string;
		kudos_count: number;
		comment_count: number;
	}[]) {
		const e = out.get(row.run_id);
		if (e) {
			e.kudos_count = Number(row.kudos_count) || 0;
			e.comment_count = Number(row.comment_count) || 0;
		}
	}
	for (const row of (viewerKudos.data ?? []) as { run_id: string }[]) {
		const e = out.get(row.run_id);
		if (e) e.viewer_has_kudos = true;
	}
	return out;
}

/// Returns kudos count for a run + whether the current viewer has
/// given kudos. Two parallel queries — count is server-side, viewer
/// flag is one indexed lookup.
export async function fetchKudosForRun(runId: string): Promise<RunKudosSummary> {
	return (await fetchKudosForRunWithError(runId)).kudos;
}

/// Same as `fetchKudosForRun` but surfaces the load error instead of
/// silently returning a zero count — so a caller can tell a failed fetch
/// apart from a run with no kudos. Mirrors the `fetchRoutesWithError`
/// convention.
export async function fetchKudosForRunWithError(
	runId: string,
): Promise<{ kudos: RunKudosSummary; error: string | null }> {
	const { data: sessionData } = await supabase.auth.getSession();
	const viewerId = sessionData.session?.user?.id;

	const [countRes, viewerRes] = await Promise.all([
		supabase
			.from(TABLES.run_kudos)
			.select('*', { count: 'exact', head: true })
			.eq('run_id', runId),
		viewerId
			? supabase
					.from(TABLES.run_kudos)
					.select('user_id')
					.eq('run_id', runId)
					.eq('user_id', viewerId)
					.maybeSingle()
			: Promise.resolve({ data: null, error: null }),
	]);

	const err =
		countRes.error ??
		('error' in viewerRes ? (viewerRes.error as { message: string; code?: string } | null) : null);
	if (err) {
		console.error('fetchKudosForRun failed', err);
		return {
			kudos: { count: 0, viewer_has_kudos: false },
			error: `${err.message}${err.code ? ` (${err.code})` : ''}`,
		};
	}

	return {
		kudos: {
			count: countRes.count ?? 0,
			viewer_has_kudos: viewerRes.data != null,
		},
		error: null,
	};
}

/// Returns `true` when a NEW kudos row was inserted, `false` when the
/// viewer already had kudos (a 23505 no-op). The caller drives the
/// optimistic `+1` only on a real change — a stale local
/// `viewer_has_kudos: false` (kudos already given from another tab /
/// session) must not bump the count, or the displayed total drifts
/// above the server's.
export async function giveKudos(runId: string): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.run_kudos)
		.insert({ user_id: userId, run_id: runId });
	if (error) {
		if (isDuplicateKeyError(error)) return false;
		throw dbError(error);
	}
	return true;
}

/// Returns `true` when a kudos row was actually deleted, `false` when
/// there was nothing to remove (already rescinded). Mirror of
/// `giveKudos` — the caller applies the optimistic `-1` only on a real
/// delete so a stale local flag can't push the count below the server's.
export async function rescindKudos(runId: string): Promise<boolean> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.run_kudos)
		.delete()
		.eq('run_id', runId)
		.eq('user_id', userId)
		.select('user_id');
	if (error) throw dbError(error);
	return (data ?? []).length > 0;
}

/// Comments on a run, sorted oldest-first. Author profiles are joined
/// in a second round trip so PostgREST doesn't need an embedded select.
export async function fetchRunComments(runId: string, limit = 200): Promise<RunCommentWithAuthor[]> {
	return (await fetchRunCommentsWithError(runId, limit)).comments;
}

/// Same as `fetchRunComments` but surfaces the load error instead of
/// swallowing it to `[]` — so a caller can tell a failed fetch apart from
/// a run that genuinely has no comments. Mirrors the `fetchRoutesWithError`
/// convention.
export async function fetchRunCommentsWithError(
	runId: string,
	limit = 200,
): Promise<{ comments: RunCommentWithAuthor[]; error: string | null }> {
	const { data: rows, error } = await supabase
		.from(TABLES.run_comments)
		.select('*')
		.eq('run_id', runId)
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchRunComments failed', error);
		return { comments: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	if (!rows || rows.length === 0) return { comments: [], error: null };

	const authorIds = Array.from(new Set(rows.map((r) => r.author_id)));
	const { data: profiles } = await queryChunked(authorIds, (part) =>
		supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', part)
	);
	const byId = new Map<string, PublicProfile>();
	for (const p of profiles ?? []) byId.set(p.id, p);

	return {
		comments: rows.map((r) => ({
			...r,
			author: byId.get(r.author_id) ?? { id: r.author_id, display_name: null, avatar_url: null },
		})),
		error: null,
	};
}

export async function postRunComment(input: {
	run_id: string;
	body: string;
	parent_comment_id?: string | null;
}): Promise<void> {
	const { data: sessionData } = await supabase.auth.getSession();
	const userId = sessionData.session?.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase.from(TABLES.run_comments).insert({
		run_id: input.run_id,
		author_id: userId,
		body: input.body,
		parent_comment_id: input.parent_comment_id ?? null,
	});
	if (error) throw dbError(error);
}

export async function deleteRunComment(commentId: string): Promise<void> {
	const { error } = await supabase.from(TABLES.run_comments).delete().eq('id', commentId);
	if (error) throw dbError(error);
}

// ─────────── Reactions, comment likes, mentions (decisions § 1971) ───────────

export interface ReactionSummaryRow {
	reaction: string;
	reaction_count: number;
	viewer_reacted: boolean;
}

/// Per-reaction counts on a run plus the viewer's own. The RPC is INVOKER, so
/// RLS decides what is counted and a run the viewer cannot read returns no
/// rows. A failed read is reported, not folded into "no reactions".
export async function fetchRunReactionSummary(
	runId: string,
): Promise<{ rows: ReactionSummaryRow[]; error: string | null }> {
	const { data, error } = await supabase.rpc('run_reaction_summary', { p_run_id: runId }, { get: true });
	if (error) return { rows: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	return { rows: (data ?? []) as ReactionSummaryRow[], error: null };
}

/// `true` when a new row was inserted, `false` when the viewer already had
/// this reaction (a 23505 no-op) — the same contract as `giveKudos`.
export async function addRunReaction(runId: string, reaction: string): Promise<boolean> {
	const userId = await currentViewerId();
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.run_reactions)
		.insert({ user_id: userId, run_id: runId, reaction });
	if (error) {
		if (isDuplicateKeyError(error)) return false;
		throw dbError(error);
	}
	return true;
}

/// `true` when a row was deleted, `false` when there was nothing to remove.
export async function removeRunReaction(runId: string, reaction: string): Promise<boolean> {
	const userId = await currentViewerId();
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.run_reactions)
		.delete()
		.eq('run_id', runId)
		.eq('user_id', userId)
		.eq('reaction', reaction)
		.select('user_id');
	if (error) throw dbError(error);
	return (data ?? []).length > 0;
}

export interface CommentLikeSummary {
	count: number;
	viewer_liked: boolean;
}

/// Like counts for every liked comment on a run, keyed by comment id. A
/// comment absent from the map has no likes.
export async function fetchRunCommentLikeSummary(
	runId: string,
): Promise<{ likes: Map<string, CommentLikeSummary>; error: string | null }> {
	const { data, error } = await supabase.rpc('run_comment_like_summary', { p_run_id: runId }, { get: true });
	const likes = new Map<string, CommentLikeSummary>();
	if (error) return { likes, error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	for (const row of data ?? []) {
		likes.set(row.comment_id, {
			count: Math.max(0, Number(row.like_count) || 0),
			viewer_liked: row.viewer_liked === true,
		});
	}
	return { likes, error: null };
}

/// `true` on a new like, `false` when the viewer had already liked it.
export async function likeRunComment(commentId: string): Promise<boolean> {
	const userId = await currentViewerId();
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.run_comment_likes)
		.insert({ user_id: userId, comment_id: commentId });
	if (error) {
		if (isDuplicateKeyError(error)) return false;
		throw dbError(error);
	}
	return true;
}

/// `true` when a like was removed, `false` when there was none.
export async function unlikeRunComment(commentId: string): Promise<boolean> {
	const userId = await currentViewerId();
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.run_comment_likes)
		.delete()
		.eq('comment_id', commentId)
		.eq('user_id', userId)
		.select('user_id');
	if (error) throw dbError(error);
	return (data ?? []).length > 0;
}

/// Resolve mentioned handles to profile ids, so a comment can link the ones
/// that name a real runner and leave the rest as plain text. Handles are
/// stored lowercase (decisions § 269), so the lookup is an exact match.
export async function resolveMentionHandles(handles: string[]): Promise<Map<string, string>> {
	const out = new Map<string, string>();
	const wanted = Array.from(new Set(handles.map((h) => h.toLowerCase()))).slice(0, 200);
	let rows: { id: string; handle: string | null }[];
	try {
		rows = await readChunked(wanted, async (part) => {
			const { data, error } = await supabase
				.from('user_profiles')
				.select('id, handle')
				.in('handle', part);
			if (error) throw dbError(error);
			return data ?? [];
		});
	} catch (error) {
		console.error('resolveMentionHandles failed', error);
		return out;
	}
	for (const row of rows) if (row.handle) out.set(row.handle, row.id);
	return out;
}

// --- Run photos (decisions §36) ---

export interface RunPhoto {
	id: string;
	/// Null for an event steward's photo of an occurrence, which belongs to
	/// no run (migration 20270807000001). Every photo read by run has one.
	run_id: string | null;
	owner_id: string;
	storage_path: string;
	/// Server-generated 512w thumbnail path, populated by the
	/// photo_process job (apps/job_worker handler_photo_process.go).
	/// Null while the job is still queued OR when the original is
	/// already small enough that resizing would just inflate the
	/// stored bytes. Gallery callers should prefer `thumbUrl` when
	/// present and fall back to `url`.
	thumb_512_path: string | null;
	caption: string | null;
	position_idx: number;
	created_at: string;
	/// Set when the photo is tagged to an event gallery (#49).
	event_id: string | null;
	event_instance_start: string | null;
	/// The owner opted this photo into the public race-listing page
	/// (`set_run_photo_race_gallery`, decisions § 1961). Shown there only
	/// while the run is public and linked to that listing.
	race_gallery: boolean;
	url: string;
	thumbUrl: string | null;
}

/// A photo in an event gallery — a `RunPhoto` plus the uploader's
/// display name so the gallery can attribute each shot. (#49)
///
/// `run_id` is deliberately omitted: an event gallery is visible to
/// anyone who can see the event (even when the underlying run is
/// private), so surfacing the run's UUID would bridge a public event to
/// a private run's id. The gallery never needs it.
///
/// `hidden_at` is set when an event steward hid the photo from the gallery
/// (`set_event_photo_hidden`, migration 20270807000001). The gallery read,
/// `event_gallery_photos` (20270807000003), returns a hidden photo only to its
/// owner and the event's stewards — RLS alone cannot, because a photo on a
/// public run is readable through the run path.
export interface EventPhoto extends Omit<RunPhoto, 'run_id' | 'race_gallery'> {
	uploader_name: string | null;
	hidden_at: string | null;
}

// Every key must be a format `stripImageExif` can clean — an accepted-but-
// unstrippable type uploads a geotagged original verbatim.
const PHOTO_MIME_TO_EXT: Record<string, string> = {
	'image/jpeg': 'jpg',
	'image/png': 'png',
	'image/webp': 'webp',
};

const PHOTO_MAX_BYTES = 10 * 1024 * 1024; // 10 MB

// `run-photos` is a private bucket (migration 20260712_001 — closed the
// public-CDN bypass on the visibility gate). Signed URLs carry their own
// TTL that the Storage layer honours independently of the SELECT policy,
// so a URL minted while a run was public stays valid for its whole TTL
// even after the run flips to private. 15 min keeps that revocation gap
// short while still comfortably outlasting a gallery render (re-signing
// happens on the next fetch, not per render).
const PHOTO_SIGNED_URL_TTL_S = 15 * 60;

async function signRunPhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from(BUCKETS.run_photos)
		.createSignedUrls(paths, PHOTO_SIGNED_URL_TTL_S);
	if (error || !data) {
		console.error('signRunPhotoPaths failed', error);
		return {};
	}
	const out: Record<string, string> = {};
	for (const row of data) {
		if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
	}
	return out;
}

export async function fetchRunPhotos(runId: string, limit = 50): Promise<RunPhoto[]> {
	return (await fetchRunPhotosWithError(runId, limit)).photos;
}

/// Same as `fetchRunPhotos` but surfaces the load error instead of
/// swallowing it to `[]` — so the gallery can render a distinct error
/// state rather than looking byte-for-byte like an empty gallery. Mirrors
/// the `fetchRoutesWithError` convention.
export async function fetchRunPhotosWithError(
	runId: string,
	limit = 50,
): Promise<{ photos: RunPhoto[]; error: string | null }> {
	const { data, error } = await supabase
		.from(TABLES.run_photos)
		.select('*')
		.eq('run_id', runId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchRunPhotos failed', error);
		return { photos: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	const rows = data ?? [];
	// Sign both the original and any present thumbnail in one batch
	// — Storage's createSignedUrls handles missing paths gracefully
	// (returns an empty array entry) so the dedupe + fallback are
	// safe even on fresh uploads where the worker hasn't filled in
	// thumb_512_path yet.
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const signed = await signRunPhotoPaths(paths);
	return {
		photos: rows.map((r) => ({
			...r,
			url: signed[r.storage_path] ?? '',
			thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
		})),
		error: null,
	};
}

/// Event gallery (#49): every photo tagged to this event instance,
/// across all attendees' runs. RLS lets anyone who can see the event
/// read these even when the underlying run is private. Uploader names
/// are fetched in a second batched query (the `run_photos` → `runs` →
/// `user_profiles` join isn't expressible through PostgREST resource
/// embedding because the run may be invisible to the viewer).
///
/// Surfaces the load error rather than collapsing it to `[]`, so the gallery
/// can tell "nobody has posted yet" from "the gallery did not load".
export async function fetchEventPhotos(
	eventId: string,
	instanceStart: string,
	limit = 100,
): Promise<{ photos: EventPhoto[]; error: string | null }> {
	// `event_gallery_photos` returns no `run_id`, so a private run's UUID can't
	// leak to an event viewer who can't see that run.
	const { data, error } = await supabase.rpc(
		'event_gallery_photos',
		{
			p_event_id: eventId,
			p_instance: instanceStart,
			p_limit: limit,
		},
		{ get: true },
	);
	if (error) {
		console.error('fetchEventPhotos failed', error);
		return { photos: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	// The generator types a RETURNS TABLE column as non-null; these three are nullable.
	const rows = (data ?? []).map((r) => ({
		...r,
		caption: r.caption as string | null,
		thumb_512_path: r.thumb_512_path as string | null,
		hidden_at: r.hidden_at as string | null,
	}));
	if (rows.length === 0) return { photos: [], error: null };
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const ownerIds = [...new Set(rows.map((r) => r.owner_id))];
	const [signed, profiles] = await Promise.all([
		signRunPhotoPaths(paths),
		supabase.from('user_profiles').select('id, display_name').in('id', ownerIds),
	]);
	const nameById = new Map<string, string | null>(
		(profiles.data ?? []).map((p) => [p.id as string, (p.display_name as string | null) ?? null]),
	);
	return {
		photos: rows.map((r) => ({
			...r,
			url: signed[r.storage_path] ?? '',
			thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
			uploader_name: nameById.get(r.owner_id) ?? null,
		})),
		error: null,
	};
}

/// Whether the viewer is one of this event's photo stewards — a club owner,
/// admin or event organiser, or the event's named host — who may post photos
/// with no run and hide any photo in its galleries. The host column is not
/// client-readable, so the server answers. Fails closed to false.
export async function canStewardEventPhotos(eventId: string): Promise<boolean> {
	if (!auth.user) return false;
	const { data, error } = await supabase.rpc(
		'can_steward_event_photos',
		{ p_event_id: eventId },
		{ get: true },
	);
	if (error) {
		console.error('canStewardEventPhotos failed', error);
		return false;
	}
	return data === true;
}

/// Hide a photo from an event gallery, or restore it. Steward-only, enforced
/// by the RPC. Hiding leaves an attendee's photo on their own run.
export async function setEventPhotoHidden(photoId: string, hidden: boolean): Promise<void> {
	const { error } = await supabase.rpc('set_event_photo_hidden', {
		p_photo_id: photoId,
		p_hidden: hidden,
	});
	if (error) throw dbError(error);
}

/// A runner's photo on a public race-listing page. Deliberately carries no
/// run id, owner id or original-file URL: the page is logged-out and indexed,
/// so it shows the processed thumbnail and the uploader's public name only.
export interface RaceListingPhoto {
	id: string;
	thumbUrl: string;
	caption: string | null;
	createdAt: string;
	displayName: string | null;
}

/// Opted-in photos for a race listing (`race_listing_photos`, decisions
/// § 1961). The RPC applies every visibility rule — opt-in, public run linked
/// to this listing, processed thumbnail, not hidden — so the client filters
/// nothing. A failure resolves to `[]` and is logged: the race page is
/// logged-out, and an empty gallery is hidden rather than shown as an error.
export async function fetchRaceListingPhotos(
	listingId: string,
	limit = 24,
): Promise<RaceListingPhoto[]> {
	const { data, error } = await supabase.rpc(
		'race_listing_photos',
		{ p_listing_id: listingId, p_limit: limit },
		{ get: true },
	);
	if (error) {
		console.error('fetchRaceListingPhotos failed', error);
		return [];
	}
	const rows = data ?? [];
	if (rows.length === 0) return [];
	const signed = await signRunPhotoPaths(rows.map((r) => r.thumb_512_path));
	const out: RaceListingPhoto[] = [];
	for (const r of rows) {
		const thumbUrl = signed[r.thumb_512_path];
		if (!thumbUrl) continue;
		out.push({
			id: r.id,
			thumbUrl,
			caption: (r.caption as string | null) ?? null,
			createdAt: r.created_at,
			displayName: (r.display_name as string | null) ?? null,
		});
	}
	return out;
}

/// Show one of the caller's run photos on its race-listing page, or withdraw
/// it. Owner-only, enforced by the RPC.
export async function setRunPhotoRaceGallery(photoId: string, shared: boolean): Promise<void> {
	const { error } = await supabase.rpc('set_run_photo_race_gallery', {
		p_photo_id: photoId,
		p_shared: shared,
	});
	if (error) throw dbError(error);
}

/// The viewer's runs the database will accept for an occurrence's gallery:
/// those that started inside the photo window (`event_photo_window.ts`).
/// Queried by the window rather than filtered from the latest few runs, so an
/// occurrence from months ago still offers the run recorded at it.
export async function fetchRunsForEventPhoto(
	instanceStart: string,
	limit = 20,
): Promise<RecentRunOption[]> {
	const userId = auth.user?.id;
	const occ = Date.parse(instanceStart);
	if (!userId || !Number.isFinite(occ)) return [];
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('id, started_at, duration_s, distance_m, activity_type')
		.eq('user_id', userId)
		.gte('started_at', new Date(occ - EVENT_PHOTO_WINDOW_BEFORE_MS).toISOString())
		.lt('started_at', new Date(occ + EVENT_PHOTO_WINDOW_AFTER_MS).toISOString())
		.order('started_at', { ascending: true })
		.limit(limit);
	if (error) throw dbError(error);
	return (data ?? [])
		.filter((r) => isRunInEventPhotoWindow(r.started_at, instanceStart))
		.map((r) => ({
			id: r.id,
			started_at: r.started_at,
			duration_s: r.duration_s,
			distance_m: r.distance_m,
			activity_type: r.activity_type ?? 'run',
		}));
}

export async function addRunPhoto(input: {
	/// Null only for an event steward's photo of an occurrence (no run), which
	/// then requires `event_id` + `event_instance_start` (migration
	/// 20270807000001).
	run_id: string | null;
	file: File;
	caption?: string | null;
	/// When set, the photo joins the event's gallery (#49). The DB
	/// INSERT policy requires the uploader can see the event.
	event_id?: string | null;
	event_instance_start?: string | null;
}): Promise<RunPhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	// Strip EXIF/XMP (incl. GPS) client-side before upload so a geotagged
	// original never sits readable in the bucket ahead of the server worker's
	// async strip. Mirrors mobile's pre-upload strip (persona woman/family #52).
	// The strip sniffs the bytes and refuses a format it cannot clean, so the
	// accepted set is decided here, not by the browser-supplied File.type.
	const file = await stripExifFromFile(input.file);
	if (!file) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const ext = PHOTO_MIME_TO_EXT[file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.run_photos)
		.upload(storagePath, file, {
			contentType: file.type,
			upsert: false,
		});
	if (upErr) throw dbError(upErr);

	let nextIdx = 0;
	if (input.run_id) {
		const { data: posData } = await supabase
			.from(TABLES.run_photos)
			.select('position_idx')
			.eq('run_id', input.run_id)
			.order('position_idx', { ascending: false })
			.limit(1)
			.maybeSingle();
		nextIdx = (posData?.position_idx ?? -1) + 1;
	}

	const { data, error } = await supabase
		.from(TABLES.run_photos)
		.insert({
			id: photoId,
			run_id: input.run_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
			event_id: input.event_id ?? null,
			event_instance_start: input.event_instance_start ?? null,
		})
		.select('*')
		.single();
	if (error || !data) {
		// Best-effort cleanup of the uploaded blob if metadata insert fails.
		await supabase.storage.from(BUCKETS.run_photos).remove([storagePath]);
		throw error ? dbError(error) : new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from(BUCKETS.run_photos)
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
		// Always null on the insert path: `thumb_512_path` is written later by
		// the photo_process job, so there is no thumbnail to sign yet. The key
		// was simply missing, which made a just-uploaded photo the one case
		// where a `RunPhoto` carried `undefined` under a type promising
		// `string | null`.
		thumbUrl: null,
	};
}

export async function deleteRunPhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from(TABLES.run_photos)
		.select('storage_path, thumb_512_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw dbError(fetchErr);

	const { error } = await supabase.from(TABLES.run_photos).delete().eq('id', photoId);
	if (error) throw dbError(error);

	// Sweep both the original upload AND the worker-generated 512-wide
	// thumbnail. Best-effort — RLS allows the photo owner to remove their
	// own bytes. If the run owner (not photo owner) deleted the row, the
	// bytes will be orphaned in Storage but invisible to the UI.
	const paths = [row?.storage_path, row?.thumb_512_path].filter(
		(p: string | null | undefined): p is string => !!p,
	);
	if (paths.length > 0) {
		await supabase.storage.from(BUCKETS.run_photos).remove(paths);
	}
}

// ─────────────────────────────── Avatars ───────────────────────────────
// Profile-picture upload into the PUBLIC `avatars` bucket (migration
// 20260927_001). Unlike run/route photos, avatars are public profile data —
// they render on the logged-out /u/[id] profile as a bare <img src> — so the
// bucket is public and avatar_url holds a plain public URL.

const AVATAR_MIME_TO_EXT: Record<string, string> = {
	'image/jpeg': 'jpg',
	'image/png': 'png',
	'image/webp': 'webp',
};
// Matches the `avatars` bucket file_size_limit (2 MB, migration 20260927_001);
// reject client-side so the user gets a friendly message instead of a 413.
const AVATAR_MAX_BYTES = 2 * 1024 * 1024;

// Every per-user avatar object lives at a stable path keyed by extension, so
// the full set a user could own is enumerable for cleanup without a folder
// `list` (which the public bucket's RLS doesn't grant authenticated callers).
const avatarPathsFor = (userId: string): string[] =>
	Object.values(AVATAR_MIME_TO_EXT).map((e) => `${userId}/avatar.${e}`);

/// Upload a profile avatar and point `user_profiles.avatar_url` at it.
/// EXIF/GPS is stripped client-side first — the bucket is public and has no
/// server-side strip worker, so this is the only strip. We remove-then-insert
/// at the stable `{uid}/avatar.{ext}` path rather than upsert: the avatars
/// bucket grants owner INSERT + DELETE but not the upsert WITH-CHECK path, so a
/// plain INSERT onto a freshly-cleared path is the only write that passes RLS.
/// A `?v=` cache-bust keeps an <img> off the previous picture (the query still
/// satisfies the avatar_url `^https?://` CHECK). Returns the new public URL,
/// already written to the profile row.
export async function uploadAvatar(file: File): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	if (file.size > AVATAR_MAX_BYTES) throw new Error('Image too large (2 MB max)');

	const clean = await stripExifFromFile(file);
	if (!clean) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const ext = AVATAR_MIME_TO_EXT[clean.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const storagePath = `${userId}/avatar.${ext}`;

	// Clear any existing avatar (this ext and the others) so the upload is a
	// clean INSERT, not an upsert. remove() on a missing path is a no-op.
	await supabase.storage.from(BUCKETS.avatars).remove(avatarPathsFor(userId));

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.avatars)
		.upload(storagePath, clean, { contentType: clean.type, upsert: false });
	if (upErr) throw dbError(upErr);

	const { data: pub } = supabase.storage.from(BUCKETS.avatars).getPublicUrl(storagePath);
	const url = `${pub.publicUrl}?v=${Date.now()}`;

	const { error: profErr } = await supabase
		.from('user_profiles')
		.update({ avatar_url: url })
		.eq('id', userId);
	if (profErr) {
		// Roll back the blob so a failed profile write doesn't leave an
		// orphaned avatar the UI never references.
		await supabase.storage.from(BUCKETS.avatars).remove([storagePath]);
		throw dbError(profErr);
	}
	return url;
}

/// Remove the user's avatar — drops every stored object for them and clears
/// `user_profiles.avatar_url` to null (renderers fall back to initials).
export async function removeAvatar(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	await supabase.storage.from(BUCKETS.avatars).remove(avatarPathsFor(userId));
	const { error } = await supabase
		.from('user_profiles')
		.update({ avatar_url: null })
		.eq('id', userId);
	if (error) throw dbError(error);
}

export async function updateRunPhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from(TABLES.run_photos)
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw dbError(error);
}

// --- Route photos (backlog C1) ---
//
// The run_photos capability applied to routes. Metadata in `route_photos`;
// bytes in the private `route-photos` bucket at `{owner_id}/{photo_id}.{ext}`.
// The Storage SELECT policy joins through `route_photos` →
// `private.is_route_visible_to(route_id, auth.uid())`, so a route flipping
// from public to private propagates within the signed-URL TTL. Owner gates
// upload + caption + delete.

export interface RoutePhoto {
	id: string;
	route_id: string;
	owner_id: string;
	storage_path: string;
	thumb_512_path: string | null;
	caption: string | null;
	position_idx: number;
	created_at: string;
	url: string;
	thumbUrl: string | null;
}

async function signRoutePhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from(BUCKETS.route_photos)
		.createSignedUrls(paths, PHOTO_SIGNED_URL_TTL_S);
	if (error || !data) {
		console.error('signRoutePhotoPaths failed', error);
		return {};
	}
	const out: Record<string, string> = {};
	for (const row of data) {
		if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
	}
	return out;
}

export async function fetchRoutePhotos(routeId: string, limit = 50): Promise<RoutePhoto[]> {
	return (await fetchRoutePhotosWithError(routeId, limit)).photos;
}

/// Same as `fetchRoutePhotos` but surfaces the load error instead of
/// swallowing it to `[]` — so the gallery can render a distinct error
/// state rather than looking byte-for-byte like an empty gallery. Mirrors
/// the `fetchRoutesWithError` convention.
export async function fetchRoutePhotosWithError(
	routeId: string,
	limit = 50,
): Promise<{ photos: RoutePhoto[]; error: string | null }> {
	const { data, error } = await supabase
		.from(TABLES.route_photos)
		.select('*')
		.eq('route_id', routeId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchRoutePhotos failed', error);
		return { photos: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	const rows = data ?? [];
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const signed = await signRoutePhotoPaths(paths);
	return {
		photos: rows.map((r) => ({
			...r,
			url: signed[r.storage_path] ?? '',
			thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
		})),
		error: null,
	};
}

export async function addRoutePhoto(input: {
	route_id: string;
	file: File;
	caption?: string | null;
}): Promise<RoutePhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	const file = await stripExifFromFile(input.file);
	if (!file) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const ext = PHOTO_MIME_TO_EXT[file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.route_photos)
		.upload(storagePath, file, {
			contentType: file.type,
			upsert: false,
		});
	if (upErr) throw dbError(upErr);

	const { data: posData } = await supabase
		.from(TABLES.route_photos)
		.select('position_idx')
		.eq('route_id', input.route_id)
		.order('position_idx', { ascending: false })
		.limit(1)
		.maybeSingle();
	const nextIdx = (posData?.position_idx ?? -1) + 1;

	const { data, error } = await supabase
		.from(TABLES.route_photos)
		.insert({
			id: photoId,
			route_id: input.route_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
		})
		.select('*')
		.single();
	if (error || !data) {
		await supabase.storage.from(BUCKETS.route_photos).remove([storagePath]);
		throw error ? dbError(error) : new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from(BUCKETS.route_photos)
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
		thumbUrl: null,
	};
}

export async function deleteRoutePhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from(TABLES.route_photos)
		.select('storage_path, thumb_512_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw dbError(fetchErr);

	const { error } = await supabase.from(TABLES.route_photos).delete().eq('id', photoId);
	if (error) throw dbError(error);

	const paths = [row?.storage_path, row?.thumb_512_path].filter(
		(p: string | null | undefined): p is string => !!p,
	);
	if (paths.length > 0) {
		await supabase.storage.from(BUCKETS.route_photos).remove(paths);
	}
}

export async function updateRoutePhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from(TABLES.route_photos)
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw dbError(error);
}

// --- Club photos (gallery; migration 20270301_001) ---
// Mirrors the route-photo path but keyed on club membership: any active
// member may upload; a photo's owner OR a club admin may delete (moderation).

export interface ClubPhoto {
	id: string;
	club_id: string;
	owner_id: string;
	storage_path: string;
	thumb_512_path: string | null;
	caption: string | null;
	position_idx: number;
	created_at: string;
	url: string;
	thumbUrl: string | null;
}

async function signClubPhotoPaths(paths: string[]): Promise<Record<string, string>> {
	if (paths.length === 0) return {};
	const { data, error } = await supabase.storage
		.from(BUCKETS.club_photos)
		.createSignedUrls(paths, PHOTO_SIGNED_URL_TTL_S);
	if (error || !data) {
		console.error('signClubPhotoPaths failed', error);
		return {};
	}
	const out: Record<string, string> = {};
	for (const row of data) {
		if (row.path && row.signedUrl) out[row.path] = row.signedUrl;
	}
	return out;
}

export async function fetchClubPhotos(clubId: string, limit = 50): Promise<ClubPhoto[]> {
	return (await fetchClubPhotosWithError(clubId, limit)).photos;
}

/// Same as `fetchClubPhotos` but surfaces the load error instead of
/// swallowing it to `[]` — so the gallery can render a distinct error
/// state rather than looking byte-for-byte like an empty gallery. Mirrors
/// the `fetchRoutesWithError` convention.
export async function fetchClubPhotosWithError(
	clubId: string,
	limit = 50,
): Promise<{ photos: ClubPhoto[]; error: string | null }> {
	const { data, error } = await supabase
		.from(TABLES.club_photos)
		.select('*')
		.eq('club_id', clubId)
		.order('position_idx', { ascending: true })
		.order('created_at', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchClubPhotos failed', error);
		return { photos: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	const rows = data ?? [];
	const paths: string[] = [];
	for (const r of rows) {
		paths.push(r.storage_path);
		if (r.thumb_512_path) paths.push(r.thumb_512_path);
	}
	const signed = await signClubPhotoPaths(paths);
	return {
		photos: rows.map((r) => ({
			...r,
			url: signed[r.storage_path] ?? '',
			thumbUrl: r.thumb_512_path ? (signed[r.thumb_512_path] ?? null) : null,
		})),
		error: null,
	};
}

export async function addClubPhoto(input: {
	club_id: string;
	file: File;
	caption?: string | null;
}): Promise<ClubPhoto> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	if (input.file.size > PHOTO_MAX_BYTES) throw new Error('Image too large (10 MB max)');

	const file = await stripExifFromFile(input.file);
	if (!file) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');
	const ext = PHOTO_MIME_TO_EXT[file.type];
	if (!ext) throw new Error('Unsupported image type — JPEG, PNG, or WebP only');

	const photoId = crypto.randomUUID();
	const storagePath = `${userId}/${photoId}.${ext}`;

	const { error: upErr } = await supabase.storage
		.from(BUCKETS.club_photos)
		.upload(storagePath, file, {
			contentType: file.type,
			upsert: false,
		});
	if (upErr) throw dbError(upErr);

	const { data: posData } = await supabase
		.from(TABLES.club_photos)
		.select('position_idx')
		.eq('club_id', input.club_id)
		.order('position_idx', { ascending: false })
		.limit(1)
		.maybeSingle();
	const nextIdx = (posData?.position_idx ?? -1) + 1;

	const { data, error } = await supabase
		.from(TABLES.club_photos)
		.insert({
			id: photoId,
			club_id: input.club_id,
			owner_id: userId,
			storage_path: storagePath,
			caption: input.caption?.trim() || null,
			position_idx: nextIdx,
		})
		.select('*')
		.single();
	if (error || !data) {
		await supabase.storage.from(BUCKETS.club_photos).remove([storagePath]);
		throw error ? dbError(error) : new Error('Insert failed');
	}
	const { data: signed } = await supabase.storage
		.from(BUCKETS.club_photos)
		.createSignedUrl(storagePath, PHOTO_SIGNED_URL_TTL_S);
	return {
		...data,
		url: signed?.signedUrl ?? '',
		thumbUrl: null,
	};
}

export async function deleteClubPhoto(photoId: string): Promise<void> {
	const { data: row, error: fetchErr } = await supabase
		.from(TABLES.club_photos)
		.select('storage_path, thumb_512_path')
		.eq('id', photoId)
		.maybeSingle();
	if (fetchErr) throw dbError(fetchErr);

	const { error } = await supabase.from(TABLES.club_photos).delete().eq('id', photoId);
	if (error) throw dbError(error);

	const paths = [row?.storage_path, row?.thumb_512_path].filter(
		(p: string | null | undefined): p is string => !!p,
	);
	if (paths.length > 0) {
		await supabase.storage.from(BUCKETS.club_photos).remove(paths);
	}
}

export async function updateClubPhotoCaption(
	photoId: string,
	caption: string | null,
): Promise<void> {
	const trimmed = caption?.trim() || null;
	const { error } = await supabase
		.from(TABLES.club_photos)
		.update({ caption: trimmed })
		.eq('id', photoId);
	if (error) throw dbError(error);
}

// --- Route course markers (migration 20270129_001) ---

function asRouteMarker(row: Record<string, unknown>): RouteMarker {
	return {
		...row,
		meta: (row.meta as Record<string, unknown>) ?? {}
	} as RouteMarker;
}

/// Course markers for a route, ordered by distance along the line. Reads
/// through `route_markers_for_viewer`, which gates visibility (owner /
/// public / club member) AND redacts any marker inside the owner's privacy
/// zones for a non-owner — the marker analogue of `clip_route_for_viewer`.
/// A failed read throws rather than answering "no markers": nothing leaks
/// either way, but an empty list tells an owner to re-add markers they have.
///
/// Issued as a GET, not supabase-js's default POST. The function is
/// `stable`, and Kong replays an idempotent request whose pooled PostgREST
/// connection closed under it, where a POST comes back 502 (decisions § 1703).
export async function fetchRouteMarkers(routeId: string): Promise<RouteMarker[]> {
	const { data, error } = await supabase.rpc(
		'route_markers_for_viewer',
		{ p_route_id: routeId },
		{ get: true },
	);
	if (error) throw dbError(error);
	return ((data ?? []) as Record<string, unknown>[]).map(asRouteMarker);
}

export async function addRouteMarker(input: {
	route_id: string;
	kind: RouteMarkerKind;
	label: string;
	lat: number;
	lng: number;
	meta?: JsonObject;
}): Promise<RouteMarker> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const { data, error } = await supabase
		.from(TABLES.route_markers)
		.insert({
			route_id: input.route_id,
			user_id: userId,
			kind: input.kind,
			label: input.label.trim(),
			lat: input.lat,
			lng: input.lng,
			meta: input.meta ?? {}
		})
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('Insert failed');
	return asRouteMarker(data);
}

export async function updateRouteMarker(
	id: string,
	patch: { kind?: RouteMarkerKind; label?: string; lat?: number; lng?: number; meta?: JsonObject }
): Promise<void> {
	const update: Updatable<'route_markers'> = {};
	if (patch.kind !== undefined) update.kind = patch.kind;
	if (patch.label !== undefined) update.label = patch.label.trim();
	if (patch.lat !== undefined) update.lat = patch.lat;
	if (patch.lng !== undefined) update.lng = patch.lng;
	if (patch.meta !== undefined) update.meta = patch.meta;
	if (Object.keys(update).length === 0) return;

	const { error } = await supabase.from(TABLES.route_markers).update(update).eq('id', id);
	if (error) throw dbError(error);
}

export async function deleteRouteMarker(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.route_markers).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Route condition reports (migration 20270215_001) ---

function asRouteCondition(row: Record<string, unknown>): RouteCondition {
	return {
		...row,
		condition: row.condition as RouteConditionKind,
		severity: row.severity as RouteConditionSeverity
	} as RouteCondition;
}

/// Condition reports for a route, newest first. Reads through
/// `route_conditions_for_viewer`, which gates visibility (owner / public /
/// club member) AND nulls the anchor of any report inside the owner's privacy
/// zones for a non-owner — the condition analogue of `route_markers_for_viewer`.
/// Fails closed (empty list) on error so a redaction failure never leaks.
export async function fetchRouteConditions(routeId: string): Promise<RouteCondition[]> {
	return (await fetchRouteConditionsWithError(routeId)).conditions;
}

/// Same as `fetchRouteConditions` but surfaces the load error instead of
/// swallowing it to `[]` — so the panel can render a distinct error state
/// instead of sticking on "Loading…" forever. Mirrors the
/// `fetchRoutesWithError` convention.
export async function fetchRouteConditionsWithError(
	routeId: string,
): Promise<{ conditions: RouteCondition[]; error: string | null }> {
	const { data, error } = await supabase.rpc('route_conditions_for_viewer', {
		p_route_id: routeId
	}, { get: true });
	if (error) {
		console.warn('route_conditions_for_viewer failed', error);
		return { conditions: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	return {
		conditions: ((data ?? []) as Record<string, unknown>[]).map(asRouteCondition),
		error: null
	};
}

export async function addRouteCondition(input: {
	route_id: string;
	condition: RouteConditionKind;
	severity: RouteConditionSeverity;
	note?: string | null;
	lat?: number | null;
	lng?: number | null;
}): Promise<RouteCondition> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const note = input.note?.trim();
	const { data, error } = await supabase
		.from(TABLES.route_conditions)
		.insert({
			route_id: input.route_id,
			user_id: userId,
			condition: input.condition,
			severity: input.severity,
			note: note && note.length > 0 ? note : null,
			lat: input.lat ?? null,
			lng: input.lng ?? null
		})
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('Insert failed');
	return asRouteCondition(data);
}

export async function deleteRouteCondition(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.route_conditions).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Heatmap / popular-route discovery (decisions backlog item #4) ---

export interface HeatmapPoint {
	lng: number;
	lat: number;
}

/// Fetch densified sample points from public routes intersecting the
/// given bounding box. Backed by the `heatmap_points_in_bbox` PostGIS
/// RPC (migration 20260828_001), which itself caps the response at
/// `max_points` to keep the wire size bounded — a continent-wide pan
/// returns the same 5k points as a city pan, just spread thinner.
/// Empty array on RPC error so the caller's map layer just stays
/// blank rather than throwing.
export async function fetchHeatmapPoints(bbox: {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
	maxPoints?: number;
}): Promise<HeatmapPoint[]> {
	const { data, error } = await supabase.rpc('heatmap_points_in_bbox', {
		p_min_lng: bbox.minLng,
		p_min_lat: bbox.minLat,
		p_max_lng: bbox.maxLng,
		p_max_lat: bbox.maxLat,
		p_max_points: bbox.maxPoints ?? 5000,
	}, { get: true });
	if (error || !data) {
		console.warn('fetchHeatmapPoints failed', error);
		return [];
	}
	return (data as { lng: number; lat: number }[]).map((r) => ({
		lng: r.lng,
		lat: r.lat,
	}));
}

/// Public clubs with a `location_point` inside the viewport bbox.
/// Backed by the SECURITY DEFINER RPC `clubs_in_bbox` (migration
/// 20260911_001). Used by the /routes?tab=heatmap discoverable-
/// pins layer so club locations show alongside the density
/// heatmap. The RPC is `is_public = true` gated server-side; this
/// caller does NOT see private clubs even if the row is in range.
export interface ClubPin {
	id: string;
	name: string;
	slug: string | null;
	avatar_url: string | null;
	location_label: string | null;
	member_count: number;
	lng: number;
	lat: number;
}

export async function fetchClubsInBbox(bbox: {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
	limit?: number;
}): Promise<ClubPin[]> {
	const { data, error } = await supabase.rpc('clubs_in_bbox', {
		p_min_lng: bbox.minLng,
		p_min_lat: bbox.minLat,
		p_max_lng: bbox.maxLng,
		p_max_lat: bbox.maxLat,
		p_limit: bbox.limit ?? 100,
	}, { get: true });
	if (error || !data) {
		console.warn('fetchClubsInBbox failed', error);
		return [];
	}
	return data as ClubPin[];
}

/// Discoverable public routes inside the viewport bbox. The lens is
/// chosen by `filter`:
///   • 'popular'     (default) — featured OR run_count > 0.
///   • 'featured'    — admin-curated only.
///   • 'friends'     — public routes created by users you follow.
///   • 'hidden_gems' — un-run public routes past a >=1km sanity floor.
/// Returns the start_point for each route so the map can drop a pin
/// there. Mirrors the `p_filter` branch in
/// 20261113_001_discoverable_routes_filter.sql — keep the union in
/// lockstep with the RPC's CASE arms.
export type DiscoverFilter = 'popular' | 'featured' | 'friends' | 'hidden_gems';

export interface DiscoverableRoutePin {
	id: string;
	name: string;
	slug: string | null;
	is_featured: boolean;
	distance_m: number;
	elevation_m: number | null;
	surface: string;
	run_count: number;
	lng: number;
	lat: number;
}

export async function fetchDiscoverableRoutesInBbox(bbox: {
	minLng: number;
	minLat: number;
	maxLng: number;
	maxLat: number;
	limit?: number;
	filter?: DiscoverFilter;
	/// Selected race-distance bands. Empty / omitted = no distance
	/// filter. Ranges are resolved via `bandsToRanges` so the band
	/// numbers stay owned by `distance_bands.ts`.
	bands?: DistanceBandKey[];
}): Promise<DiscoverableRoutePin[]> {
	const ranges = bandsToRanges(bbox.bands ?? []);
	const { data, error } = await supabase.rpc('discoverable_routes_in_bbox', {
		p_min_lng: bbox.minLng,
		p_min_lat: bbox.minLat,
		p_max_lng: bbox.maxLng,
		p_max_lat: bbox.maxLat,
		p_limit: bbox.limit ?? 100,
		p_filter: bbox.filter ?? 'popular',
		p_dist_min: ranges.min ?? undefined,
		// Postgres accepts NULL elements (open-ended ultra bound); the
		// generated arg type is number[], so cast past the null.
		p_dist_max: (ranges.max ?? undefined) as number[] | undefined,
	});
	if (error || !data) {
		console.warn('fetchDiscoverableRoutesInBbox failed', error);
		return [];
	}
	return data as DiscoverableRoutePin[];
}

// --- Gear tracking (decisions backlog item #7) ---

export type GearKind = 'shoe' | 'bike';

export interface Gear {
	id: string;
	owner_id: string;
	kind: GearKind;
	name: string;
	brand: string | null;
	model: string | null;
	purchased_at: string | null;
	retired_at: string | null;
	target_distance_m: number | null;
	notes: string | null;
	is_default: boolean;
	created_at: string;
	updated_at: string;
}

export interface GearWithDistance extends Gear {
	total_distance_m: number;
	run_count: number;
}

/// Fetch every gear item the signed-in user owns, with the rolled-up
/// total distance from `gear_with_distance`. Default order: active
/// (retired_at IS NULL) first, then newest. Settings UI renders sub-
/// tabs (shoes / bikes) on top of this single fetch.
export async function fetchMyGear(): Promise<GearWithDistance[]> {
	const { data, error } = await supabase
		.from('gear_with_distance')
		.select('*')
		.order('retired_at', { ascending: true, nullsFirst: true })
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchMyGear failed', error);
		return [];
	}
	return ((data ?? []) as GearWithDistance[]).map((g) => ({
		...g,
		// Postgres bigint comes through as a string in some PostgREST
		// configurations; coerce defensively so the UI math is never
		// surprised by 'NaN km'.
		total_distance_m: Number(g.total_distance_m ?? 0),
		target_distance_m:
			g.target_distance_m == null ? null : Number(g.target_distance_m),
	}));
}

export async function createGear(input: {
	kind: GearKind;
	name: string;
	brand?: string | null;
	model?: string | null;
	purchased_at?: string | null;
	target_distance_m?: number | null;
	notes?: string | null;
}): Promise<Gear> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.gear)
		.insert({
			owner_id: userId,
			kind: input.kind,
			name: input.name,
			brand: input.brand ?? null,
			model: input.model ?? null,
			purchased_at: input.purchased_at ?? null,
			target_distance_m: input.target_distance_m ?? null,
			notes: input.notes ?? null,
		})
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createGear failed');
	return data as Gear;
}

export async function updateGear(
	id: string,
	patch: Partial<Pick<Gear,
		'name' | 'brand' | 'model' | 'purchased_at' | 'retired_at' |
		'target_distance_m' | 'notes'
	>>,
): Promise<void> {
	const { error } = await supabase.from(TABLES.gear).update(patch).eq('id', id);
	if (error) throw dbError(error);
}

/// Mark this gear as the user's current default for its kind. Unsets
/// any sibling (same owner + same kind) first so the partial-unique
/// constraint `(owner_id, kind) where is_default and not retired`
/// never trips. Pass null to clear the default for this kind entirely.
export async function setDefaultGear(
	gearId: string | null,
	kind: GearKind,
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error: clearErr } = await supabase
		.from(TABLES.gear)
		.update({ is_default: false })
		.eq('owner_id', userId)
		.eq('kind', kind)
		.eq('is_default', true);
	if (clearErr) throw dbError(clearErr);
	if (gearId !== null) {
		const { error: setErr } = await supabase
			.from(TABLES.gear)
			.update({ is_default: true })
			.eq('id', gearId);
		if (setErr) throw dbError(setErr);
	}
}

/// Stamp retired_at to today and clear nothing else — the row stays
/// around for historical mileage roll-ups on past runs that reference
/// it. Use [deleteGear] to actually remove (cascades to run_gear).
export async function retireGear(id: string): Promise<void> {
	// Local-tz today — `toISOString().slice(0,10)` returns the UTC date, which
	// rolls a calendar day early/late depending on the runner's TZ (same fix as
	// the active-plan overview above).
	const { todayISO } = await import('../training/training');
	await updateGear(id, { retired_at: todayISO() });
}

/// Un-retire — restore an actively-tracked piece of gear without
/// touching anything else. Useful when a runner pulled an old pair
/// out of retirement for slow / treadmill runs.
export async function unretireGear(id: string): Promise<void> {
	await updateGear(id, { retired_at: null });
}

export async function deleteGear(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.gear).delete().eq('id', id);
	if (error) throw dbError(error);
}

/// Replace the full gear set assigned to a run. Empty array clears
/// the assignment. Idempotent — re-running with the same set is a
/// no-op once the round trip completes. RLS gates both the insert
/// and the delete to the run's owner.
export async function setRunGear(runId: string, gearIds: string[]): Promise<void> {
	// Delete-then-insert is the simple shape; the join table has no
	// natural-key churn to make a smarter diff worthwhile. Wrap in
	// best-effort error surfacing for the toast layer.
	const del = await supabase.from(TABLES.run_gear).delete().eq('run_id', runId);
	if (del.error) throw dbError(del.error);
	if (gearIds.length === 0) return;
	const rows = gearIds.map((gear_id) => ({ run_id: runId, gear_id }));
	const ins = await supabase.from(TABLES.run_gear).insert(rows);
	if (ins.error) throw dbError(ins.error);
}

/// Attach ONE piece of gear to many past runs, additively — the write half of
/// the post-create backfill prompt on /settings/gear.
///
/// Deliberately not [setRunGear]: that replaces a run's whole gear set, so
/// backfilling a newly-registered pair through it would silently untag every
/// other item the run already carried. This only ever adds. `ignoreDuplicates`
/// makes a repeat backfill a no-op instead of a 23505, matching the mobile
/// `ApiClient.addGearToRuns` shape. It is also the only upsert resolution that
/// works here: `run_gear` carries SELECT / INSERT / DELETE policies and no
/// UPDATE one, so PostgREST's default merge-duplicates (`ON CONFLICT DO
/// UPDATE`) has no policy to pass on a collision.
///
/// RLS gates every row: the `run_gear` insert policy requires the caller to
/// own BOTH the run and the gear, so a forged run id writes nothing.
export async function addGearToRuns(gearId: string, runIds: string[]): Promise<number> {
	if (runIds.length === 0) return 0;
	const rows = runIds.map((run_id) => ({ run_id, gear_id: gearId }));
	const { error } = await supabase
		.from(TABLES.run_gear)
		.upsert(rows, { onConflict: 'run_id,gear_id', ignoreDuplicates: true });
	if (error) throw dbError(error);
	return rows.length;
}

/// Fetch the gear assigned to a single run. Used on the run-detail page AND
/// the PUBLIC share page (non-owner / anon viewer) to render the chip row.
///
/// Goes through the `public_run_gear` SECURITY DEFINER RPC
/// (migration 20261126_001) rather than a `run_gear` → `gear` table join. The
/// `gear` SELECT policy is owner-only, so a join returns NULL gear rows for any
/// non-owner — the chip used to render for the owner only. The RPC gates on
/// `is_run_visible_to` and projects ONLY the public columns (id / kind / name /
/// brand / model); owner-private inventory metadata (notes / purchased_at /
/// retired_at / target_distance_m) is never selected, so exposing gear on a
/// public run stays leak-free.
export async function fetchRunGear(runId: string): Promise<Gear[]> {
	const { data, error } = await supabase.rpc('public_run_gear', { p_run_id: runId }, { get: true });
	if (error || !data) {
		console.error('fetchRunGear failed', error);
		return [];
	}
	return data as Gear[];
}

// --- Gear wear-pattern logging (roadmap §7) ---

export type GearWearArea = 'outsole' | 'midsole' | 'upper' | 'other';

export interface GearWearLog {
	id: string;
	gear_id: string;
	owner_id: string;
	logged_on: string;
	area: GearWearArea | null;
	note: string;
	created_at: string;
	updated_at: string;
}

/// Fetch a gear item's wear log, newest observation first. Owner-scoped by
/// RLS — a non-owner read returns nothing, never another user's notes.
export async function fetchGearWearLogs(gearId: string): Promise<GearWearLog[]> {
	const { data, error } = await supabase
		.from(TABLES.gear_wear_logs)
		.select('*')
		.eq('gear_id', gearId)
		.order('logged_on', { ascending: false })
		.order('created_at', { ascending: false });
	if (error) {
		console.error('fetchGearWearLogs failed', error);
		return [];
	}
	return (data ?? []) as GearWearLog[];
}

export async function addGearWearLog(input: {
	gearId: string;
	note: string;
	area?: GearWearArea | null;
	loggedOn?: string | null;
}): Promise<GearWearLog> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.gear_wear_logs)
		.insert({
			gear_id: input.gearId,
			owner_id: userId,
			note: input.note,
			area: input.area ?? null,
			// Let the column default (current_date) win when no date is supplied.
			...(input.loggedOn ? { logged_on: input.loggedOn } : {}),
		})
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('addGearWearLog failed');
	return data as GearWearLog;
}

export async function deleteGearWearLog(id: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gear_wear_logs)
		.delete()
		.eq('id', id);
	if (error) throw dbError(error);
}

// --- Gear rotations (roadmap §7 — named multi-pair grouping) ---

export interface GearRotation {
	id: string;
	owner_id: string;
	name: string;
	created_at: string;
	updated_at: string;
}

/// A rotation plus the ids of the gear it contains. The membership ids
/// are fetched alongside so the settings UI can group the gear list by
/// rotation and pre-check the assignment toggles without a second round
/// trip per rotation.
export interface GearRotationWithMembers extends GearRotation {
	gear_ids: string[];
}

/// Fetch every rotation the signed-in user owns, each with its member
/// gear ids. Two owner-scoped reads (rotations + the membership join)
/// stitched client-side — both are tiny (a runner has a handful of
/// rotations), and RLS scopes each to the owner.
export async function fetchMyGearRotations(): Promise<GearRotationWithMembers[]> {
	const { data: rotations, error: rotErr } = await supabase
		.from(TABLES.gear_rotations)
		.select('*')
		.order('name', { ascending: true });
	if (rotErr) {
		console.error('fetchMyGearRotations failed', rotErr);
		return [];
	}
	const { data: members, error: memErr } = await supabase
		.from(TABLES.gear_rotation_members)
		.select('rotation_id, gear_id');
	if (memErr) {
		console.error('fetchMyGearRotations members failed', memErr);
		return [];
	}
	const byRotation = new Map<string, string[]>();
	for (const m of (members ?? []) as { rotation_id: string; gear_id: string }[]) {
		const list = byRotation.get(m.rotation_id) ?? [];
		list.push(m.gear_id);
		byRotation.set(m.rotation_id, list);
	}
	return ((rotations ?? []) as GearRotation[]).map((r) => ({
		...r,
		gear_ids: byRotation.get(r.id) ?? [],
	}));
}

export async function createGearRotation(name: string): Promise<GearRotation> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.gear_rotations)
		.insert({ owner_id: userId, name })
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createGearRotation failed');
	return data as GearRotation;
}

export async function renameGearRotation(id: string, name: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gear_rotations)
		.update({ name })
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Delete a rotation. Membership rows cascade away via the FK; the gear
/// itself is untouched (a rotation is just a grouping).
export async function deleteGearRotation(id: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.gear_rotations)
		.delete()
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Replace the full gear set assigned to a rotation. Delete-then-insert,
/// mirroring [setRunGear] — the join has no natural-key churn worth a
/// smarter diff. RLS gates both halves to the rotation + gear owner.
export async function setGearRotationMembers(
	rotationId: string,
	gearIds: string[],
): Promise<void> {
	const del = await supabase
		.from(TABLES.gear_rotation_members)
		.delete()
		.eq('rotation_id', rotationId);
	if (del.error) throw dbError(del.error);
	if (gearIds.length === 0) return;
	const rows = gearIds.map((gear_id) => ({ rotation_id: rotationId, gear_id }));
	const ins = await supabase.from(TABLES.gear_rotation_members).insert(rows);
	if (ins.error) throw dbError(ins.error);
}

// --- Safety contacts (decisions §131) ---

export interface SafetyContact {
	id: string;
	contact_email: string;
	contact_phone: string | null;
	contact_user_id: string | null;
	confirmed_at: string | null;
	sms_opt_in_at: string | null;
	created_at: string;
}

export interface PendingSafetyRequest {
	id: string;
	owner_name: string;
	has_phone: boolean;
	created_at: string;
}

/// The owner's own safety-contact list, scoped by an explicit `owner_id`
/// filter. RLS is NOT the scope here and never was: `safety_contacts` carries
/// a second permissive SELECT policy for `contact_user_id = auth.uid()`
/// (20261218_001), and permissive policies OR — so an unfiltered read returns
/// the union of the rows you own and the rows naming YOU as someone else's
/// contact, rendered as your own list under your own email address.
/// Reports the error rather than degrading to `[]`: on a safety surface a
/// failed read rendered as "you have no emergency contacts", which is the
/// one wrong answer a runner might act on — so a signed-out caller is an
/// error, not an empty list.
export async function fetchMySafetyContacts(): Promise<{
	contacts: SafetyContact[];
	error: string | null;
}> {
	const userId = auth.user?.id;
	if (!userId) return { contacts: [], error: 'Not signed in' };
	const { data, error } = await supabase
		.from(TABLES.safety_contacts)
		.select('id, contact_email, contact_phone, contact_user_id, confirmed_at, sms_opt_in_at, created_at')
		.eq('owner_id', userId)
		.order('created_at', { ascending: false });
	return { contacts: (data ?? []) as SafetyContact[], error: error?.message ?? null };
}

/// Add a safety contact by email. The address is stored as-is; a confirm
/// email is sent by the AFTER INSERT trigger. confirmed_at / contact_user_id
/// are forced null server-side (the contact must opt in), so we never set
/// them here. Throws on RLS / unique / format failure for the caller to
/// surface.
export async function addSafetyContact(email: string, phone?: string | null): Promise<SafetyContact> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const trimmedPhone = phone?.trim() ?? '';
	const { data, error } = await supabase
		.from(TABLES.safety_contacts)
		.insert({ owner_id: userId, contact_email: email, contact_phone: trimmedPhone || null })
		.select('id, contact_email, contact_phone, contact_user_id, confirmed_at, sms_opt_in_at, created_at')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('addSafetyContact failed');
	return data as SafetyContact;
}

/// Remove a safety contact the owner added, scoped by an explicit `owner_id`
/// filter for the same reason the read is: the table's second permissive
/// DELETE policy (`contact_user_id = auth.uid()`) means an unscoped
/// delete-by-id succeeds against a row naming the caller as SOMEONE ELSE's
/// contact — silently stripping that person's emergency contact under a
/// button labelled as the caller's own housekeeping. Withdrawing from a
/// relationship you are the contact of is `declineSafetyRequest`, which says
/// so.
export async function removeSafetyContact(id: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { error } = await supabase
		.from(TABLES.safety_contacts)
		.delete()
		.eq('id', id)
		.eq('owner_id', userId);
	if (error) throw dbError(error);
}

/// A relationship in which SOMEONE ELSE named the signed-in user as their
/// safety contact and the user confirmed. The mirror image of
/// `SafetyContact`, and the only place `set_safety_sms_opt_in` can be called
/// from once the confirm step is behind you.
export interface SafetyContactOf {
	id: string;
	owner_id: string;
	owner_name: string | null;
	has_phone: boolean;
	sms_opt_in_at: string | null;
	created_at: string;
}

/// The contact-of direction of `safety_contacts`, scoped by an explicit
/// `contact_user_id` filter for the same reason the owner list scopes on
/// `owner_id` (§720): the table's permissive policies OR, so a query has to
/// state which half it wants rather than inherit whatever RLS happens to
/// allow. The linked-contact SELECT policy (`20261218_001`) already permits
/// exactly this read, so no migration is involved. Every row here is a
/// confirmed relationship by construction — `contact_user_id` is set only by
/// `confirm_safety_contact`, which stamps `confirmed_at` in the same UPDATE.
///
/// The owner's stored number is reported as a FACT, never as digits. It only
/// gates whether the SMS consent toggle means anything, and there is no owner
/// UPDATE policy, so a contact could not correct a wrong number from here
/// even if it were shown — the same posture `my_pending_safety_requests`
/// takes with `has_phone`.
///
/// Reports the error rather than degrading to `[]`, matching the owner list:
/// a signed-out caller is an error, not "you are nobody's contact".
export async function fetchSafetyContactOf(): Promise<{
	relationships: SafetyContactOf[];
	error: string | null;
}> {
	const userId = auth.user?.id;
	if (!userId) return { relationships: [], error: 'Not signed in' };
	const { data, error } = await supabase
		.from(TABLES.safety_contacts)
		.select('id, owner_id, contact_phone, sms_opt_in_at, created_at')
		.eq('contact_user_id', userId)
		.order('created_at', { ascending: false });
	if (error) return { relationships: [], error: error.message };
	const rows = (data ?? []) as {
		id: string;
		owner_id: string;
		contact_phone: string | null;
		sms_opt_in_at: string | null;
		created_at: string;
	}[];
	// A shadow-hidden or unreadable owner degrades to the anonymous fallback
	// rather than dropping the row: the consent controls are the point, the
	// name is decoration.
	const byId = await fetchProfilesByIds([...new Set(rows.map((r) => r.owner_id))]);
	return {
		relationships: rows.map((r) => ({
			id: r.id,
			owner_id: r.owner_id,
			owner_name: byId.get(r.owner_id)?.display_name ?? null,
			has_phone: r.contact_phone !== null,
			sms_opt_in_at: r.sms_opt_in_at,
			created_at: r.created_at,
		})),
		error: null,
	};
}

/// Pending requests where the signed-in user is the named contact (matched
/// by their account email via a SECURITY DEFINER RPC — the pending row isn't
/// directly readable until they link by confirming).
export async function fetchPendingSafetyRequests(): Promise<{
	requests: PendingSafetyRequest[];
	error: string | null;
}> {
	const { data, error } = await supabase.rpc('my_pending_safety_requests', undefined, { get: true });
	return {
		requests: (data ?? []) as PendingSafetyRequest[],
		error: error?.message ?? null,
	};
}

/// Confirm a pending request addressed to my account email (links my
/// account). `smsOptIn` additionally consents to SMS alerts — armed only when
/// the owner stored a phone number (server-enforced). Returns whether a row
/// was confirmed.
export async function confirmSafetyRequest(id: string, smsOptIn = false): Promise<boolean> {
	const { data, error } = await supabase.rpc('confirm_safety_contact', {
		p_id: id,
		p_sms_opt_in: smsOptIn,
	});
	if (error) throw dbError(error);
	return data === true;
}

/// Turn SMS consent on/off on a relationship the signed-in user is the
/// confirmed contact of. Opting in requires a phone on file (server-enforced).
export async function setSafetySmsOptIn(id: string, optIn: boolean): Promise<boolean> {
	const { data, error } = await supabase.rpc('set_safety_sms_opt_in', { p_id: id, p_opt_in: optIn });
	if (error) throw dbError(error);
	return data === true;
}

/// Set (or clear, with null) the per-run "not back by X" expected-return
/// override on one of my own in-progress broadcast runs. The overdue scan
/// escalates to my confirmed safety contacts once this time passes. Returns
/// whether the run was updated (false if it isn't mine or isn't in-progress).
export async function setRunExpectedReturn(
	runId: string,
	expectedReturnAt: string | null,
): Promise<boolean> {
	const { data, error } = await supabase.rpc('set_run_expected_return', {
		p_run_id: runId,
		p_expected_return_at: expectedReturnAt,
	});
	if (error) throw dbError(error);
	return data === true;
}

/// The run a safety contact's escalation link admits (decisions § 1964), or
/// null when it admits nothing: a wrong token, an ended or concluded run, an
/// expired link and a closed gate all read the same. POST, never `get: true`,
/// so the token travels in the body and stays out of request-URL logs.
export async function fetchSafetyLiveRun(
	runId: string,
	token: string,
): Promise<{
	started_at: string;
	duration_s: number;
	distance_m: number;
	route_id: string | null;
	owner_name: string;
} | null> {
	const { data, error } = await supabase.rpc('safety_live_run', {
		p_run_id: runId,
		p_token: token,
	});
	if (error) throw dbError(error);
	const row = singleEmbed(data);
	if (!row) return null;
	return {
		started_at: row.started_at,
		duration_s: Number(row.duration_s ?? 0),
		distance_m: Number(row.distance_m ?? 0),
		route_id: row.route_id ?? null,
		owner_name: row.owner_name ?? '',
	};
}

/// Privacy-clipped pings for a safety contact's link. Without `since` the
/// newest 1000, newest first (the backlog); with it, what arrived after it,
/// oldest first (the poll). Empty when the link admits nothing.
export async function fetchSafetyLivePings(
	runId: string,
	token: string,
	since: string | null = null,
): Promise<
	Array<{
		lat: number;
		lng: number;
		distance_m: number | null;
		elapsed_s: number | null;
		at: string;
		coarse: boolean;
	}>
> {
	const { data, error } = await supabase.rpc('safety_live_pings', {
		p_run_id: runId,
		p_token: token,
		...(since ? { p_since: since } : {}),
	});
	if (error) throw dbError(error);
	return Array.isArray(data) ? data : [];
}

/// Decline a pending request / withdraw from a confirmed one.
export async function declineSafetyRequest(id: string): Promise<boolean> {
	const { data, error } = await supabase.rpc('decline_safety_contact', { p_id: id });
	if (error) throw dbError(error);
	return data === true;
}

/// Unauthenticated email-link confirm for an external contact. The token is
/// the capability; the anon Supabase client may call it.
export async function confirmSafetyContactByToken(token: string, smsOptIn = false): Promise<boolean> {
	const { data, error } = await supabase.rpc('confirm_safety_contact_by_token', {
		p_token: token,
		p_sms_opt_in: smsOptIn,
	});
	if (error) throw dbError(error);
	return data === true;
}

// --- Segments + leaderboards (decisions §37) ---

export interface Segment {
	id: string;
	route_id: string;
	name: string;
	start_distance_m: number;
	end_distance_m: number;
	length_m: number | null;
	author_id: string | null;
	created_at: string;
}

export interface SegmentEffort {
	id: string;
	segment_id: string;
	run_id: string;
	user_id: string;
	time_seconds: number;
	started_at: string;
	created_at: string;
}

export interface SegmentLeaderboardEntry {
	effort: SegmentEffort;
	athlete: PublicProfile;
	rank: number;
}

export interface SegmentEffortWithSegment {
	effort: SegmentEffort;
	segment: Segment;
	/** Null when the rank RPC did not answer for this effort — see
	 *  `segments/rank_pill.ts`. Absent is not `#1`. */
	rank: number | null;
}

export async function fetchSegmentsForRoute(routeId: string, limit = 100): Promise<Segment[]> {
	return (await fetchSegmentsForRouteWithError(routeId, limit)).segments;
}

/// Same as `fetchSegmentsForRoute` but surfaces the load error instead of
/// swallowing it to `[]` — so the panel can render a distinct error state
/// instead of sticking on the loading spinner forever. Mirrors the
/// `fetchRoutesWithError` convention.
export async function fetchSegmentsForRouteWithError(
	routeId: string,
	limit = 100,
): Promise<{ segments: Segment[]; error: string | null }> {
	const { data, error } = await supabase
		.from(TABLES.segments)
		.select('*')
		.eq('route_id', routeId)
		.order('start_distance_m', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchSegmentsForRoute failed', error);
		return { segments: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	return { segments: (data ?? []) as Segment[], error: null };
}

export async function createSegment(input: {
	route_id: string;
	name: string;
	start_distance_m: number;
	end_distance_m: number;
}): Promise<Segment> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.segments)
		.insert({
			route_id: input.route_id,
			name: input.name.trim(),
			start_distance_m: input.start_distance_m,
			end_distance_m: input.end_distance_m,
			author_id: userId,
		})
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('Insert failed');
	return data as Segment;
}

export async function deleteSegment(segmentId: string): Promise<void> {
	const { error } = await supabase.from(TABLES.segments).delete().eq('id', segmentId);
	if (error) throw dbError(error);
}

// SEGMENT_AGE_BANDS, SegmentAgeBand, and SegmentGenderFilter live in
// `./segments` (pure module, importable by unit tests without pulling
// in the SvelteKit-only supabase client). Re-exported here so existing
// callers don't break.
export { SEGMENT_AGE_BANDS, type SegmentAgeBand, type SegmentGenderFilter } from '../segments/segments';

/**
 * Tiered leaderboard for a segment. Calls the `segment_leaderboard_tiered` RPC
 * which joins user_profiles server-side and applies gender / age-band
 * filters. Pass `null` for "all" on a filter. Ranks are computed
 * client-side from the returned order (1-based standard competition —
 * ties share a rank; next distinct time skips ordinal positions).
 */
export async function fetchSegmentLeaderboardTieredWithError(
	segmentId: string,
	filter: {
		gender?: SegmentGenderFilter | null;
		ageBand?: SegmentAgeBand | null;
		clubId?: string | null;
	} = {},
	limit = 50,
): Promise<{ entries: SegmentLeaderboardEntry[]; error: string | null }> {
	const { data, error } = await supabase.rpc('segment_leaderboard_tiered', {
		p_segment_id: segmentId,
		p_gender: filter.gender ?? undefined,
		p_age_band: filter.ageBand ?? undefined,
		p_limit: limit,
		p_club_id: filter.clubId ?? undefined,
	}, { get: true });
	if (error) {
		console.warn('fetchSegmentLeaderboardTiered failed', error);
		return { entries: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	const rows = (data ?? []) as Array<{
		effort_id: string;
		user_id: string;
		run_id: string;
		time_seconds: number;
		started_at: string;
		display_name: string | null;
		avatar_url: string | null;
		gender: string | null;
		age: number | null;
	}>;
	return {
		entries: assignCompetitionRanks(rows).map(({ row, rank }) => ({
			effort: {
				id: row.effort_id,
				segment_id: segmentId,
				run_id: row.run_id,
				user_id: row.user_id,
				time_seconds: row.time_seconds,
				started_at: row.started_at,
				created_at: row.started_at,
			} as SegmentEffort,
			athlete: { id: row.user_id, display_name: row.display_name, avatar_url: row.avatar_url },
			rank,
		})),
		error: null,
	};
}

export async function fetchSegmentLeaderboardTiered(
	segmentId: string,
	filter: {
		gender?: SegmentGenderFilter | null;
		ageBand?: SegmentAgeBand | null;
		clubId?: string | null;
	} = {},
	limit = 50,
): Promise<SegmentLeaderboardEntry[]> {
	return (await fetchSegmentLeaderboardTieredWithError(segmentId, filter, limit)).entries;
}

/**
 * All segment efforts attached to a single run, joined to the parent
 * segment so the run-detail page can render "Climb of doom — 4:21,
 * #3 of 17". Rank is computed via a count query against the
 * leaderboard.
 */
export async function fetchEffortsForRun(runId: string): Promise<SegmentEffortWithSegment[]> {
	return (await fetchEffortsForRunWithError(runId)).efforts;
}

/// Same as `fetchEffortsForRun` but surfaces the load error instead of
/// swallowing it to `[]` — so the panel can render a distinct error state
/// instead of sticking on "Checking segments…" forever. Mirrors the
/// `fetchRoutesWithError` convention.
export async function fetchEffortsForRunWithError(
	runId: string,
): Promise<{ efforts: SegmentEffortWithSegment[]; error: string | null }> {
	const { data: efforts, error } = await supabase
		.from(TABLES.segment_efforts)
		.select('*')
		.eq('run_id', runId);
	if (error) {
		console.error('fetchEffortsForRun failed', error);
		return { efforts: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	if (!efforts || efforts.length === 0) return { efforts: [], error: null };

	const segmentIds = Array.from(new Set(efforts.map((e) => e.segment_id)));
	const { data: segments } = await queryChunked(segmentIds, (part) =>
		supabase.from(TABLES.segments).select('*').in('id', part)
	);
	const bySeg = new Map<string, Segment>();
	for (const s of segments ?? []) bySeg.set(s.id, s as Segment);

	// Rank every effort in ONE round-trip via segment_effort_ranks (migration
	// 20261223_001) instead of a serial count-per-effort loop — a run over a
	// 30-segment route used to fire 30 sequential queries before the panel
	// rendered. rank = 1 + the distinct OTHER athletes holding a strictly-faster
	// visible, non-blocked effort — the per-athlete population the board this
	// chip links to ranks over (20270523_001, decisions §594), not a count of
	// effort rows. `supabase.rpc` RESOLVES with an error rather than throwing,
	// so a failure here leaves the map empty and every effort unranked; the
	// panel still shows the efforts (degraded, not blank) and each says so.
	// It must not say `#1` — see decisions §746.
	const { data: rankRows, error: rankErr } = await supabase.rpc('segment_effort_ranks', {
		p_run_id: runId,
	}, { get: true });
	if (rankErr) console.error('segment_effort_ranks failed', rankErr);
	const rankByEffort = readRankRows(rankRows);

	const out: SegmentEffortWithSegment[] = [];
	for (const e of efforts as SegmentEffort[]) {
		const segment = bySeg.get(e.segment_id);
		if (!segment) continue;
		out.push({
			effort: e,
			segment,
			rank: rankByEffort.get(e.id) ?? null,
		});
	}
	return { efforts: out, error: null };
}

/**
 * Client-side auto-effort generation for a run (decisions §37).
 *
 * Called from the run detail page on mount. Walks each route segment
 * over the run's track and inserts any new efforts. Existing efforts
 * are protected by the unique(segment_id, run_id) index — a duplicate
 * insert returns 23505 and we treat it as a no-op.
 *
 * Returns the count of new efforts written.
 */
export async function computeSegmentEffortsForRun(input: {
	run_id: string;
	user_id: string;
	route_id: string;
	track: { lat: number; lng: number; ts?: string }[];
}): Promise<number> {
	if (!input.track || input.track.length < 2) return 0;
	const userId = auth.user?.id;
	if (!userId || userId !== input.user_id) return 0;

	const segments = await fetchSegmentsForRoute(input.route_id);
	if (segments.length === 0) return 0;

	const { buildSegmentEffortRows } = await import('../segments/auto_segment_effort');
	const rows = buildSegmentEffortRows(segments, input.track as import('#lib/types.ts').TrackPoint[], {
		run_id: input.run_id,
		user_id: userId,
	});
	if (rows.length === 0) return 0;

	// One batched upsert instead of an insert-per-segment loop — a run over a
	// 30-segment route used to fire 30 serial round-trips on the run-detail
	// view. `ignoreDuplicates` (ON CONFLICT DO NOTHING on unique(segment_id,
	// run_id)) keeps the prior per-row 23505 idempotency: re-viewing a run
	// re-inserts nothing and the RETURNING set counts only newly-written rows.
	const { data: inserted, error } = await supabase
		.from(TABLES.segment_efforts)
		.upsert(rows, { onConflict: 'segment_id,run_id', ignoreDuplicates: true })
		.select('id');
	if (error) {
		console.warn('segment effort batch upsert failed', input.run_id, error);
		return 0;
	}
	return inserted?.length ?? 0;
}

// --- Global / famous-segment catalogue (decisions §232) ---

export interface GlobalSegment {
	id: string;
	name: string;
	description: string | null;
	waypoints: { lat: number; lng: number; ele?: number }[];
	distance_m: number;
	elevation_m: number | null;
	surface: string;
	region: string | null;
	country_code: string | null;
	is_active: boolean;
	created_at: string;
}

/// One `global_segments` row as the client's `GlobalSegment`. `waypoints` is a
/// jsonb column the generated row types `Json`, where this type promises a
/// line; a value that is not an array becomes `[]` rather than being asserted
/// through, the same rule `asRoute` follows for the same column shape.
function asGlobalSegment(
	row: Database['public']['Tables']['global_segments']['Row'],
): GlobalSegment {
	return {
		...row,
		waypoints: Array.isArray(row.waypoints)
			? (row.waypoints as unknown as GlobalSegment['waypoints'])
			: [],
	};
}

export interface GlobalSegmentEffort {
	id: string;
	global_segment_id: string;
	run_id: string;
	user_id: string;
	time_seconds: number;
	started_at: string;
	created_at: string;
}

export interface GlobalSegmentLeaderboardEntry {
	effort: GlobalSegmentEffort;
	athlete: PublicProfile;
	rank: number;
}

export interface GlobalSegmentEffortWithSegment {
	effort: GlobalSegmentEffort;
	segment: GlobalSegment;
	/** Null when the rank RPC did not answer for this effort — see
	 *  `segments/rank_pill.ts`. Absent is not `#1`. */
	rank: number | null;
}

export async function fetchGlobalSegments(
	limit = GLOBAL_SEGMENT_SCORING_LIMIT,
): Promise<GlobalSegment[]> {
	return (await fetchGlobalSegmentsWithError(limit)).segments;
}

/// Browse the catalogue. Region filtering is client-side (the curated v1
/// catalogue is small); this fetch just pulls the active rows. Surfaces the
/// error instead of swallowing to `[]` so the browse page can show a
/// distinct error state rather than a false "empty catalogue".
///
/// The default IS the catalogue bound, not a convenience number. It read 200
/// while the scoring sweep passed GLOBAL_SEGMENT_SCORING_LIMIT (500), so the
/// two callers of one function disagreed about what "the whole catalogue"
/// means and `/segments` dropped the alphabetical tail of any catalogue past
/// 200 rows — silently, which is the same false-incomplete-result the error
/// return above exists to prevent, one layer up.
export async function fetchGlobalSegmentsWithError(
	limit = GLOBAL_SEGMENT_SCORING_LIMIT,
): Promise<{ segments: GlobalSegment[]; error: string | null }> {
	const { data, error } = await supabase
		.from(TABLES.global_segments)
		.select('*')
		.eq('is_active', true)
		.order('name', { ascending: true })
		.limit(limit);
	if (error) {
		console.error('fetchGlobalSegments failed', error);
		return { segments: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	return { segments: (data ?? []).map(asGlobalSegment), error: null };
}

export async function fetchGlobalSegment(id: string): Promise<GlobalSegment | null> {
	const { data, error } = await supabase
		.from(TABLES.global_segments)
		.select('*')
		.eq('id', id)
		.eq('is_active', true)
		.maybeSingle();
	if (error) {
		console.error('fetchGlobalSegment failed', error);
		return null;
	}
	return data ? asGlobalSegment(data) : null;
}

/// Block-guarded global-segment leaderboard. Mirrors
/// `fetchSegmentLeaderboardTiered` but calls the catalogue RPC (no route
/// visibility branch — the catalogue is public; per-effort run privacy +
/// the block graph are applied server-side).
export async function fetchGlobalSegmentLeaderboard(
	segmentId: string,
	filter: {
		gender?: SegmentGenderFilter | null;
		ageBand?: SegmentAgeBand | null;
		clubId?: string | null;
	} = {},
	limit = 50,
): Promise<GlobalSegmentLeaderboardEntry[]> {
	const { data, error } = await supabase.rpc('global_segment_leaderboard', {
		p_segment_id: segmentId,
		p_gender: filter.gender ?? undefined,
		p_age_band: filter.ageBand ?? undefined,
		p_limit: limit,
		p_club_id: filter.clubId ?? undefined,
	}, { get: true });
	if (error || !data) {
		console.warn('fetchGlobalSegmentLeaderboard failed', error);
		return [];
	}
	const rows = data as Array<{
		effort_id: string;
		user_id: string;
		run_id: string;
		time_seconds: number;
		started_at: string;
		display_name: string | null;
		avatar_url: string | null;
		gender: string | null;
		age: number | null;
	}>;
	return assignCompetitionRanks(rows).map(({ row, rank }) => ({
		effort: {
			id: row.effort_id,
			global_segment_id: segmentId,
			run_id: row.run_id,
			user_id: row.user_id,
			time_seconds: row.time_seconds,
			started_at: row.started_at,
			created_at: row.started_at,
		} as GlobalSegmentEffort,
		athlete: { id: row.user_id, display_name: row.display_name, avatar_url: row.avatar_url },
		rank,
	}));
}

/// Backfill catalogue-segment efforts a run earned. Called from the
/// run-detail page on mount (owner only). Scores the run's track against
/// every active catalogue geometry via the pure `computeGlobalSegmentEffort`
/// (end-to-end match, curated v1) and batch-upserts matches. Idempotent via
/// unique(global_segment_id, run_id) + ignoreDuplicates. Returns new count.
///
/// The write-side upsert is idempotent, but the FETCH + client-side haversine
/// match are not — without a short-circuit they'd re-run on every owner view
/// forever (issue #333). A `runs.metadata.global_segments_scored_count` stamp
/// records the catalogue size a run was last scored against; a cheap `count`
/// query gates the expensive polyline fetch so a scored run only recomputes
/// when the (deliberately growing) catalogue gains segments. Both the gate
/// and the fetch are bounded by the shared GLOBAL_SEGMENT_SCORING_LIMIT —
/// see its doc comment for why a drift between the two is a pessimisation.
export async function computeGlobalSegmentEffortsForRun(input: {
	run_id: string;
	user_id: string;
	track: TrackPoint[];
}): Promise<number> {
	if (!input.track || input.track.length < 2) return 0;
	const userId = auth.user?.id;
	if (!userId || userId !== input.user_id) return 0;

	const [{ data: runRow }, { count: activeCount }] = await Promise.all([
		supabase.from(TABLES.runs).select('metadata').eq('id', input.run_id).maybeSingle(),
		supabase
			.from(TABLES.global_segments)
			.select('id', { count: 'exact', head: true })
			.eq('is_active', true),
	]);
	const runMetadata = (runRow?.metadata ?? null) as JsonObject | null;
	if (!shouldRescoreGlobalSegments(runMetadata, activeCount)) return 0;

	const { segments } = await fetchGlobalSegmentsWithError(GLOBAL_SEGMENT_SCORING_LIMIT);
	if (segments.length === 0) return 0;

	const { computeGlobalSegmentEfforts } = await import('../segments/segments');
	const rows: {
		global_segment_id: string;
		run_id: string;
		user_id: string;
		time_seconds: number;
		started_at: string;
	}[] = [];
	// One sweep over the catalogue rather than a call per segment: the track's
	// extent is then measured once and the (overwhelming) majority of segments,
	// which are nowhere near this run, are rejected without walking it.
	const efforts = computeGlobalSegmentEfforts(
		input.track,
		segments.map((seg) => ({
			points: (seg.waypoints ?? []).map((w) => ({ lat: Number(w.lat), lng: Number(w.lng) })),
			distance_m: Number(seg.distance_m),
		})),
	);
	for (let i = 0; i < segments.length; i++) {
		const eff = efforts[i];
		if (!eff) continue;
		rows.push({
			global_segment_id: segments[i].id,
			run_id: input.run_id,
			user_id: userId,
			time_seconds: eff.time_seconds,
			started_at: eff.started_at,
		});
	}
	let newCount = 0;
	if (rows.length > 0) {
		const { data: inserted, error } = await supabase
			.from(TABLES.global_segment_efforts)
			.upsert(rows, { onConflict: 'global_segment_id,run_id', ignoreDuplicates: true })
			.select('id');
		if (error) {
			// Don't stamp on a failed write — the run stays un-scored so
			// the next view retries rather than dropping real matches.
			console.warn('global segment effort batch upsert failed', input.run_id, error);
			return 0;
		}
		newCount = inserted?.length ?? 0;
	}

	// Stamp even when nothing matched (rows.length === 0): a no-match run
	// must not re-fetch + re-match the whole catalogue every view either.
	//
	// Re-read the bag here rather than merging into the copy read at the top
	// of the function: the catalogue fetch + haversine pass above takes
	// seconds, and `runs.metadata` is a whole-column jsonb write. Merging the
	// stale copy would silently revert any title / notes edit the owner made
	// inside that window — the run-detail edit dialog writes the same column.
	const { data: freshRow } = await supabase
		.from(TABLES.runs)
		.select('metadata')
		.eq('id', input.run_id)
		.maybeSingle();
	const next = stampGlobalSegmentsScored(
		(freshRow?.metadata ?? null) as JsonObject | null,
		segments.length,
	);
	const { error: stampErr } = await supabase
		.from(TABLES.runs)
		.update({ metadata: next })
		.eq('id', input.run_id);
	if (stampErr) console.warn('global segment scored stamp failed', input.run_id, stampErr);
	return newCount;
}

/// Catalogue-segment efforts a run earned, joined to the segment + ranked
/// in one round-trip via `global_segment_effort_ranks`. Mirrors
/// `fetchEffortsForRun` for the run-detail panel.
export async function fetchGlobalEffortsForRun(
	runId: string,
): Promise<GlobalSegmentEffortWithSegment[]> {
	const { data: efforts, error } = await supabase
		.from(TABLES.global_segment_efforts)
		.select('*')
		.eq('run_id', runId);
	if (error || !efforts || efforts.length === 0) return [];

	const segmentIds = Array.from(new Set(efforts.map((e) => e.global_segment_id)));
	const { data: segments } = await queryChunked(segmentIds, (part) =>
		supabase.from(TABLES.global_segments).select('*').in('id', part)
	);
	const bySeg = new Map<string, GlobalSegment>();
	for (const s of segments ?? []) bySeg.set(s.id, asGlobalSegment(s));

	// This one is reachable for a logged-out reader of a public run today:
	// `global_segment_effort_ranks` is granted to `authenticated` only while
	// both catalogue tables are readable by `anon` (20270512_001), so the rows
	// arrive and the ranks 42501. Unranked is the honest answer either way.
	const { data: rankRows, error: rankErr } = await supabase.rpc('global_segment_effort_ranks', {
		p_run_id: runId,
	}, { get: true });
	if (rankErr) console.error('global_segment_effort_ranks failed', rankErr);
	const rankByEffort = readRankRows(rankRows);

	const out: GlobalSegmentEffortWithSegment[] = [];
	for (const e of efforts as GlobalSegmentEffort[]) {
		const segment = bySeg.get(e.global_segment_id);
		if (!segment) continue;
		out.push({ effort: e, segment, rank: rankByEffort.get(e.id) ?? null });
	}
	return out;
}

// --- Notifications (decisions §38) ---

export interface NotificationRow {
	id: string;
	user_id: string;
	actor_id: string | null;
	kind: NotificationKind;
	run_id: string | null;
	comment_id: string | null;
	event_id: string | null;
	plan_id: string | null;
	club_id: string | null;
	achievement_id: string | null;
	challenge_id: string | null;
	read_at: string | null;
	refunded: boolean;
	created_at: string;
}

export interface NotificationView {
	row: NotificationRow;
	actor: PublicProfile | null;
	run_distance_m: number | null;
	run_started_at: string | null;
	comment_excerpt: string | null;
	event_title: string | null;
	event_club_slug: string | null;
	club_name: string | null;
	club_slug: string | null;
}

/**
 * Last `limit` notifications for the current user, joined to actor
 * profiles + small run/comment metadata so the UI can render
 * "Alice commented on your 8 km run" without follow-up queries.
 */
export async function fetchNotifications(limit = 50): Promise<NotificationView[]> {
	return (await fetchNotificationsWithError(limit)).notifications;
}

/// Same as `fetchNotifications` but surfaces the load error instead of
/// swallowing it to `[]` — so the inbox can render a distinct error state
/// rather than looking byte-for-byte like a genuinely empty inbox (a
/// broken inbox must not show "You have no notifications / Find people").
/// Mirrors the `fetchRoutesWithError` convention.
export async function fetchNotificationsWithError(
	limit = 50,
): Promise<{ notifications: NotificationView[]; error: string | null }> {
	const { data: rows, error } = await supabase
		.from(TABLES.notifications)
		.select('*')
		.order('created_at', { ascending: false })
		.limit(limit);
	if (error) {
		console.error('fetchNotifications failed', error);
		return { notifications: [], error: `${error.message}${error.code ? ` (${error.code})` : ''}` };
	}
	if (!rows || rows.length === 0) return { notifications: [], error: null };

	const actorIds = Array.from(new Set(rows.map((r) => r.actor_id).filter((x): x is string => !!x)));
	const runIds = Array.from(new Set(rows.map((r) => r.run_id).filter((x): x is string => !!x)));
	const commentIds = Array.from(new Set(rows.map((r) => r.comment_id).filter((x): x is string => !!x)));
	const eventIds = Array.from(new Set(rows.map((r) => (r as { event_id?: string | null }).event_id).filter((x): x is string => !!x)));
	const clubIds = Array.from(new Set(rows.map((r) => (r as { club_id?: string | null }).club_id).filter((x): x is string => !!x)));

	const [profiles, runs, publicRuns, comments, events, clubs] = await Promise.all([
		actorIds.length > 0
			? supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', actorIds)
			: Promise.resolve({ data: [] as PublicProfile[] }),
		// Two run reads: `runs` resolves the recipient's OWN runs
		// (kudos / comment / reply notifications, where the recipient is
		// the owner and the run may be private), and `public_runs`
		// resolves runs owned by someone else (run_completed, where the
		// recipient is a follower — the bare `runs` table has owner-only
		// SELECT since migration 20260701_001 so a follower read returns
		// nothing). Merged below; either source filling the distance.
		runIds.length > 0
			? supabase.from(TABLES.runs).select('id, distance_m, started_at').in('id', runIds)
			: Promise.resolve({ data: [] as { id: string; distance_m: number; started_at: string }[] }),
		runIds.length > 0
			? supabase.from('public_runs').select('id, distance_m, started_at').in('id', runIds)
			: Promise.resolve({ data: [] as { id: string; distance_m: number; started_at: string }[] }),
		commentIds.length > 0
			? supabase.from(TABLES.run_comments).select('id, body').in('id', commentIds)
			: Promise.resolve({ data: [] as { id: string; body: string }[] }),
		eventIds.length > 0
			? supabase.from('events').select('id, title, club_id, clubs(slug)').in('id', eventIds)
			: Promise.resolve({ data: [] as { id: string; title: string; clubs: { slug: string } | { slug: string }[] | null }[] }),
		clubIds.length > 0
			? supabase.from('clubs').select('id, name, slug').in('id', clubIds)
			: Promise.resolve({ data: [] as { id: string; name: string; slug: string }[] }),
	]);

	const profileBy = new Map<string, PublicProfile>();
	for (const p of (profiles.data ?? []) as PublicProfile[]) profileBy.set(p.id, p);
	const runBy = new Map<string, { distance_m: number; started_at: string }>();
	for (const r of (publicRuns.data ?? []) as { id: string; distance_m: number; started_at: string }[]) {
		runBy.set(r.id, { distance_m: r.distance_m, started_at: r.started_at });
	}
	// Owner-read overlays public — both carry the same columns; this just
	// fills any private run the public view omits.
	for (const r of (runs.data ?? []) as { id: string; distance_m: number; started_at: string }[]) {
		runBy.set(r.id, { distance_m: r.distance_m, started_at: r.started_at });
	}
	const commentBy = new Map<string, string>();
	for (const c of (comments.data ?? []) as { id: string; body: string }[]) {
		commentBy.set(c.id, c.body);
	}
	const eventBy = new Map<string, { title: string; club_slug: string | null }>();
	for (const e of (events.data ?? []) as { id: string; title: string; clubs: { slug: string } | { slug: string }[] | null }[]) {
		const club = singleEmbed(e.clubs);
		eventBy.set(e.id, { title: e.title, club_slug: club?.slug ?? null });
	}
	const clubBy = new Map<string, { name: string; slug: string }>();
	for (const c of (clubs.data ?? []) as { id: string; name: string; slug: string }[]) {
		clubBy.set(c.id, { name: c.name, slug: c.slug });
	}

	return {
		notifications: rows.map((row) => {
			const r = row as NotificationRow;
			const run = r.run_id ? runBy.get(r.run_id) ?? null : null;
			const body = r.comment_id ? commentBy.get(r.comment_id) ?? null : null;
			const ev = r.event_id ? eventBy.get(r.event_id) ?? null : null;
			const club = r.club_id ? clubBy.get(r.club_id) ?? null : null;
			return {
				row: r,
				actor: r.actor_id ? profileBy.get(r.actor_id) ?? null : null,
				run_distance_m: run?.distance_m ?? null,
				run_started_at: run?.started_at ?? null,
				comment_excerpt: body ? (body.length > 120 ? body.slice(0, 117) + '…' : body) : null,
				event_title: ev?.title ?? null,
				event_club_slug: ev?.club_slug ?? null,
				club_name: club?.name ?? null,
				club_slug: club?.slug ?? null,
			};
		}),
		error: null,
	};
}

export async function fetchUnreadNotificationCount(): Promise<number> {
	const { count, error } = await supabase
		.from(TABLES.notifications)
		.select('*', { count: 'exact', head: true })
		.is('read_at', null);
	if (error) {
		console.error('fetchUnreadNotificationCount failed', error);
		return 0;
	}
	return count ?? 0;
}

export async function markNotificationRead(id: string): Promise<void> {
	const { error } = await supabase
		.from(TABLES.notifications)
		.update({ read_at: new Date().toISOString() })
		.eq('id', id)
		.is('read_at', null);
	if (error) throw dbError(error);
}

export async function markAllNotificationsRead(): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) return;
	const { error } = await supabase
		.from(TABLES.notifications)
		.update({ read_at: new Date().toISOString() })
		.eq('user_id', userId)
		.is('read_at', null);
	if (error) throw dbError(error);
}

// Dismissing a group is ONE intent, so it is one statement in one
// transaction. An `in` filter rides the request URL, which leaves a large
// dismiss at the mercy of the gateway's request-line budget (decisions
// § 653), and chunking to dodge that only trades the failure for a partial
// dismiss the spent undo offer can no longer take back. The RPC takes the
// array in the POST body and refuses past its own cap rather than truncating.
export async function deleteNotifications(ids: string[]): Promise<void> {
	if (ids.length === 0) return;
	const { error } = await supabase.rpc('delete_notifications', { p_ids: ids });
	if (error) throw dbError(error);
}

// ─────────────────────── User reports ───────────────────────
//
// Submit a report against a user / club / route. The server-side
// `submit_report` SECURITY DEFINER RPC validates the target exists,
// rejects self-reports, rate-limits at 10/hour, and raises 23505 if
// the same reporter already has a pending report against the same
// target. See migration 20260908_001.

export type ReportReason =
	| 'spam'
	| 'harassment'
	| 'inappropriate'
	| 'impersonation'
	| 'other';

// The two RESOLVED statuses of `reports.status`. `pending` is the column's
// third value and the default every report is inserted with, so the moderation
// queue never writes it — the vocabulary here is deliberately the resolution
// half (check_constraint_unions.mjs carries the exemption).
export type ReportResolution = 'reviewed' | 'dismissed';

export async function submitReport(input: {
	targetKind: ReportTargetKind;
	targetId: string;
	reason: ReportReason;
	notes?: string;
}): Promise<string> {
	const { data, error } = await supabase.rpc('submit_report', {
		p_target_kind: input.targetKind,
		p_target_id: input.targetId,
		p_reason: input.reason,
		p_notes: input.notes?.trim() || null,
	});
	if (error) {
		// Normalise the load-bearing failure modes into caller-
		// friendly messages. The PostgREST envelope surfaces the
		// SQLSTATE / hint exactly as raised in the migration; we
		// don't lean on the raw text because that string can change.
		if (isDuplicateKeyError(error)) {
			throw new Error('You already have a pending report against this content.');
		}
		// The `create_report` bucket goes through the same
		// enforce_create_rate_limit trigger as create_club + create_route,
		// so the shared helper recognises the message + emits a
		// consistent "filing reports too quickly — please wait N minutes"
		// rather than this function carrying its own copy of the
		// translation rule.
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data as string;
}

// ─────────────────────── Direct messages (#55) ───────────────────────

export interface DirectMessage {
	id: string;
	sender_id: string;
	/// Null once the recipient deleted their account (migration
	/// 20271021000003): the remaining sender keeps the message, and
	/// `deleted_partner_key` names the conversation instead.
	recipient_id: string | null;
	/// Null once the sender unsent it (`unsent_at` set).
	body: string | null;
	created_at: string;
	read_at: string | null;
	/// Typed route attachment (migration 20270619_001). Null on an ordinary
	/// message. What the reader is allowed to SEE of the route it names is
	/// decided at read time by [fetchRouteById], never by holding this id.
	route_id: string | null;
	unsent_at: string | null;
	deleted_partner_key: string | null;
}

export interface DmThread {
	/// Null when the partner deleted their account; the thread is then keyed
	/// on `deletedPartnerKey` and holds only the viewer's own messages.
	partnerId: string | null;
	deletedPartnerKey: string | null;
	partnerName: string | null;
	partnerAvatar: string | null;
	/// Null when the latest message was unsent (`lastUnsent`).
	lastBody: string | null;
	lastUnsent: boolean;
	lastAt: string;
	lastFromMe: boolean;
	unread: number;
}

/// The newest message of the runner's current (not archived) Coach
/// conversations, for the AI Coach row in the Messages inbox (decisions
/// § 2227). Owner-only by RLS. The caller reads it only once the runner has
/// consented to the Coach; throws on a failed read so the row can say nothing
/// rather than claim there is no conversation.
export interface LatestCoachMessage {
	planId: string | null;
	role: 'user' | 'assistant';
	content: string;
	createdAt: string;
}

export async function fetchLatestCoachMessage(): Promise<LatestCoachMessage | null> {
	const me = auth.user?.id;
	if (!me) return null;
	const { data, error } = await supabase
		.from('coach_messages')
		.select('plan_id, role, content, created_at')
		.eq('user_id', me)
		.is('archived_at', null)
		.order('created_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (error) throw dbError(error);
	if (!data) return null;
	return {
		planId: data.plan_id,
		role: data.role === 'user' ? 'user' : 'assistant',
		content: data.content,
		createdAt: data.created_at,
	};
}

/// Total unread direct messages across every conversation: the badge on the
/// sidebar's Messages entry. The same `dm_threads()` aggregation as
/// [fetchDmThreads] without its partner-profile read, as mobile's
/// `ApiClient.fetchUnreadDmCount` does. Throws on a failed read, so the store
/// keeps the last count rather than reading a blip as "nothing unread".
export async function fetchUnreadDmCount(): Promise<number> {
	if (!auth.user?.id) return 0;
	const { data, error } = await supabase.rpc('dm_threads', undefined, { get: true });
	if (error) throw new Error(`dm_threads failed: ${error.message}`);
	return (data ?? []).reduce((total, r) => total + (Number(r.unread) || 0), 0);
}

/// Conversation list: the latest message per partner + an unread count.
/// Aggregated server-side by the dm_threads() RPC (DISTINCT ON partner +
/// unread COUNT over the viewer's ENTIRE message set) — one preview row per
/// conversation instead of pulling the newest 500 full message bodies and
/// folding them in JS (which over-fetched AND silently dropped older partners
/// once a heavy inbox's newest 500 messages spanned fewer conversations than
/// it had). Partner name/avatar is a chunked `in` profile lookup, since the
/// partner set has no ceiling of its own.
export async function fetchDmThreads(): Promise<DmThread[]> {
	const me = auth.user?.id;
	if (!me) return [];
	const { data, error } = await supabase.rpc('dm_threads', undefined, { get: true });
	// Throw rather than returning [] — the caller can't tell a transient
	// RPC failure from a genuinely empty inbox, and rendering "no
	// conversations" on a blip strands the user until a manual reload.
	if (error) throw new Error(`dm_threads failed: ${error.message}`);
	if (!data) return [];
	// The generator types every RETURNS TABLE column as non-null; partner_id,
	// deleted_partner_key and last_body are each null in one case (a deleted
	// partner, a live partner, an unsent message).
	const threads: DmThread[] = (data as {
		partner_id: string | null;
		deleted_partner_key: string | null;
		last_body: string | null;
		last_unsent: boolean;
		last_at: string;
		last_from_me: boolean;
		unread: number;
	}[]).map((r) => ({
		partnerId: r.partner_id,
		deletedPartnerKey: r.deleted_partner_key,
		partnerName: null,
		partnerAvatar: null,
		lastBody: r.last_body,
		lastUnsent: r.last_unsent === true,
		lastAt: r.last_at,
		lastFromMe: r.last_from_me,
		unread: Number(r.unread) || 0,
	}));
	const byPartner = new Map(
		threads.flatMap((t) => (t.partnerId ? [[t.partnerId, t] as const] : [])),
	);
	const partnerIds = [...byPartner.keys()];
	if (partnerIds.length > 0) {
		const { data: profiles } = await queryChunked(partnerIds, (part) =>
			supabase.from('user_profiles').select('id, display_name, avatar_url').in('id', part)
		);
		for (const p of profiles ?? []) {
			const t = byPartner.get(p.id as string);
			if (t) {
				t.partnerName = (p.display_name as string | null) ?? null;
				t.partnerAvatar = (p.avatar_url as string | null) ?? null;
			}
		}
	}
	// The RPC already orders newest-conversation-first; the profile merge
	// mutates the rows in place, so that order is kept.
	return threads;
}

/// One page of a conversation, oldest message first. A partner thread is both
/// directions between the viewer and the partner; a deleted-partner thread is
/// the viewer's own messages under that partner's key, since the leaver's
/// side was erased with their account.
///
/// Keyset-paged from the newest end on `(created_at, id)`: `before` is the
/// oldest message already shown, and the page holds the `limit` messages before
/// it, so the first read is the current end of the conversation however long
/// it is. Mirrors mobile's `fetchDmThread`. The pair is matched as both columns
/// IN the two ids, which with the table's `sender_id <> recipient_id` CHECK is
/// exactly the two directions of this conversation, and leaves the `or` tree
/// to the keyset. Throws on a failed read.
export async function fetchDmThread(
	target: DmThreadTarget,
	opts: { before?: DmOrderKey; limit?: number } = {},
): Promise<DmPage<DirectMessage>> {
	const me = auth.user?.id;
	if (!me) return { messages: [], hasMore: false };
	const limit = opts.limit ?? DM_THREAD_PAGE_SIZE;
	let query = supabase.from(TABLES.direct_messages).select('*');
	if (target.kind === 'deleted') {
		query = query.eq('sender_id', me).eq('deleted_partner_key', target.deletedPartnerKey);
	} else {
		const pair = [me, target.partnerId];
		query = query.in('sender_id', pair).in('recipient_id', pair);
	}
	if (opts.before) query = query.or(dmPageBeforeFilter(opts.before));
	for (const k of DM_THREAD_ORDER) {
		query = query.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
	}
	const { data, error } = await query.limit(limit + 1);
	// Throw rather than returning an empty page: the caller can't tell a
	// transient failure (network blip, RLS denial, dead session) from a
	// genuinely empty conversation.
	if (error) throw new Error(`fetchDmThread failed: ${error.message}`);
	return dmPageFromRows((data ?? []) as DirectMessage[], limit);
}

/// Send a message. RLS enforces the no-block + follow-graph gate; a
/// 42501 surfaces as a friendly "can't message this person" error, and
/// the rail's two send buckets (migration 20270608_001) raise the same
/// P0001 every other create-rate-limit does, so they go through the
/// shared parser rather than reaching a composer as a raw exception.
///
/// `routeId` attaches a route to the message (route_direct_share.md v2).
/// The same INSERT policy also refuses an attachment the SENDER cannot see
/// (migration 20270619_001), which surfaces through the same 42501 branch.
export async function sendDm(
	recipientId: string,
	body: string,
	routeId?: string,
): Promise<DirectMessage> {
	const me = auth.user?.id;
	if (!me) throw new Error('Not signed in');
	const trimmed = body.trim();
	if (!trimmed) throw new Error('Message is empty');
	const { data, error } = await supabase
		.from(TABLES.direct_messages)
		.insert({
			sender_id: me,
			recipient_id: recipientId,
			body: trimmed,
			route_id: routeId?.trim() || null,
		})
		.select('*')
		.single();
	if (error || !data) {
		if (error?.code === '42501') {
			throw new Error(m('messages.sendNotAllowed'));
		}
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw error ? dbError(error) : new Error('Send failed');
	}
	return data as DirectMessage;
}

/// Unsend one of the viewer's own messages: the server nulls its body and
/// attachment and stamps `unsent_at`, so both sides see a placeholder
/// (migration 20271021000003). Not reversible. Returns the updated row; a
/// message the viewer did not send answers P0002, which reaches the caller as
/// an error rather than a silent no-op.
export async function unsendDm(messageId: string): Promise<DirectMessage> {
	const { data, error } = await supabase.rpc('unsend_direct_message', {
		p_message_id: messageId,
	});
	if (error || !data) throw error ? dbError(error) : new Error('Unsend failed');
	return data as DirectMessage;
}

/// Marks the partner's unread messages read up to and including `through`, the
/// newest one on screen (created_at, then id, the thread's own order). A reply
/// that lands after the thread was read stays unread until it is shown.
export async function markDmThreadRead(
	otherId: string,
	through: Pick<DirectMessage, 'id' | 'created_at'>,
): Promise<void> {
	const me = auth.user?.id;
	if (!me) return;
	const at = through.created_at;
	const { error } = await supabase
		.from(TABLES.direct_messages)
		.update({ read_at: new Date().toISOString() })
		.eq('sender_id', otherId)
		.eq('recipient_id', me)
		.is('read_at', null)
		.or(`created_at.lt."${at}",and(created_at.eq."${at}",id.lte.${through.id})`);
	if (error) throw dbError(error);
}

// --- Coach-athlete roster (persona #46) -------------------------------------
//
// A coach mints a shareable invite token (createCoachInvite); the athlete
// redeems it (redeemCoachInvite -> redeem_coach_invite RPC) to form an active
// link. RLS scopes every read/write to the two parties. Profiles are joined in
// a second query, mirroring the club-member fetch pattern above.

export interface CoachAthleteLink {
	id: string;
	status: CoachAthleteStatus;
	note: string | null;
	created_at: string;
	accepted_at: string | null;
	/// The athlete on a coach's roster, or the coach on an athlete's list.
	user_id: string;
	display_name: string | null;
	avatar_url: string | null;
}

export interface PendingCoachInvite {
	id: string;
	invite_token: string;
	note: string | null;
	created_at: string;
}

/// Mint a pending invite. The token is client-generated (122-bit UUID); only
/// the coach can read their own pending rows (RLS), so it never needs the
/// column-grant lockdown clubs use. Returns the token so the caller can build
/// the /coaching/accept/<token> share link.
export async function createCoachInvite(note?: string): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const token = crypto.randomUUID().replace(/-/g, '');
	const { error } = await supabase.from(TABLES.coach_athletes).insert({
		coach_id: userId,
		status: 'pending',
		invite_token: token,
		note: note?.trim() || null
	});
	if (error) throw dbError(error);
	return token;
}

/// Active athletes on the signed-in coach's roster, newest acceptance first.
/// Same as `fetchMyAthletes` but surfaces the roster-query error so a
/// caller can show a "couldn't load — retry" state instead of an empty
/// roster that's indistinguishable from "no athletes yet". The profile
/// enrichment stays best-effort (a missing display name isn't a load
/// failure). Mirrors the `fetchRoutesWithError` convention.
export async function fetchMyAthletesWithError(): Promise<{
	athletes: CoachAthleteLink[];
	error: string | null;
}> {
	const userId = auth.user?.id;
	if (!userId) return { athletes: [], error: null };
	const { data: rows, error } = await supabase
		.from(TABLES.coach_athletes)
		.select('id, status, note, created_at, accepted_at, athlete_id')
		.eq('coach_id', userId)
		.eq('status', 'active')
		.order('accepted_at', { ascending: false });
	if (error) return { athletes: [], error: error.message };
	if (!rows || rows.length === 0) return { athletes: [], error: null };
	const ids = (rows as { athlete_id: string }[]).map((r) => r.athlete_id);
	const byId = await fetchProfilesByIds(ids);
	return {
		athletes: (rows as Array<Record<string, unknown>>).map((r) => ({
			id: r.id as string,
			status: r.status as CoachAthleteStatus,
			note: (r.note as string | null) ?? null,
			created_at: r.created_at as string,
			accepted_at: (r.accepted_at as string | null) ?? null,
			user_id: r.athlete_id as string,
			display_name: byId.get(r.athlete_id as string)?.display_name ?? null,
			avatar_url: byId.get(r.athlete_id as string)?.avatar_url ?? null
		})),
		error: null
	};
}

export async function fetchMyAthletes(): Promise<CoachAthleteLink[]> {
	return (await fetchMyAthletesWithError()).athletes;
}

/// True when the signed-in viewer actively coaches [athleteId]: the test the
/// coach RLS policies on plan_workouts run (`private.is_active_coach_of`), so
/// a surface can offer an edit only where the write will be allowed.
export async function isActiveCoachOf(athleteId: string): Promise<boolean> {
	const userId = auth.user?.id;
	if (!userId || userId === athleteId) return false;
	const { data, error } = await supabase
		.from(TABLES.coach_athletes)
		.select('id')
		.eq('coach_id', userId)
		.eq('athlete_id', athleteId)
		.eq('status', 'active')
		.limit(1);
	if (error) throw dbError(error);
	return (data ?? []).length > 0;
}

/// One row of the multi-athlete coach roster (coach_roster.md). The shape is
/// the bespoke `coach_roster_summary` RPC projection — NOT a base-table row —
/// so it lives here next to CoachAthleteLink rather than as a types.ts overlay.
/// load_acute / load_chronic are RAW distance-proxy stress sums; the page
/// derives the ACWR risk band + load trend from them via the coach_load helper
/// (the risk policy stays in one place, never in the SQL).
export interface CoachRosterRow {
	athlete_id: string;
	display_name: string | null;
	avatar_url: string | null;
	last_run_at: string | null;
	runs_7d: number;
	distance_7d_m: number;
	load_acute: number;
	load_chronic: number;
	active_plan_id: string | null;
	plan_completion_pct: number;
	/// The athlete's local date, the `today` the miss count is derived against.
	athlete_today: string | null;
	/// The current plan's non-rest workouts over the last 28 local days.
	recent_workouts: RosterRecentWorkout[];
	/// Easy-run efficiency drift, per cent. Null without health-data consent
	/// or too few runs to compare (decisions § 2092).
	easy_hr_drift_pct: number | null;
}

/// The whole roster in one consent-gated round-trip. Surfaces the RPC error so
/// the page can show a retry state distinct from "no athletes yet" — the
/// durable shape, mirroring fetchMyAthletesWithError. Returns no athlete data
/// to a non-coach (the RPC's `mine` CTE yields zero rows; an unauthenticated
/// caller raises, which surfaces as an error here, fail-closed).
export async function fetchCoachRosterSummaryWithError(): Promise<{
	rows: CoachRosterRow[];
	error: string | null;
}> {
	if (!auth.user?.id) return { rows: [], error: null };
	const { data, error } = await supabase.rpc('coach_roster_summary', undefined, { get: true });
	if (error) return { rows: [], error: error.message };
	const rows: CoachRosterRow[] = ((data as Array<Record<string, unknown>>) ?? []).map((r) => ({
		athlete_id: r.athlete_id as string,
		display_name: (r.display_name as string | null) ?? null,
		avatar_url: (r.avatar_url as string | null) ?? null,
		last_run_at: (r.last_run_at as string | null) ?? null,
		runs_7d: Number(r.runs_7d) || 0,
		distance_7d_m: Number(r.distance_7d_m) || 0,
		load_acute: Number(r.load_acute) || 0,
		load_chronic: Number(r.load_chronic) || 0,
		active_plan_id: (r.active_plan_id as string | null) ?? null,
		plan_completion_pct: Number(r.plan_completion_pct) || 0,
		athlete_today: typeof r.athlete_today === 'string' ? r.athlete_today : null,
		recent_workouts: parseRosterRecentWorkouts(r.recent_workouts),
		easy_hr_drift_pct:
			typeof r.easy_hr_drift_pct === 'number' && Number.isFinite(r.easy_hr_drift_pct)
				? r.easy_hr_drift_pct
				: null
	}));
	return { rows, error: null };
}

export async function fetchCoachRosterSummary(): Promise<CoachRosterRow[]> {
	return (await fetchCoachRosterSummaryWithError()).rows;
}

/// One athlete's recent runs for the coach review surface
/// (`/coaching/athletes/[id]`). The RLS policy `active coach reads
/// athlete runs` (migration 20261103_001) grants a `status='active'`
/// coach SELECT on the athlete's run rows — public AND private —
/// straight off the base table, so the explicit `user_id` filter here
/// is the *athlete*, not the caller. Column-narrowed: no track
/// download (the raw GPS trace stays owner-only — decisions § 98).
/// Returns [] when the caller isn't an active coach of `athleteId`
/// (RLS simply yields zero rows — no error).
export interface AthleteRunSummary {
	id: string;
	started_at: string;
	distance_m: number;
	duration_s: number;
	is_public: boolean;
	source: RunSource;
	route_id: string | null;
	activity_type: string;
	metadata: Record<string, unknown> | null;
	/// Whether the run carries a GPS track. Only the fact: the path is not
	/// kept, and the coach's map is served clipped by `clip-public-track`
	/// (decisions § 1968), never read from Storage.
	has_track: boolean;
}

export async function fetchAthleteRuns(
	athleteId: string,
	limit = 20
): Promise<AthleteRunSummary[]> {
	if (!auth.user?.id || !athleteId) return [];
	const { data, error } = await supabase
		.from(TABLES.runs)
		.select('id, started_at, distance_m, duration_s, is_public, source, route_id, activity_type, metadata, track_url')
		.eq('user_id', athleteId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (error || !data) return [];
	return (data as Array<Record<string, unknown>>).map((r) => ({
		id: r.id as string,
		started_at: r.started_at as string,
		distance_m: r.distance_m as number,
		duration_s: r.duration_s as number,
		is_public: (r.is_public as boolean) ?? false,
		source: parseRunSource(r.source as string | null),
		route_id: (r.route_id as string | null) ?? null,
		activity_type: (r.activity_type as string | null) ?? 'run',
		metadata: (r.metadata as Record<string, unknown> | null) ?? null,
		has_track: r.track_url != null,
	}));
}

/// Whether a linked coach is served the athlete's clipped run map (the
/// server's `coach_run_map` flag, decisions § 1968). Fail-closed: a read
/// failure is "off" and is not cached, so a later mount can find out.
let coachRunMapProbe: Promise<boolean> | null = null;
export function coachRunMapEnabled(): Promise<boolean> {
	if (coachRunMapProbe) return coachRunMapProbe;
	const probe = (async () => {
		try {
			const { data, error } = await supabase.rpc('coach_run_map_enabled', undefined, { get: true });
			if (error) {
				coachRunMapProbe = null;
				return false;
			}
			return data === true;
		} catch {
			coachRunMapProbe = null;
			return false;
		}
	})();
	coachRunMapProbe = probe;
	return probe;
}

/// The athlete's active training plan + per-workout compliance for the
/// coach review surface. Mirrors [fetchActivePlanOverview] but scoped
/// to `athleteId` — the coach plan-read policies (migration
/// 20261116_001) grant SELECT on `training_plans` / `plan_weeks` /
/// `plan_workouts` for active-linked athletes. Null when the athlete
/// has no active plan, or the caller isn't their active coach (RLS
/// yields no rows).
export async function fetchAthletePlanOverview(athleteId: string): Promise<PlanOverviewRead> {
	if (!auth.user?.id || !athleteId) return { overview: null, error: null };
	return planOverviewFor(athleteId);
}

/// Assigns a coach's plan to a linked athlete via the assign_plan_to_athlete
/// RPC (migration 20270106_001). An overlap with one of the athlete's active
/// plans throws a PlanOverlapError (23P01, migration 20270830000008), which the
/// coaching page turns into "pick a start date after it ends"; any other
/// refusal carries the RPC's raise text.
export async function assignPlanToAthlete(
	sourcePlanId: string,
	athleteId: string,
	startDate: string
): Promise<string> {
	const { data, error } = await supabase.rpc('assign_plan_to_athlete', {
		p_source_plan_id: sourcePlanId,
		p_athlete_id: athleteId,
		p_start_date: startDate
	});
	if (error) throw dbError(error);
	return data as string;
}

/// Unredeemed invites the signed-in coach has minted.
export async function fetchPendingCoachInvites(): Promise<PendingCoachInvite[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data } = await supabase
		.from(TABLES.coach_athletes)
		.select('id, invite_token, note, created_at')
		.eq('coach_id', userId)
		.eq('status', 'pending')
		.is('athlete_id', null)
		.order('created_at', { ascending: false });
	return (data as PendingCoachInvite[]) ?? [];
}

/// Active coaches the signed-in athlete is linked to.
export async function fetchMyCoaches(): Promise<CoachAthleteLink[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data: rows } = await supabase
		.from(TABLES.coach_athletes)
		.select('id, status, note, created_at, accepted_at, coach_id')
		.eq('athlete_id', userId)
		.eq('status', 'active')
		.order('accepted_at', { ascending: false });
	if (!rows || rows.length === 0) return [];
	const ids = (rows as { coach_id: string }[]).map((r) => r.coach_id);
	const byId = await fetchProfilesByIds(ids);
	return (rows as Array<Record<string, unknown>>).map((r) => ({
		id: r.id as string,
		status: r.status as CoachAthleteStatus,
		note: (r.note as string | null) ?? null,
		created_at: r.created_at as string,
		accepted_at: (r.accepted_at as string | null) ?? null,
		user_id: r.coach_id as string,
		display_name: byId.get(r.coach_id as string)?.display_name ?? null,
		avatar_url: byId.get(r.coach_id as string)?.avatar_url ?? null
	}));
}

/// Redeem an invite token. Returns the coach's user id.
export async function redeemCoachInvite(token: string): Promise<string> {
	const { data, error } = await supabase.rpc('redeem_coach_invite', { token });
	if (error) throw dbError(error);
	return data as string;
}

/// End an active link (either party may call). Goes through the end_coach_link
/// RPC, not a direct UPDATE: coach_athletes has no client UPDATE policy, so a
/// coach can't reassign athlete_id to forge a link. Soft-ends via status so the
/// row and its acceptance history survive for audit.
export async function endCoachLink(id: string): Promise<void> {
	const { error } = await supabase.rpc('end_coach_link', { p_id: id });
	if (error) throw dbError(error);
}

/// Revoke (hard-delete) an unredeemed invite. RLS only permits this on the
/// coach's own pending, athlete-less rows.
export async function revokeCoachInvite(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.coach_athletes).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Gym (Phase 4 multi-modal, decisions §63; spec docs/features/multi_modal.md) ---
//
// A gym session is a `gym_workouts` parent with N ordered `gym_sets`
// children. Mirrors the api_client Dart methods (createGymWorkout /
// fetchGymWorkoutWithSets / ...). last_modified_at is client-stamped for
// the same newer-wins reconciliation runs + gear use — there is no server
// updated_at trigger (migration 20261204_001).

export interface GymWorkout {
	id: string;
	user_id: string;
	title: string | null;
	started_at: string;
	duration_s: number | null;
	notes: string | null;
	is_public: boolean;
	external_id: string | null;
	last_modified_at: string;
	created_at: string;
	/// Schemaless bag (migration 20270101_001) holding the guided-runner
	/// execution trio and, while a session is in flight, the
	/// `gym_session_draft` snapshot. Registered in docs/backend/metadata.md.
	metadata: JsonObject | null;
	/// Trigger-maintained totals over the workout's sets (migration
	/// 20261214_001, contract in docs/backend/derived_state.md) — the list row
	/// reads them off the row rather than summing raw sets client-side.
	set_count: number;
	volume_kg: number;
}

export interface GymSet {
	id: string;
	workout_id: string;
	set_index: number;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	/// Role this set played (warmup / working / dropset / amrap / failure /
	/// backoff); defaults to 'working' (migration 20270224_001). Shares the
	/// gym_routine_sets.set_type vocabulary — GymSetType.
	set_type: GymSetType;
	/// Optional hold/interval time in seconds for timed work (planks, holds);
	/// null for rep/load-only sets (migration 20270101_001).
	duration_s: number | null;
	/// Optional link to a public.exercises catalogue entry (migration
	/// 20270222_001). null = a free-text set (the default). exercise_name is
	/// always present regardless — the link is provenance, not the PR key.
	exercise_id: string | null;
}

export interface GymWorkoutWithSets {
	workout: GymWorkout;
	sets: GymSet[];
}

export interface GymSetInput {
	exercise_name: string;
	reps?: number | null;
	weight_kg?: number | null;
	rpe?: number | null;
	/// Set role; omit to default to 'working' (migration 20270224_001).
	set_type?: GymSetType | null;
	duration_s?: number | null;
	/// Optional catalogue link (migration 20270222_001). Omit / null for a
	/// free-text set; the editor resolves it by matching the typed name against
	/// the catalogue at save time.
	exercise_id?: string | null;
}

/// One row per historical set, joined to its workout's start time, for
/// client-side PR computation (gym_prs.ts). Owner-scoped by RLS. Fine at
/// individual-user scale; see multi_modal.md § "activities view at scale".
export interface GymSetWithDate {
	workout_id: string;
	started_at: string;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	duration_s: number | null;
	/// gym_sets.set_type — the role the set played. Carried on every history
	/// read because the progression prescriber excludes a warmup by reading
	/// exactly this column; a reader that drops it hands the prescriber a
	/// ramp-up that looks like a working set (migration 20270525_001).
	/// Nullable at this boundary only — the column is NOT NULL DEFAULT
	/// 'working', and `gym_progression` resolves an absent value to 'working'.
	set_type: string | null;
}

/// PostgREST renders a `numeric` column as a JSON number or a string depending
/// on its magnitude, so every numeric the gym reads is coerced on the way in.
function numericOrZero(v: unknown): number {
	const n = typeof v === 'string' ? Number(v) : v;
	return typeof n === 'number' && Number.isFinite(n) ? n : 0;
}

export interface FetchGymWorkoutsOptions {
	/** Cap the number of rows returned. */
	limit?: number;
	/** Inclusive lower bound on `started_at`, as an ISO instant. */
	startedAtFrom?: string;
	/** Exclusive upper bound on `started_at`, as an ISO instant. */
	startedAtBefore?: string;
}

/// Newest gym workouts when unbounded; the window's workouts when
/// `startedAtFrom` / `startedAtBefore` are given — the same two bounds
/// `fetchRuns` takes, compared by PostgREST as real timestamptz values.
/// A caller that wants one calendar day must window rather than pull the
/// newest N and filter: a day older than the caller's N most recent sessions
/// would otherwise read as a day with no lifts in it.
///
/// Surfaces the error so the /gym list can show a "couldn't load — retry" state
/// instead of the empty "log your first workout" card (a real failure otherwise
/// reads as a brand-new lifter whose history vanished). Mirrors the
/// `fetchExerciseRecordsWithError` convention.
export async function fetchGymWorkoutsWithError(
	opts?: FetchGymWorkoutsOptions,
): Promise<{ workouts: GymWorkout[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { workouts: [], error: null };
	let q = supabase.from(TABLES.gym_workouts).select('*').eq('user_id', userId);
	if (opts?.startedAtFrom != null) q = q.gte('started_at', opts.startedAtFrom);
	if (opts?.startedAtBefore != null) q = q.lt('started_at', opts.startedAtBefore);
	const { data, error } = await q
		.order('started_at', { ascending: false })
		.limit(opts?.limit ?? 50);
	if (error) return { workouts: [], error: error.message };
	const workouts = ((data ?? []) as GymWorkout[]).map((w) => ({
		...w,
		set_count: numericOrZero(w.set_count),
		volume_kg: numericOrZero(w.volume_kg),
	}));
	return { workouts, error: null };
}

/// Gym workouts for the signed-in user, newest first. See
/// `fetchGymWorkoutsWithError` for the window.
export async function fetchGymWorkouts(opts?: FetchGymWorkoutsOptions): Promise<GymWorkout[]> {
	return (await fetchGymWorkoutsWithError(opts)).workouts;
}

/// Whether the user has ever logged a gym session (`gym`) or a food entry
/// (`nutrition`): the data half of `modalityShown`. Reads at most one row, so
/// it costs the same for a lifter with years of sessions as for none. Throws
/// on a failed read, because the caller must not mistake an outage for "no
/// data" and hide a modality the runner uses.
export async function fetchModalityHasData(userId: string, modality: Modality): Promise<boolean> {
	const { data, error } =
		modality === 'gym'
			? await supabase.from(TABLES.gym_workouts).select('id').eq('user_id', userId).limit(1)
			: await supabase.from(TABLES.food_log).select('id').eq('user_id', userId).limit(1);
	if (error) throw new Error(error.message);
	return (data?.length ?? 0) > 0;
}

/// The two per-workout values the /gym list needs that no column carries:
/// whether the workout set a personal record, and how many distinct exercises
/// it contained.
export interface GymWorkoutSummary {
	workoutId: string;
	exerciseCount: number;
	isPr: boolean;
}

/// Per-workout PR flags + exercise counts for the /gym list, aggregated by the
/// `gym_workout_summaries` RPC (migration 20270510_001).
///
/// /gym used to answer both questions in the browser from every gym_sets row
/// the account held — an unbounded read PostgREST truncates at 1000 rows, so
/// past ~40 sessions the badges and counts were quietly computed from a
/// partial, unordered history. A PR badge is an all-time question, so no
/// client-side window could fix it; the aggregation had to move to SQL, the
/// way gym_exercise_records + gym_exercise_names already did for /gym/records
/// and the composer autocomplete. `gym_prs.ts` remains the definition of a PR
/// — the RPC mirrors it, and the two are pinned against one fixture by
/// gym_workout_summaries.test.ts + gym_workout_summaries_test.sql.
///
/// Surfaces the error like `fetchGymWorkoutsWithError`: an empty result on a
/// failed read would silently strip every badge and show 0 exercises a row.
export async function fetchGymWorkoutSummariesWithError(
	limit = 100,
): Promise<{ summaries: GymWorkoutSummary[]; error: string | null }> {
	if (!auth.user?.id) return { summaries: [], error: null };
	const { data, error } = await supabase.rpc('gym_workout_summaries', { p_limit: limit }, { get: true });
	if (error) return { summaries: [], error: error.message };
	const rows = (data ?? []) as Array<{
		workout_id: string;
		exercise_count: number | string | null;
		is_pr: boolean | null;
	}>;
	return {
		summaries: rows.map((r) => ({
			workoutId: r.workout_id,
			exerciseCount: numericOrZero(r.exercise_count),
			isPr: r.is_pr === true,
		})),
		error: null,
	};
}

/// Has the user ever logged a set carrying a positive weight? Gates the
/// /gym/records link, which only surfaces weighted exercises. All-time, so a
/// lifter whose last weighted session predates the list page still gets the
/// link. Degrades to false (link hidden) on a failed read.
export async function fetchGymHasWeightedSets(): Promise<boolean> {
	if (!auth.user?.id) return false;
	const { data, error } = await supabase.rpc('gym_has_weighted_sets', undefined, { get: true });
	if (error) {
		console.error('fetchGymHasWeightedSets failed', error);
		return false;
	}
	return data === true;
}

/// A single workout plus its sets in set_index order. Returns null when the
/// id doesn't resolve (RLS hides another user's private workout).
export async function fetchGymWorkoutWithSets(
	id: string,
): Promise<GymWorkoutWithSets | null> {
	const { data: workout, error: wErr } = await supabase
		.from(TABLES.gym_workouts)
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (wErr || !workout) return null;
	const { data: sets, error: sErr } = await supabase
		.from(TABLES.gym_sets)
		.select('*')
		.eq('workout_id', id)
		.order('set_index', { ascending: true });
	// A workout whose sets failed to load is not a workout with no sets:
	// returning the populated header over an empty body presented a partial
	// read failure as the user's session being empty. Fail the whole read so
	// the caller can offer a retry.
	if (sErr) throw dbError(sErr);
	return { workout: workout as GymWorkout, sets: (sets ?? []) as GymSet[] };
}

/// The newest in-flight guided-session draft for a routine — the row a refresh
/// mid-session resumes from (decisions.md § 483). Owner-scoped by RLS.
///
/// The server-side key-existence filter is a cheap prefilter, not the
/// predicate: PostgREST cannot ask `jsonb_typeof`, so it also matches a bag
/// whose key carries JSON null or an array. `hasSessionDraft` is what decides,
/// so this agrees with the resume card and the routine-history exclusion
/// instead of adopting — and overwriting the sets of — a row they both count
/// as a session performed.
export async function fetchGymSessionDraft(routineId: string): Promise<GymWorkout | null> {
	const userId = auth.user?.id;
	if (!userId || !routineId) return null;
	const { data, error } = await supabase
		.from(TABLES.gym_workouts)
		.select('*')
		.eq('user_id', userId)
		.eq('metadata->>routine_id', routineId)
		.not(`metadata->${GYM_SESSION_DRAFT_KEY}`, 'is', null)
		.order('started_at', { ascending: false })
		.limit(1);
	if (error) {
		console.error('fetchGymSessionDraft failed', error);
		return null;
	}
	const row = (data?.[0] as GymWorkout | undefined) ?? null;
	return row && hasSessionDraft(row.metadata) ? row : null;
}

/// Sets the user has logged, joined to their workout start time. Owner-scoped.
///
/// `sinceDays` bounds the read to workouts started within the last N days —
/// pass it on surfaces that only reason about recent training (e.g. the
/// dashboard's 90-day training-load curve + its 5 most-recent-lift cards) so a
/// multi-year lifter's whole gym_sets history (~15k rows) isn't shipped to the
/// browser on every load. perf-hunt follow-up 2026-06-10.
///
/// Nothing reads this unwindowed any more. An all-time question is a server
/// question: PostgREST caps an unbounded SELECT at 1000 rows, so the /gym PR
/// badges that used to pass no window were computed from a truncated,
/// unordered history past ~40 sessions. Those go through
/// `fetchGymWorkoutSummariesWithError`; per-exercise bests through
/// `fetchExerciseRecords`; per-workout prior sets on /gym/[id] through
/// `fetchExerciseSetHistoryBatch`. All three aggregate or scope in SQL.
export async function fetchGymSetHistoryWithError(opts?: {
	sinceDays?: number;
}): Promise<{ sets: GymSetWithDate[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { sets: [], error: null };
	let query = supabase
		.from(TABLES.gym_sets)
		.select('workout_id, exercise_name, reps, weight_kg, rpe, duration_s, set_type, gym_workouts!inner(started_at, user_id)')
		.eq('gym_workouts.user_id', userId);
	if (opts?.sinceDays != null) {
		const since = new Date(Date.now() - opts.sinceDays * 86_400_000).toISOString();
		query = query.gte('gym_workouts.started_at', since);
	}
	const { data, error } = await query;
	if (error) return { sets: [], error: error.message };
	const sets = ((data ?? []) as unknown[]).map((row) => {
		const r = row as {
			workout_id: string;
			exercise_name: string;
			reps: number | null;
			weight_kg: number | null;
			rpe: number | null;
			duration_s: number | null;
			set_type: string | null;
			gym_workouts: { started_at: string } | { started_at: string }[];
		};
		const w = singleEmbed(r.gym_workouts);
		return {
			workout_id: r.workout_id,
			started_at: w?.started_at ?? '',
			exercise_name: r.exercise_name,
			reps: r.reps,
			weight_kg: r.weight_kg,
			rpe: r.rpe,
			duration_s: r.duration_s,
			set_type: r.set_type,
		};
	});
	return { sets, error: null };
}

export async function fetchGymSetHistory(opts?: {
	sinceDays?: number;
}): Promise<GymSetWithDate[]> {
	return (await fetchGymSetHistoryWithError(opts)).sets;
}

/// One per-exercise all-time strength record (heaviest set, best volume, best
/// e1rm, last performed, session count). Computed server-side by the
/// gym_exercise_records RPC (migration 20261224_001) so the client never pulls
/// raw set history to recompute it. Records are all-time maxima, so a windowed
/// read can't serve them — the aggregation lives in SQL, mirroring how run PRs
/// are SQL-maintained (the gym_prs.ts badge engine stays client-side for the
/// per-workout temporal badges). pgTAP gym_exercise_records_test.sql pins the
/// metrics against the same fixture shape gym_prs.test.ts uses.
export interface ExerciseRecord {
	exerciseName: string;
	heaviestWeightKg: number;
	heaviestWeightReps: number | null;
	bestVolumeKg: number | null;
	bestEst1RmKg: number | null;
	/// ISO timestamp of the most recent workout that included this exercise.
	lastPerformedAt: string;
	sessionCount: number;
}

/// Per-exercise all-time records for the signed-in user, most-recently-
/// performed first. One round-trip; the SQL does the aggregation.
/// Same as `fetchExerciseRecords` but surfaces the RPC error so the
/// records page can show a "couldn't load — retry" state instead of the
/// empty "no records yet" card (a real failure otherwise reads as a
/// brand-new lifter). Mirrors the `fetchMyPlansWithError` convention.
export async function fetchExerciseRecordsWithError(): Promise<{
	records: ExerciseRecord[];
	error: string | null;
}> {
	if (!auth.user?.id) return { records: [], error: null };
	const { data, error } = await supabase.rpc('gym_exercise_records', undefined, { get: true });
	if (error) return { records: [], error: error.message };
	type Row = {
		exercise_name: string;
		heaviest_weight_kg: number | string;
		heaviest_weight_reps: number | null;
		best_volume_kg: number | string | null;
		best_est_1rm_kg: number | string | null;
		last_performed_at: string;
		session_count: number;
	};
	const num = (v: number | string | null): number | null =>
		v == null ? null : Number(v);
	return {
		records: ((data ?? []) as Row[]).map((r) => ({
			exerciseName: r.exercise_name,
			heaviestWeightKg: Number(r.heaviest_weight_kg),
			heaviestWeightReps: r.heaviest_weight_reps,
			bestVolumeKg: num(r.best_volume_kg),
			bestEst1RmKg: num(r.best_est_1rm_kg),
			lastPerformedAt: r.last_performed_at,
			sessionCount: r.session_count,
		})),
		error: null
	};
}

export async function fetchExerciseRecords(): Promise<ExerciseRecord[]> {
	return (await fetchExerciseRecordsWithError()).records;
}

/// Every logged set of ONE exercise (normalised-name matched server-side),
/// joined to its workout start time — for the single-exercise progression view
/// (/gym/exercise). Bounds the read to that exercise instead of pulling the
/// whole history and filtering in JS. The RPC normalises the name the same way
/// gym_prs.ts#normaliseExerciseName does, so it picks up sessions logged under
/// a different capitalisation. perf-hunt follow-up 2026-06-10.
/// Same as `fetchExerciseSetHistory` but surfaces the RPC error so the
/// single-exercise progression page can show a "couldn't load — retry"
/// state instead of an empty "no progression data" card.
export async function fetchExerciseSetHistoryWithError(
	name: string
): Promise<{ sets: GymSetWithDate[]; error: string | null }> {
	// The RPC matches `s.exercise_key = normalise_exercise_name(p_name)`, so the
	// only blankness that means anything here is the fold's — a name of one
	// U+0085 survives JS `trim()` and folds to the empty key no row can hold
	// (§ 1367).
	if (!auth.user?.id || !namesAnExercise(name)) return { sets: [], error: null };
	const { data, error } = await supabase.rpc('gym_exercise_set_history', { p_name: name }, { get: true });
	if (error) return { sets: [], error: error.message };
	return {
		sets: ((data ?? []) as Array<{
			workout_id: string;
			started_at: string;
			exercise_name: string;
			reps: number | null;
			weight_kg: number | string | null;
			rpe: number | string | null;
			duration_s: number | null;
			set_type: string | null;
		}>).map((r) => ({
			workout_id: r.workout_id,
			started_at: r.started_at,
			exercise_name: r.exercise_name,
			reps: r.reps,
			weight_kg: r.weight_kg == null ? null : Number(r.weight_kg),
			rpe: r.rpe == null ? null : Number(r.rpe),
			duration_s: r.duration_s,
			set_type: r.set_type,
		})),
		error: null
	};
}

export async function fetchExerciseSetHistory(name: string): Promise<GymSetWithDate[]> {
	return (await fetchExerciseSetHistoryWithError(name)).sets;
}

/// N exercises' set history in ONE round-trip (migration 20270323_001) — the
/// batched sibling of fetchExerciseSetHistory for the session / detail pages
/// that previously called the singular RPC once per exercise. Server-side the
/// match is on the normalised name (same expression as normaliseExerciseName),
/// so consumers can group the flat result by that key.
export async function fetchExerciseSetHistoryBatch(names: string[]): Promise<GymSetWithDate[]> {
	// The RPC folds each element and drops the ones that fold to empty, so this
	// filter only decides which names are worth a round trip — and it has to
	// agree with the server about which those are. A JS `trim()` does not: it
	// leaves U+0085 standing (§ 1367). The names go over unfolded, because the
	// server's fold is the one that matches.
	const wanted = names.filter((n) => namesAnExercise(n));
	if (!auth.user?.id || wanted.length === 0) return [];
	const { data, error } = await supabase.rpc('gym_exercise_set_history_batch', {
		p_names: wanted
	});
	if (error) {
		console.error('fetchExerciseSetHistoryBatch failed', error);
		return [];
	}
	return ((data ?? []) as Array<{
		workout_id: string;
		started_at: string;
		exercise_name: string;
		reps: number | null;
		weight_kg: number | string | null;
		rpe: number | string | null;
		duration_s: number | null;
		set_type: string | null;
	}>).map((r) => ({
		workout_id: r.workout_id,
		started_at: r.started_at,
		exercise_name: r.exercise_name,
		reps: r.reps,
		weight_kg: r.weight_kg == null ? null : Number(r.weight_kg),
		rpe: r.rpe == null ? null : Number(r.rpe),
		duration_s: r.duration_s,
		set_type: r.set_type
	}));
}

/// Distinct exercise names the user has logged, most-used first — for the gym
/// editor's autocomplete datalist. Bounded to the count of distinct exercises
/// (dozens), so a caller that only needs the names never pulls raw set history.
/// perf-hunt follow-up 2026-06-10.
export async function fetchGymExerciseNames(): Promise<string[]> {
	if (!auth.user?.id) return [];
	const { data, error } = await supabase.rpc('gym_exercise_names', undefined, { get: true });
	if (error) {
		console.error('fetchGymExerciseNames failed', error);
		return [];
	}
	return ((data ?? []) as Array<{ exercise_name: string }>).map((r) => r.exercise_name);
}

/// Alphabetical; `id` breaks a tie because a seeded global and a user's own
/// custom entry can carry the same name — the two partial uniques on
/// `name_key` (migration 20270222_001) scope uniqueness to `author_id is null`
/// and to one author, so a custom can shadow a global. Both columns are NOT
/// NULL. `api_client.dart` walks the catalogue in the same order.
const EXERCISE_ORDER: readonly KeysetKey[] = [
	{ column: 'name', ascending: true, nullsFirst: false },
	{ column: 'id', ascending: true, nullsFirst: false },
];

/// The exercise catalogue visible to the signed-in user: every seeded global
/// (author_id null) plus their own custom entries. RLS scopes the read; an
/// ordered name list lets the gym editor merge these into its autocomplete
/// datalist and bind a typed name to an exercise_id (migration 20270222_001).
/// Additive — a user who never picks a catalogue entry logs exactly as before.
///
/// Surfaces the error instead of degrading to `[]`, because an empty catalogue
/// is a state the surfaces ACT on: `GymEditor` binds every typed name to no
/// `exercises.id`, the browse affordance hides itself, and the picker's
/// create-custom test is only as good as the list it scans. The same
/// "unavailable is not empty" contract `fetchRunsWithError`,
/// `browseClubsWithError` and `fetchGlobalSegmentsWithError` each carry; here
/// it is the only shape rather than a sibling, because there is one caller and
/// a second, swallowing name would be a shim that reads safe.
export async function fetchExerciseCatalogue(): Promise<{
	catalogue: Exercise[];
	error: string | null;
}> {
	// Signed out is not a vouched-for empty catalogue either — the read never
	// happened, so nothing downstream may claim a typed name is free. The `/gym`
	// page returns before `load()` when there is no user and so never reaches
	// this branch, which is exactly why the branch has to be right on its own:
	// the next caller inherits whatever it says, and `null` here says the
	// catalogue is known to hold nothing.
	if (!auth.user?.id) return { catalogue: [], error: 'signed_out' };
	// Walked by cursor: PostgREST caps an unranged select at `db.max-rows`, and
	// an OFFSET walk over a catalogue someone adds a custom entry to mid-read
	// skips or repeats a row (§ 1936).
	const walk = await walkKeyset(EXERCISE_ORDER, (after, limit) => {
		let q = supabase.from(TABLES.exercises).select('*');
		if (after) q = q.or(after);
		for (const k of EXERCISE_ORDER) {
			q = q.order(k.column, { ascending: k.ascending, nullsFirst: k.nullsFirst });
		}
		return q.limit(limit);
	});
	if (!walk.complete) {
		const error = walk.error as { message?: unknown; code?: unknown } | null;
		console.error('fetchExerciseCatalogue failed', walk.error);
		const message = typeof error?.message === 'string' ? error.message : 'unavailable';
		const code = typeof error?.code === 'string' && error.code ? ` (${error.code})` : '';
		return { catalogue: [], error: `${message}${code}` };
	}
	const rows = walk.rows as Exercise[];
	return { catalogue: dedupeShadowedExercises(rows), error: null };
}

/// Create an owner-scoped custom exercise. `name_key` is NOT sent: the
/// `exercises_stamp_name_key` trigger derives it from `name` on every insert
/// and update (migration 20270711000001), so a client value is overwritten
/// rather than used, and computing one here would be a fourth rail that can
/// drift from the fold the two partial unique indexes are actually built on.
/// RLS rejects an insert with any author_id other than the caller. Returns the
/// created row, or null on conflict/error (e.g. a duplicate name_key -- the
/// conflict is decided on the SERVER's fold).
export async function createCustomExercise(input: {
	name: string;
	category?: ExerciseCategory;
	modality?: GymExerciseModality;
}): Promise<Exercise | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const name = input.name.trim();
	// The display spelling is not the rail the row is keyed on: `name_key` is
	// stamped from it by trigger and carries a `length between 1 and 120`
	// CHECK, and the fold's whitespace class is not the set JS `trim()` strips.
	// A name of one U+0085 survives the trim and mints an empty key the column
	// refuses, so blankness is decided on the key (§ 1367).
	if (!namesAnExercise(name)) return null;
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.exercises)
		.insert({
			author_id: userId,
			name,
			category: input.category ?? 'other',
			modality: input.modality ?? 'weight_reps',
			last_modified_at: nowIso,
		})
		.select('*')
		.single();
	if (error || !data) {
		console.error('createCustomExercise failed', error);
		return null;
	}
	return data as Exercise;
}

async function replaceGymSets(workoutId: string, sets: GymSetInput[]): Promise<void> {
	const { error: delErr } = await supabase
		.from(TABLES.gym_sets)
		.delete()
		.eq('workout_id', workoutId);
	if (delErr) throw dbError(delErr);
	// Dropped on the key, not the spelling: `gym_sets.exercise_key` is stamped
	// from `exercise_name` by trigger under a `length >= 1` CHECK, and a name
	// of one U+0085 trims non-empty while folding to nothing. Dropping first
	// also keeps `set_index` contiguous — a blank in the middle used to leave a
	// hole in the numbering the surviving sets are read back by.
	const rows = sets
		.filter((s) => namesAnExercise(s.exercise_name))
		.map((s, i) => ({
			workout_id: workoutId,
			set_index: i,
			exercise_name: s.exercise_name.trim(),
			reps: s.reps ?? null,
			weight_kg: s.weight_kg ?? null,
			rpe: s.rpe ?? null,
			// NOT NULL column — coalesce to the working default so an omitted
			// type never sends null (migration 20270224_001).
			set_type: s.set_type ?? 'working',
			duration_s: s.duration_s ?? null,
			exercise_id: s.exercise_id ?? null,
		}));
	if (rows.length === 0) return;
	const { error: insErr } = await supabase.from(TABLES.gym_sets).insert(rows);
	if (insErr) throw dbError(insErr);
}

export async function createGymWorkout(input: {
	title?: string | null;
	started_at?: string;
	duration_s?: number | null;
	notes?: string | null;
	is_public?: boolean;
	sets?: GymSetInput[];
	metadata?: JsonObject | null;
}): Promise<GymWorkout> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const nowIso = new Date().toISOString();
	markListsStale('history');
	const { data, error } = await supabase
		.from(TABLES.gym_workouts)
		.insert({
			user_id: userId,
			title: input.title ?? null,
			started_at: input.started_at ?? nowIso,
			duration_s: input.duration_s ?? null,
			notes: input.notes ?? null,
			is_public: input.is_public ?? false,
			// gym_workouts.metadata is NOT NULL default '{}' (20270101_001).
			// Sending an explicit null bypasses the default and trips a 23502,
			// so coalesce to an empty bag when the caller omits it.
			metadata: input.metadata ?? {},
			last_modified_at: nowIso,
		})
		.select('*')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createGymWorkout failed');
	const workout = data as GymWorkout;
	if (input.sets && input.sets.length > 0) {
		await replaceGymSets(workout.id, input.sets);
	}
	return workout;
}

export async function updateGymWorkout(
	id: string,
	patch: Partial<
		Pick<GymWorkout, 'title' | 'started_at' | 'duration_s' | 'notes' | 'is_public' | 'metadata'>
	>,
	sets?: GymSetInput[],
): Promise<void> {
	markListsStale('history');
	const { error } = await supabase
		.from(TABLES.gym_workouts)
		.update({ ...patch, last_modified_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw dbError(error);
	if (sets !== undefined) await replaceGymSets(id, sets);
}

/// Flip a gym workout's visibility. Mirrors `setRoutePublic` — bidirectional
/// (public ↔ private). RLS guards ownership; the caller should still gate the
/// UI so non-owners never see the control. Stamps `last_modified_at` so the
/// offline newer-wins reconciliation on mobile picks the change up.
export async function setGymWorkoutPublic(id: string, isPublic: boolean): Promise<void> {
	markListsStale('history');
	const { error } = await supabase
		.from(TABLES.gym_workouts)
		.update({ is_public: isPublic, last_modified_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Deletes the workout; gym_sets cascade via the FK (migration 20261204_001).
export async function deleteGymWorkout(id: string): Promise<void> {
	markListsStale('history');
	const { error } = await supabase.from(TABLES.gym_workouts).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Gym routines (gym_programming.md slice P1) ---
//
// A reusable plan: gym_routines parent + gym_routine_exercises + their
// gym_routine_sets. Author-only RLS (migration 20270101_001). last_modified_at
// + exercise_count are client-stamped (newer-wins sync, non-authoritative
// count — no server trigger), mirroring gym_workouts. The plan is NOT a dated
// activity, so it does not feed the activities view. P1 leaves the superset /
// progression / periodisation columns at their defaults.

export interface GymRoutineSummary {
	id: string;
	author_id: string;
	club_id: string | null;
	is_public_template: boolean;
	title: string;
	notes: string | null;
	exercise_count: number;
	last_modified_at: string;
	created_at: string;
}

export interface GymRoutineExercise {
	id: string;
	exercise_name: string;
	exercise_key: string;
	position: number;
	superset_group: number | null;
	superset_order: number | null;
	modality: GymExerciseModality;
	progression: GymProgressionScheme;
	progression_params: JsonObject;
	sets: GymRoutineSet[];
}

export interface GymRoutineSet {
	set_index: number;
	set_type: GymSetType;
	target_reps_min: number | null;
	target_reps_max: number | null;
	target_weight_kg: number | null;
	target_rpe: number | null;
	rest_s: number | null;
	target_duration_s: number | null;
	target_distance_m: number | null;
}

export interface GymRoutineDetail {
	routine: GymRoutineSummary;
	exercises: GymRoutineExercise[];
}

/// The shape routineFromWorkout / the RoutineEditor produce. Mirrors the
/// RoutineDraft from #lib/gym/gym_routine.ts.
export interface GymRoutineInput {
	title: string;
	notes?: string | null;
	exercises: Array<{
		exercise_name: string;
		exercise_key: string;
		position: number;
		superset_group?: number | null;
		superset_order?: number | null;
		modality?: GymExerciseModality;
		progression?: GymProgressionScheme;
		progression_params?: JsonObject;
		sets: Array<{
			set_index: number;
			set_type?: GymSetType;
			target_reps_min?: number | null;
			target_reps_max?: number | null;
			target_weight_kg?: number | null;
			target_rpe?: number | null;
			rest_s?: number | null;
			target_duration_s?: number | null;
			target_distance_m?: number | null;
		}>;
	}>;
}

/// Authored routines for the signed-in user, most-recently-modified first.
/// Same as `fetchGymRoutines` but surfaces the error so the routines page
/// can show a "couldn't load — retry" state rather than an empty list
/// (indistinguishable from "no routines yet"). Mirrors the
/// `fetchRoutesWithError` / `fetchMyPlansWithError` convention.
export async function fetchGymRoutinesWithError(
	limit = 100
): Promise<{ routines: GymRoutineSummary[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { routines: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('author_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	return { routines: (data ?? []) as GymRoutineSummary[], error: error?.message ?? null };
}

export async function fetchGymRoutines(limit = 100): Promise<GymRoutineSummary[]> {
	return (await fetchGymRoutinesWithError(limit)).routines;
}

/// A single routine with its exercises (by position) + their planned sets (by
/// set_index). Returns null when the id doesn't resolve (RLS hides others').
/// A public template a non-author previews (the library detail page) misses on
/// the owner-only base table and falls back to the redacted
/// public_gym_routines view (migration 20270319_001), which carries no
/// last_modified_at — created_at stands in for the required summary field.
export async function fetchGymRoutineDetail(id: string): Promise<GymRoutineDetail | null> {
	let routine: GymRoutineSummary | null = null;
	const { data: base, error: rErr } = await supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('id', id)
		.maybeSingle();
	if (!rErr && base) {
		routine = base as GymRoutineSummary;
	} else {
		const { data: pub } = await supabase
			.from('public_gym_routines')
			.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, created_at')
			.eq('id', id)
			.maybeSingle();
		if (pub) {
			const p = pub as Omit<GymRoutineSummary, 'last_modified_at'>;
			routine = { ...p, last_modified_at: p.created_at };
		}
	}
	if (!routine) return null;
	const { data: exRows, error: eErr } = await supabase
		.from(TABLES.gym_routine_exercises)
		.select(
			'id, exercise_name, exercise_key, position, superset_group, superset_order, modality, progression, progression_params',
		)
		.eq('routine_id', id)
		.order('position', { ascending: true });
	// Same contract as fetchGymWorkoutWithSets: a routine whose exercises
	// failed to load is not an empty routine, and rendering it as one invites
	// the viewer to start or adopt a routine that has no content.
	if (eErr) throw dbError(eErr);
	const exercises = (exRows ?? []) as Array<{
		id: string;
		exercise_name: string;
		exercise_key: string;
		position: number;
		superset_group: number | null;
		superset_order: number | null;
		modality: GymExerciseModality;
		progression: GymProgressionScheme;
		progression_params: JsonObject | null;
	}>;
	if (exercises.length === 0) {
		return { routine: routine as GymRoutineSummary, exercises: [] };
	}
	// Every exercise's sets come back from one chunk, so the per-exercise
	// set_index order the grouping below relies on survives the merge.
	const { data: setRows, error: sErr } = await queryChunked(
		exercises.map((e) => e.id),
		(part) =>
			supabase
				.from(TABLES.gym_routine_sets)
				.select(
					'routine_exercise_id, set_index, set_type, target_reps_min, target_reps_max, target_weight_kg, target_rpe, rest_s, target_duration_s, target_distance_m',
				)
				.in('routine_exercise_id', part)
				.order('set_index', { ascending: true }),
	);
	// The planned sets ARE the prescription — dropping them silently turns a
	// 5x5 into a bare exercise list.
	if (sErr) throw dbError(sErr);
	const setsByExercise = new Map<string, GymRoutineSet[]>();
	for (const row of (setRows ?? []) as Array<{ routine_exercise_id: string } & GymRoutineSet>) {
		const list = setsByExercise.get(row.routine_exercise_id) ?? [];
		list.push({
			set_index: row.set_index,
			set_type: row.set_type,
			target_reps_min: row.target_reps_min,
			target_reps_max: row.target_reps_max,
			target_weight_kg: row.target_weight_kg,
			target_rpe: row.target_rpe,
			rest_s: row.rest_s,
			target_duration_s: row.target_duration_s,
			target_distance_m: row.target_distance_m,
		});
		setsByExercise.set(row.routine_exercise_id, list);
	}
	return {
		routine: routine as GymRoutineSummary,
		exercises: exercises.map((e) => ({
			id: e.id,
			exercise_name: e.exercise_name,
			exercise_key: e.exercise_key,
			position: e.position,
			superset_group: e.superset_group,
			superset_order: e.superset_order,
			modality: e.modality,
			progression: e.progression,
			progression_params: e.progression_params ?? {},
			sets: setsByExercise.get(e.id) ?? [],
		})),
	};
}

/// One routine's own performance history: complete tallies over every session
/// it has ever been run as, plus a bounded page of the most recent for the
/// panel's list — all from the `gym_routine_history` RPC in one round trip.
///
/// A count is an aggregate, so no client-side window can serve it honestly:
/// the previous read pulled up to 500 rows just to reduce them, and past that
/// silently under-reported (an unbounded PostgREST select truncates at
/// `db.max-rows` and still answers 200). The RPC applies the draft / ungraded
/// exclusions to BOTH the tallies and the page in one snapshot, so the listed
/// rows can never contradict the count above them; classifying each listed row
/// is still `gym/routine_history.ts`'s job.
export async function fetchGymRoutineHistory(
	routineId: string,
	recentLimit = 5,
): Promise<RoutineHistoryAggregate> {
	const empty: RoutineHistoryAggregate = {
		sessionCount: 0,
		lastPerformedAt: null,
		gradedCount: 0,
		completedCount: 0,
		recentRows: [],
	};
	const userId = auth.user?.id;
	if (!userId || !routineId) return empty;
	const { data, error } = await supabase.rpc('gym_routine_history', {
		p_routine_id: routineId,
		p_recent_limit: recentLimit,
	}, { get: true });
	// A failed read is not "you have never run this" — the caller shows a retry
	// rather than an empty history.
	if (error) throw dbError(error);
	const row = data?.[0];
	if (!row) return empty;
	return {
		sessionCount: row.session_count ?? 0,
		lastPerformedAt: row.last_performed_at ?? null,
		gradedCount: row.graded_count ?? 0,
		completedCount: row.completed_count ?? 0,
		// `recent_sessions` is a jsonb array the RPC builds row by row
		// (migration 20270528_001); the generated return type can say no more
		// than `Json`, so the element shape is the RPC's contract with
		// `routine_history.ts` rather than anything the compiler can check.
		recentRows: Array.isArray(row.recent_sessions)
			? (row.recent_sessions as unknown as RoutineSessionRow[])
			: [],
	};
}

/// Insert a routine + its exercises + their planned sets. Blank-named
/// exercises are dropped. exercise_count is stamped client-side from the
/// surviving exercise list (non-authoritative cache).
export async function createGymRoutine(input: GymRoutineInput): Promise<GymRoutineSummary> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	// The same key-not-spelling test `replaceGymSets` applies:
	// `gym_routine_exercises.exercise_key` is trigger-stamped under a
	// `length between 1 and 120` CHECK the display spelling does not decide.
	const exercises = input.exercises.filter((e) => namesAnExercise(e.exercise_name));
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.gym_routines)
		.insert({
			author_id: userId,
			title: input.title.trim(),
			notes: input.notes ?? null,
			exercise_count: exercises.length,
			last_modified_at: nowIso,
		})
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createGymRoutine failed');
	const routine = data as GymRoutineSummary;
	if (exercises.length === 0) return routine;

	// Batch-insert all exercises in one round-trip, then all their planned sets
	// in a second — collapsing the previous N+1 serial loop (one INSERT…select
	// per exercise, each blocking the next, plus a per-exercise sets insert)
	// into 2 round-trips regardless of routine size. `position` is
	// client-supplied and unique per routine, and there's no insert trigger
	// reading prior rows, so the rows have no inter-row dependency and the
	// returned ids map back by position. Mirrors createTrainingPlan's shape.
	const exerciseRows = exercises.map((ex) => {
		// gym_routine_exercises_superset_chk requires the group + order to be
		// both null or both set, so a standalone exercise clears both.
		const supersetGroup = ex.superset_group ?? null;
		return {
			routine_id: routine.id,
			exercise_name: ex.exercise_name.trim(),
			// exercise_key is NOT sent: gym_routine_exercises_stamp_exercise_key
			// derives it from exercise_name on every write (20270711000001). The
			// caller still carries one for its own plan-to-log matching.
			position: ex.position,
			superset_group: supersetGroup,
			superset_order: supersetGroup == null ? null : ex.superset_order ?? 0,
			modality: ex.modality ?? 'weight_reps',
			progression: ex.progression ?? 'none',
			progression_params: ex.progression_params ?? {},
		};
	});
	const { data: exRows, error: exErr } = await supabase
		.from(TABLES.gym_routine_exercises)
		.insert(exerciseRows)
		.select('id, position');
	if (exErr || !exRows) throw exErr ? dbError(exErr) : new Error('createGymRoutine exercises failed');
	const idByPosition = new Map<number, string>();
	for (const r of exRows as { id: string; position: number }[]) {
		idByPosition.set(r.position, r.id);
	}
	const allSetRows = exercises.flatMap((ex) => {
		const exId = idByPosition.get(ex.position);
		if (!exId) return [];
		return ex.sets.map((s, i) => ({
			routine_exercise_id: exId,
			set_index: i,
			set_type: s.set_type ?? 'working',
			target_reps_min: s.target_reps_min ?? null,
			target_reps_max: s.target_reps_max ?? null,
			target_weight_kg: s.target_weight_kg ?? null,
			target_rpe: s.target_rpe ?? null,
			rest_s: s.rest_s ?? null,
			target_duration_s: s.target_duration_s ?? null,
			target_distance_m: s.target_distance_m ?? null,
		}));
	});
	if (allSetRows.length > 0) {
		const { error: sErr } = await supabase.from(TABLES.gym_routine_sets).insert(allSetRows);
		if (sErr) throw dbError(sErr);
	}
	return routine;
}

/// Deletes a routine; exercises + sets cascade via FK (migration 20270101_001).
/// Logged gym_workouts are untouched (the plan→log link is a metadata string,
/// not an FK).
export async function deleteGymRoutine(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.gym_routines).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Nutrition: food_log + body_metrics (Phase 4 multi-modal) ---
//
// A food_log row is one logged item against an optional meal slot, with
// per-item macros (migration 20261204_001). last_modified_at is
// client-stamped (newer-wins sync, no server trigger), mirroring gym/gear.
// Meals are owner-private in v1 — is_public exists in the schema but no UI
// surfaces meal sharing (multi_modal.md § Social feed).

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';

export interface FoodEntry {
	id: string;
	user_id: string;
	started_at: string;
	item_name: string;
	meal_slot: MealSlot | null;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	// Extended nutrients (issue #492), all nullable. Grams for fibre / sugar /
	// saturated fat; milligrams for sodium / cholesterol.
	fiber_g: number | null;
	sugar_g: number | null;
	sodium_mg: number | null;
	saturated_fat_g: number | null;
	cholesterol_mg: number | null;
	is_public: boolean;
	external_id: string | null;
	last_modified_at: string;
	created_at: string;
}

export interface FoodEntryInput {
	item_name: string;
	meal_slot?: MealSlot | null;
	calories?: number | null;
	protein_g?: number | null;
	carbs_g?: number | null;
	fat_g?: number | null;
	fiber_g?: number | null;
	sugar_g?: number | null;
	sodium_mg?: number | null;
	saturated_fat_g?: number | null;
	cholesterol_mg?: number | null;
	started_at?: string;
	external_id?: string | null;
}

/// Food entries whose `started_at` falls in the half-open window
/// [fromIso, toIso). Surfaces the error so the daily nutrition view + the
/// per-meal-slot detail can show a "couldn't load — retry" state instead of an
/// empty day (a real failure otherwise reads as "nothing logged", inviting the
/// user to re-log meals they already have). Mirrors the
/// `fetchExerciseRecordsWithError` convention.
export async function fetchFoodLogWithError(
	fromIso: string,
	toIso: string,
): Promise<{ entries: FoodEntry[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { entries: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.food_log)
		.select('*')
		.eq('user_id', userId)
		.gte('started_at', fromIso)
		.lt('started_at', toIso)
		.order('started_at', { ascending: true });
	if (error) return { entries: [], error: error.message };
	return { entries: (data ?? []) as FoodEntry[], error: null };
}

/// Food entries whose `started_at` falls in the half-open window
/// [fromIso, toIso). Used for the daily nutrition view + ring totals.
/// Owner-scoped by RLS.
export async function fetchFoodLog(fromIso: string, toIso: string): Promise<FoodEntry[]> {
	return (await fetchFoodLogWithError(fromIso, toIso)).entries;
}

export async function createFoodEntry(input: FoodEntryInput): Promise<FoodEntry> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('not signed in');
	const now = new Date().toISOString();
	const row = {
		user_id: userId,
		item_name: input.item_name,
		meal_slot: input.meal_slot ?? null,
		calories: input.calories ?? null,
		protein_g: input.protein_g ?? null,
		carbs_g: input.carbs_g ?? null,
		fat_g: input.fat_g ?? null,
		fiber_g: input.fiber_g ?? null,
		sugar_g: input.sugar_g ?? null,
		sodium_mg: input.sodium_mg ?? null,
		saturated_fat_g: input.saturated_fat_g ?? null,
		cholesterol_mg: input.cholesterol_mg ?? null,
		started_at: input.started_at ?? now,
		external_id: input.external_id ?? null,
		last_modified_at: now,
	};
	markListsStale('history');
	const { data, error } = await supabase
		.from(TABLES.food_log)
		.insert(row)
		.select('*')
		.single();
	if (error) throw dbError(error);
	return data as FoodEntry;
}

export async function updateFoodEntry(
	id: string,
	patch: Partial<FoodEntryInput>,
): Promise<void> {
	markListsStale('history');
	const { error } = await supabase
		.from(TABLES.food_log)
		.update({ ...patch, last_modified_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw dbError(error);
}

export async function deleteFoodEntry(id: string): Promise<void> {
	markListsStale('history');
	const { error } = await supabase.from(TABLES.food_log).delete().eq('id', id);
	if (error) throw dbError(error);
}

// --- Meal templates: saved meals logged with one tap (multi_modal.md) ---
//
// A reusable plan: meal_templates parent + meal_template_items. Owner-scoped
// RLS (migration 20270218_001). last_modified_at + item_count are
// client-stamped (newer-wins sync, non-authoritative count — no server
// trigger), mirroring food_log + gym_routines. A template is NOT a dated
// activity, so it does not feed the activities view. Item shaping (logged
// entries -> draft, template -> log inputs) is the pure meal_template.ts
// parity pair; these helpers are the Supabase round-trips.

export interface MealTemplateSummary {
	id: string;
	user_id: string;
	name: string;
	meal_slot: MealSlot | null;
	item_count: number;
	last_modified_at: string;
	created_at: string;
}

export interface MealTemplateItemRow {
	position: number;
	item_name: string;
	meal_slot: MealSlot | null;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	external_id: string | null;
}

export interface MealTemplateDetail {
	template: MealTemplateSummary;
	items: MealTemplateItemRow[];
}

/// The shape templateFromEntries / the save-as-meal flow hand to the create
/// call. Mirrors MealTemplateDraft from #lib/nutrition/meal_template.ts.
export interface MealTemplateInput {
	name: string;
	meal_slot?: MealSlot | null;
	items: Array<{
		position: number;
		item_name: string;
		meal_slot?: MealSlot | null;
		calories?: number | null;
		protein_g?: number | null;
		carbs_g?: number | null;
		fat_g?: number | null;
		external_id?: string | null;
	}>;
}

/// Saved meal templates for the signed-in user, most-recently-modified first.
/// Surfaces the error so the list can show a "couldn't load — retry" state
/// rather than an empty list (indistinguishable from "no templates yet"),
/// mirroring `fetchGymRoutinesWithError`.
export async function fetchMealTemplatesWithError(
	limit = 100,
): Promise<{ templates: MealTemplateSummary[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { templates: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.meal_templates)
		.select('id, user_id, name, meal_slot, item_count, last_modified_at, created_at')
		.eq('user_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	return { templates: (data ?? []) as MealTemplateSummary[], error: error?.message ?? null };
}

export async function fetchMealTemplates(limit = 100): Promise<MealTemplateSummary[]> {
	return (await fetchMealTemplatesWithError(limit)).templates;
}

/// A single template with its items ordered by `position`. Returns null when
/// the id doesn't resolve (RLS hides others').
export async function fetchMealTemplateDetail(id: string): Promise<MealTemplateDetail | null> {
	const { data: template, error: tErr } = await supabase
		.from(TABLES.meal_templates)
		.select('id, user_id, name, meal_slot, item_count, last_modified_at, created_at')
		.eq('id', id)
		.maybeSingle();
	if (tErr || !template) return null;
	const { data: itemRows, error: iErr } = await supabase
		.from(TABLES.meal_template_items)
		.select('position, item_name, meal_slot, calories, protein_g, carbs_g, fat_g, external_id')
		.eq('template_id', id)
		.order('position', { ascending: true });
	if (iErr) console.error('fetchMealTemplateDetail items failed', iErr);
	return {
		template: template as MealTemplateSummary,
		items: (itemRows ?? []) as MealTemplateItemRow[],
	};
}

/// Insert a template + its items. Blank-named items are dropped. item_count is
/// stamped client-side from the surviving item list (non-authoritative cache).
/// Two round-trips (parent, then a single batch of items), mirroring
/// `createGymRoutine`.
export async function createMealTemplate(input: MealTemplateInput): Promise<MealTemplateSummary> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const items = input.items.filter((it) => it.item_name.trim().length > 0);
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.meal_templates)
		.insert({
			user_id: userId,
			name: input.name.trim(),
			meal_slot: input.meal_slot ?? null,
			item_count: items.length,
			last_modified_at: nowIso,
		})
		.select('id, user_id, name, meal_slot, item_count, last_modified_at, created_at')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createMealTemplate failed');
	const template = data as MealTemplateSummary;
	if (items.length === 0) return template;
	const itemRows = items.map((it, i) => ({
		template_id: template.id,
		position: i,
		item_name: it.item_name.trim(),
		meal_slot: it.meal_slot ?? null,
		calories: it.calories ?? null,
		protein_g: it.protein_g ?? null,
		carbs_g: it.carbs_g ?? null,
		fat_g: it.fat_g ?? null,
		external_id: it.external_id ?? null,
	}));
	const { error: iErr } = await supabase.from(TABLES.meal_template_items).insert(itemRows);
	if (iErr) throw dbError(iErr);
	return template;
}

/// Delete a template; its items cascade via FK (migration 20270218_001).
/// Logged food_log entries are untouched — the template is a parallel plan,
/// never linked to the entries it spawned.
export async function deleteMealTemplate(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.meal_templates).delete().eq('id', id);
	if (error) throw dbError(error);
}

/// Log every item of a template as a food_log entry at `startedAt` (default
/// now), one round-trip. Returns the count logged. This is the one-tap
/// "Log meal template" path; the slot/item shaping (item → template-default →
/// `slotOverride`, position order) is the pure `entriesFromTemplate` parity
/// helper so the resolution can't drift from the mobile twin.
export async function logMealTemplate(
	detail: MealTemplateDetail,
	opts: { startedAt?: string; slotOverride?: MealSlot | null } = {},
): Promise<number> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const inputs = entriesFromTemplate(
		{
			name: detail.template.name,
			mealSlot: detail.template.meal_slot,
			items: detail.items.map((it) => ({
				position: it.position,
				itemName: it.item_name,
				mealSlot: it.meal_slot,
				calories: it.calories,
				proteinG: it.protein_g,
				carbsG: it.carbs_g,
				fatG: it.fat_g,
				externalId: it.external_id,
			})),
		},
		opts.slotOverride ?? null,
	);
	if (inputs.length === 0) return 0;
	const startedAt = opts.startedAt ?? new Date().toISOString();
	const nowIso = new Date().toISOString();
	const rows = inputs.map((it) => ({
		user_id: userId,
		item_name: it.itemName,
		meal_slot: it.mealSlot,
		calories: it.calories,
		protein_g: it.proteinG,
		carbs_g: it.carbsG,
		fat_g: it.fatG,
		started_at: startedAt,
		external_id: it.externalId,
		last_modified_at: nowIso,
	}));
	markListsStale('history');
	const { error } = await supabase.from(TABLES.food_log).insert(rows);
	if (error) throw dbError(error);
	return rows.length;
}

// --- Recipes: N ingredients summed into one logged meal (multi_modal.md) ---
//
// A reusable plan: recipes parent + recipe_ingredients. Owner-scoped RLS
// (migration 20270221_001). last_modified_at + ingredient_count are
// client-stamped (newer-wins sync, non-authoritative count — no server
// trigger), like meal_templates. The difference from a meal template: logging
// a recipe sums its ingredients into ONE food_log entry (the recipe's combined
// macros, scaled by servings), not one entry per item. The summing + the
// single log input is the pure recipe.ts parity pair; these helpers are the
// Supabase round-trips. A recipe is NOT a dated activity, so it never feeds
// the activities view.

export interface RecipeSummary {
	id: string;
	user_id: string;
	name: string;
	servings: number;
	meal_slot: MealSlot | null;
	ingredient_count: number;
	last_modified_at: string;
	created_at: string;
}

export interface RecipeIngredientRow {
	position: number;
	item_name: string;
	quantity: number;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
	external_id: string | null;
}

export interface RecipeDetail {
	recipe: RecipeSummary;
	ingredients: RecipeIngredientRow[];
}

/// The shape recipeFromEntries / the save-as-recipe flow hand to the create
/// call. Mirrors RecipeDraft from #lib/nutrition/recipe.ts.
export interface RecipeInput {
	name: string;
	servings?: number;
	meal_slot?: MealSlot | null;
	ingredients: Array<{
		position: number;
		item_name: string;
		quantity?: number;
		calories?: number | null;
		protein_g?: number | null;
		carbs_g?: number | null;
		fat_g?: number | null;
		external_id?: string | null;
	}>;
}

/// Saved recipes for the signed-in user, most-recently-modified first.
/// Surfaces the error so the list can show a "couldn't load — retry" state
/// rather than an empty list, mirroring `fetchMealTemplatesWithError`.
export async function fetchRecipesWithError(
	limit = 100,
): Promise<{ recipes: RecipeSummary[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { recipes: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.recipes)
		.select('id, user_id, name, servings, meal_slot, ingredient_count, last_modified_at, created_at')
		.eq('user_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	return { recipes: (data ?? []) as RecipeSummary[], error: error?.message ?? null };
}

export async function fetchRecipes(limit = 100): Promise<RecipeSummary[]> {
	return (await fetchRecipesWithError(limit)).recipes;
}

/// A single recipe with its ingredients ordered by `position`. Returns null
/// when the id doesn't resolve (RLS hides others').
export async function fetchRecipeDetail(id: string): Promise<RecipeDetail | null> {
	const { data: recipe, error: rErr } = await supabase
		.from(TABLES.recipes)
		.select('id, user_id, name, servings, meal_slot, ingredient_count, last_modified_at, created_at')
		.eq('id', id)
		.maybeSingle();
	if (rErr || !recipe) return null;
	const { data: ingredientRows, error: iErr } = await supabase
		.from(TABLES.recipe_ingredients)
		.select('position, item_name, quantity, calories, protein_g, carbs_g, fat_g, external_id')
		.eq('recipe_id', id)
		.order('position', { ascending: true });
	if (iErr) console.error('fetchRecipeDetail ingredients failed', iErr);
	return {
		recipe: recipe as RecipeSummary,
		ingredients: (ingredientRows ?? []) as RecipeIngredientRow[],
	};
}

/// Insert a recipe + its ingredients. Blank-named ingredients are dropped.
/// ingredient_count is stamped client-side from the surviving list
/// (non-authoritative cache). Two round-trips, mirroring `createMealTemplate`.
export async function createRecipe(input: RecipeInput): Promise<RecipeSummary> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const ingredients = input.ingredients.filter((it) => it.item_name.trim().length > 0);
	const nowIso = new Date().toISOString();
	const { data, error } = await supabase
		.from(TABLES.recipes)
		.insert({
			user_id: userId,
			name: input.name.trim(),
			servings: input.servings && input.servings >= 1 ? input.servings : 1,
			meal_slot: input.meal_slot ?? null,
			ingredient_count: ingredients.length,
			last_modified_at: nowIso,
		})
		.select('id, user_id, name, servings, meal_slot, ingredient_count, last_modified_at, created_at')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createRecipe failed');
	const recipe = data as RecipeSummary;
	if (ingredients.length === 0) return recipe;
	const ingredientRows = ingredients.map((it, i) => ({
		recipe_id: recipe.id,
		position: i,
		item_name: it.item_name.trim(),
		quantity: it.quantity && it.quantity >= 0 ? it.quantity : 1,
		calories: it.calories ?? null,
		protein_g: it.protein_g ?? null,
		carbs_g: it.carbs_g ?? null,
		fat_g: it.fat_g ?? null,
		external_id: it.external_id ?? null,
	}));
	const { error: iErr } = await supabase.from(TABLES.recipe_ingredients).insert(ingredientRows);
	if (iErr) throw dbError(iErr);
	return recipe;
}

/// Delete a recipe; its ingredients cascade via FK (migration 20270221_001).
/// Logged food_log entries are untouched — the recipe is a parallel plan,
/// never linked to the meals it spawned.
export async function deleteRecipe(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.recipes).delete().eq('id', id);
	if (error) throw dbError(error);
}

/// Log ONE serving of a recipe as a SINGLE food_log entry at `startedAt`
/// (default now): the recipe's name + its per-serving summed macros. Returns
/// the number of entries logged (1, or 0 for an empty recipe). The summing +
/// slot resolution is the pure `logInputFromRecipe` parity helper so the
/// per-serving macros can't drift from the mobile twin.
export async function logRecipe(
	detail: RecipeDetail,
	opts: { startedAt?: string; slotOverride?: MealSlot | null } = {},
): Promise<number> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const input = logInputFromRecipe(
		{
			name: detail.recipe.name,
			servings: detail.recipe.servings,
			mealSlot: detail.recipe.meal_slot,
			ingredients: detail.ingredients.map((it) => ({
				position: it.position,
				itemName: it.item_name,
				quantity: it.quantity,
				calories: it.calories,
				proteinG: it.protein_g,
				carbsG: it.carbs_g,
				fatG: it.fat_g,
				externalId: it.external_id,
			})),
		},
		opts.slotOverride ?? null,
	);
	if (!input) return 0;
	const startedAt = opts.startedAt ?? new Date().toISOString();
	const nowIso = new Date().toISOString();
	markListsStale('history');
	const { error } = await supabase.from(TABLES.food_log).insert({
		user_id: userId,
		item_name: input.itemName,
		meal_slot: input.mealSlot,
		calories: input.calories,
		protein_g: input.proteinG,
		carbs_g: input.carbsG,
		fat_g: input.fatG,
		started_at: startedAt,
		external_id: input.externalId,
		last_modified_at: nowIso,
	});
	if (error) throw dbError(error);
	return 1;
}

/// The user's most recent recorded weight, or null if none. Owner-only
/// (body_metrics has no public-read policy — special-category health data,
/// migration 20261216_001).
export async function fetchLatestWeightKg(): Promise<number | null> {
	const userId = auth.user?.id;
	if (!userId) return null;
	const { data, error } = await supabase
		.from(TABLES.body_metrics)
		.select('weight_kg')
		.eq('user_id', userId)
		.order('recorded_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	if (error) {
		console.error('fetchLatestWeightKg failed', error);
		return null;
	}
	return data ? ((data as { weight_kg: number }).weight_kg ?? null) : null;
}

/// Append a weight measurement to the time-series (one row per recording —
/// the series is the history). Caller gates on health-data consent.
export async function recordWeightKg(weightKg: number): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('not signed in');
	const { error } = await supabase
		.from(TABLES.body_metrics)
		.insert({ user_id: userId, weight_kg: weightKg });
	if (error) throw dbError(error);
}

// --- Nutrition plans: prescribed targets + self-assignment (nutrition_programming.md P1) ---
//
// nutrition_plans is author-scoped; nutrition_plan_assignments says which plan
// governs which run of diary days (migration 20270815000001). Adherence is
// never stored: the day view computes it from food_log and the governing plan.
// last_modified_at is client-stamped (newer-wins, no trigger), like gym_routines.

const NUTRITION_PLAN_COLS =
	'id, author_id, title, notes, goal_phase, target_calories, target_protein_g, target_carbs_g, target_fat_g, training_calories, training_carbs_g, progression, progression_params, external_id, last_modified_at, created_at';
const NUTRITION_ASSIGNMENT_COLS =
	'id, plan_id, client_id, assigned_by, start_date, end_date, status, last_modified_at, created_at';

type NutritionPlanRow = Database['public']['Tables']['nutrition_plans']['Row'];
type NutritionAssignmentRow = Database['public']['Tables']['nutrition_plan_assignments']['Row'];

function asNutritionPlan(row: NutritionPlanRow): NutritionPlan {
	const params = row.progression_params;
	return {
		...row,
		goal_phase: parseNutritionGoalPhase(row.goal_phase),
		progression: parseNutritionProgression(row.progression),
		progression_params:
			params !== null && typeof params === 'object' && !Array.isArray(params) ? params : {},
	};
}

function asNutritionAssignment(row: NutritionAssignmentRow): NutritionPlanAssignment {
	return { ...row, status: parseNutritionAssignmentStatus(row.status) };
}

/// The pure meal_plan shape of an assignment row.
export function planAssignmentOf(a: NutritionPlanAssignment): PlanAssignment {
	return {
		id: a.id,
		planId: a.plan_id,
		startDate: a.start_date,
		endDate: a.end_date,
		status: a.status,
		createdAt: a.created_at,
	};
}

/// The pure meal_plan prescription columns of a plan row.
export function planTargetsOf(p: NutritionPlan): PlanTargets {
	return {
		targetCalories: p.target_calories,
		targetProteinG: p.target_protein_g,
		targetCarbsG: p.target_carbs_g,
		targetFatG: p.target_fat_g,
		trainingCalories: p.training_calories,
		trainingCarbsG: p.training_carbs_g,
	};
}

/// What the editor hands the create / update calls.
export interface NutritionPlanInput {
	title: string;
	notes: string | null;
	goal_phase: NutritionGoalPhase;
	target_calories: number;
	target_protein_g: number | null;
	target_carbs_g: number | null;
	target_fat_g: number | null;
	training_calories: number | null;
	training_carbs_g: number | null;
}

/// The signed-in user's authored plans, most-recently-modified first. The
/// error is reported beside the list so "couldn't load" is never drawn as
/// "no plans yet".
export async function fetchNutritionPlansWithError(
	limit = 100,
): Promise<{ plans: NutritionPlan[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { plans: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.nutrition_plans)
		.select(NUTRITION_PLAN_COLS)
		.eq('author_id', userId)
		.order('last_modified_at', { ascending: false })
		.limit(limit);
	if (error) return { plans: [], error: thrownMessage(dbError(error)) };
	return { plans: (data ?? []).map(asNutritionPlan), error: null };
}

/// One plan by id. `plan: null, error: null` is a genuine miss (deleted, or
/// RLS hides it); a failed read carries its error instead.
export async function fetchNutritionPlan(
	id: string,
): Promise<{ plan: NutritionPlan | null; error: string | null }> {
	const { data, error } = await supabase
		.from(TABLES.nutrition_plans)
		.select(NUTRITION_PLAN_COLS)
		.eq('id', id)
		.maybeSingle();
	if (error) return { plan: null, error: thrownMessage(dbError(error)) };
	return { plan: data ? asNutritionPlan(data) : null, error: null };
}

/// Plans by id, for resolving the plans the caller's assignments point at.
export async function fetchNutritionPlansByIds(ids: string[]): Promise<NutritionPlan[]> {
	if (ids.length === 0) return [];
	const { data, error } = await queryChunked(ids, (part) =>
		supabase.from(TABLES.nutrition_plans).select(NUTRITION_PLAN_COLS).in('id', part)
	);
	if (error) throw dbError(error);
	return (data ?? []).map(asNutritionPlan);
}

export async function createNutritionPlan(input: NutritionPlanInput): Promise<NutritionPlan> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.nutrition_plans)
		.insert({
			...input,
			title: input.title.trim(),
			author_id: userId,
			last_modified_at: new Date().toISOString(),
		})
		.select(NUTRITION_PLAN_COLS)
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('createNutritionPlan failed');
	return asNutritionPlan(data);
}

export async function updateNutritionPlan(id: string, input: NutritionPlanInput): Promise<NutritionPlan> {
	const { data, error } = await supabase
		.from(TABLES.nutrition_plans)
		.update({ ...input, title: input.title.trim(), last_modified_at: new Date().toISOString() })
		.eq('id', id)
		.select(NUTRITION_PLAN_COLS)
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('updateNutritionPlan failed');
	return asNutritionPlan(data);
}

/// Delete a plan; its assignments cascade, and the days it governed revert to
/// the computed target. food_log is untouched — the link is date-based.
export async function deleteNutritionPlan(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.nutrition_plans).delete().eq('id', id);
	if (error) throw dbError(error);
}

/// Every assignment naming the signed-in user as the client, ended ones
/// included: an ended assignment still governs the days inside its range.
export async function fetchMyNutritionAssignmentsWithError(): Promise<{
	assignments: NutritionPlanAssignment[];
	error: string | null;
}> {
	const userId = auth.user?.id;
	if (!userId) return { assignments: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.nutrition_plan_assignments)
		.select(NUTRITION_ASSIGNMENT_COLS)
		.eq('client_id', userId)
		.order('start_date', { ascending: false })
		.limit(200);
	if (error) return { assignments: [], error: thrownMessage(dbError(error)) };
	return { assignments: (data ?? []).map(asNutritionAssignment), error: null };
}

async function endNutritionAssignment(a: NutritionPlanAssignment, today: string): Promise<void> {
	const action = stopFollowingAction(planAssignmentOf(a), today);
	const nowIso = new Date().toISOString();
	const { error } =
		action.kind === 'delete'
			? await supabase.from(TABLES.nutrition_plan_assignments).delete().eq('id', a.id)
			: await supabase
					.from(TABLES.nutrition_plan_assignments)
					.update({ status: 'ended', end_date: action.endDate, last_modified_at: nowIso })
					.eq('id', a.id);
	if (error) throw dbError(error);
}

/// Start following `planId` from `today`. The new assignment is written
/// before the old ones are ended, so a failure part-way leaves an overlap the
/// newest-start rule already resolves to the new plan — never a day with no
/// plan the user asked for.
export async function followNutritionPlan(
	planId: string,
	today: string,
	current: NutritionPlanAssignment[],
): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');
	const { data, error } = await supabase
		.from(TABLES.nutrition_plan_assignments)
		.insert({
			plan_id: planId,
			client_id: userId,
			assigned_by: userId,
			start_date: today,
			status: 'active',
			last_modified_at: new Date().toISOString(),
		})
		.select('id')
		.single();
	if (error || !data) throw error ? dbError(error) : new Error('followNutritionPlan failed');
	const toEnd = assignmentsToEnd(current.map(planAssignmentOf), today);
	for (const a of current) {
		if (a.id === data.id || !toEnd.some((t) => t.id === a.id)) continue;
		await endNutritionAssignment(a, today);
	}
}

/// Stop following: today reverts to the computed target.
export async function stopFollowingNutritionPlan(
	assignment: NutritionPlanAssignment,
	today: string,
): Promise<void> {
	await endNutritionAssignment(assignment, today);
}

// --- Unified activities timeline (Phase 4 multi-modal History) ---

/// One row of the `activities` UNION view (runs + gym_workouts + food_log)
/// projecting (id, user_id, kind, started_at, summary). `summary` is a thin
/// per-kind jsonb the History list renders without a second fetch; the
/// detail routes load the full underlying row. Migration 20261204_001.
export interface ActivityRow {
	id: string;
	kind: 'run' | 'lift' | 'meal';
	started_at: string;
	summary: Record<string, unknown>;
}

/// Windowed, reverse-chronological feed across all logged modalities for
/// the History timeline. RLS (security_invoker on the view) scopes it to
/// the caller. Always bounded — the timeline paginates like /runs rather
/// than pulling an unbounded history (multi_modal.md § "activities view
/// at scale").
export async function fetchActivities(limit = 100): Promise<ActivityRow[]> {
	return (await fetchActivitiesWithError(limit)).activities;
}

/// Same window as `fetchActivities` but surfaces a hard fetch failure
/// instead of swallowing it into an empty feed. A network / DB error and a
/// genuinely-empty history both used to collapse to `[]`, so a transient
/// failure rendered as the "nothing logged yet" empty state on /history with
/// no retry. This sibling distinguishes the two: `error` is non-null only on
/// a real failure. Mirrors the `fetchFoodLogWithError` convention. A
/// signed-out caller is empty, not an error.
export async function fetchActivitiesWithError(
	limit = 100,
): Promise<{ activities: ActivityRow[]; error: string | null }> {
	const userId = auth.user?.id;
	if (!userId) return { activities: [], error: null };
	const { data, error } = await supabase
		.from(TABLES.activities)
		.select('id, kind, started_at, summary')
		.eq('user_id', userId)
		.order('started_at', { ascending: false })
		.limit(limit);
	if (error) return { activities: [], error: error.message };
	const activities = ((data ?? []) as unknown[])
		.map((row) => {
			const r = row as {
				id: string | null;
				kind: string | null;
				started_at: string | null;
				summary: Record<string, unknown> | null;
			};
			return {
				id: r.id ?? '',
				kind: (r.kind ?? 'run') as ActivityRow['kind'],
				started_at: r.started_at ?? '',
				summary: r.summary ?? {},
			};
		})
		.filter((r) => r.id !== '' && r.started_at !== '');
	return { activities, error: null };
}

// ───────────────────────── Session plans (session_planner.md P1) ─────────────
// A reusable yoga/pilates session-content template: a plan head + optional
// blocks + ordered items. P1 is build/save/reuse + read; no execution. RLS
// owns authority (author / public / club). The editor supplies the full
// blocks+items shape; createSessionPlan / updateSessionPlan persist the head
// and replace the child rows (no diff — a plan is small and edited rarely, so a
// delete-all + re-insert is simpler and correct than a per-row reconcile).

export interface SessionPlanItemInput {
	movement_name: string;
	kind: SessionItemKind;
	duration_s: number | null;
	reps: number | null;
	per_side: boolean;
	tempo: string | null;
	cue: string | null;
	/// index into the editor's blocks array, or null for a flat (blockless) item.
	block_index: number | null;
}

export interface SessionPlanInput {
	title: string;
	discipline: string | null;
	equipment: string | null;
	is_public: boolean;
	club_id: string | null;
	est_duration_min: number | null;
	blocks: { name: string | null }[];
	items: SessionPlanItemInput[];
}

/** The user's own plans + any plan owned by a club they belong to. List view. */
export async function fetchSessionPlans(): Promise<SessionPlan[]> {
	const userId = auth.user?.id;
	if (!userId) return [];

	// Scope the read to the rows the list actually shows — the user's own
	// plans plus plans owned by a club they belong to. A bare select('*')
	// leaned entirely on the RLS policies to filter, forcing Postgres to
	// seq-scan every session_plan in the table and run the per-row
	// is_club_member() subquery on each. Filtering explicitly lets the
	// (author_id, updated_at) and (club_id, updated_at) indexes serve it
	// (BitmapOr), and also matches the documented intent — a stranger's
	// public plan should not appear in "my session plans".
	const { data: memberships } = await supabase
		.from(TABLES.club_members)
		.select('club_id')
		.eq('user_id', userId);
	const clubIds = (memberships ?? []).map((m: { club_id: string }) => m.club_id);

	let query = supabase.from('session_plans').select('*');
	query = clubIds.length
		? query.or(`author_id.eq.${userId},club_id.in.(${clubIds.join(',')})`)
		: query.eq('author_id', userId);
	const { data, error } = await query.order('updated_at', { ascending: false });
	if (error) throw dbError(error);
	return (data ?? []) as SessionPlan[];
}

/** A single plan with its blocks + items (read view + editor hydrate). */
export async function fetchSessionPlan(id: string): Promise<SessionPlanWithItems | null> {
	const { data: plan, error } = await supabase
		.from('session_plans')
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (error) throw dbError(error);
	if (!plan) return null;

	const [{ data: blocks }, { data: items }] = await Promise.all([
		supabase.from('session_plan_blocks').select('*').eq('plan_id', id).order('position'),
		supabase.from('session_plan_items').select('*').eq('plan_id', id).order('position')
	]);
	return {
		...(plan as SessionPlan),
		blocks: (blocks ?? []) as SessionPlanBlock[],
		items: ((items ?? []) as SessionPlanItem[])
	};
}

async function replaceSessionPlanChildren(planId: string, input: SessionPlanInput): Promise<void> {
	// Children cascade on plan delete; here we clear + re-insert to apply
	// edits. A resolved-with-error delete followed by successful inserts
	// would duplicate every block/item, so both deletes are error-checked.
	const { error: itemsError } = await supabase
		.from('session_plan_items')
		.delete()
		.eq('plan_id', planId);
	if (itemsError) throw dbError(itemsError);
	const { error: blocksError } = await supabase
		.from('session_plan_blocks')
		.delete()
		.eq('plan_id', planId);
	if (blocksError) throw dbError(blocksError);

	const blockIds: string[] = [];
	if (input.blocks.length > 0) {
		const { data, error } = await supabase
			.from('session_plan_blocks')
			.insert(
				input.blocks.map((b, i) => ({
					plan_id: planId,
					position: i,
					name: b.name?.trim() || null
				}))
			)
			.select('id');
		if (error) throw dbError(error);
		// insert preserves input order, but sort defensively by nothing — map by index.
		for (const row of (data ?? []) as { id: string }[]) blockIds.push(row.id);
	}

	if (input.items.length > 0) {
		const { error } = await supabase.from('session_plan_items').insert(
			input.items.map((it, i) => ({
				plan_id: planId,
				block_id:
					it.block_index !== null && it.block_index < blockIds.length
						? blockIds[it.block_index]
						: null,
				position: i,
				movement_name: it.movement_name.trim(),
				kind: it.kind,
				duration_s: it.duration_s,
				reps: it.reps,
				per_side: it.per_side,
				tempo: it.tempo?.trim() || null,
				cue: it.cue?.trim() || null
			}))
		);
		if (error) throw dbError(error);
	}
}

export async function createSessionPlan(input: SessionPlanInput): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('session_plans')
		.insert({
			author_id: userId,
			club_id: input.club_id,
			title: input.title.trim(),
			discipline: input.discipline?.trim() || null,
			equipment: input.equipment?.trim() || null,
			est_duration_min: input.est_duration_min,
			is_public: input.is_public
		})
		.select('id')
		.single();
	if (error) throw dbError(error);
	const planId = (data as { id: string }).id;
	await replaceSessionPlanChildren(planId, input);
	return planId;
}

export async function updateSessionPlan(id: string, input: SessionPlanInput): Promise<void> {
	const { error } = await supabase
		.from('session_plans')
		.update({
			title: input.title.trim(),
			discipline: input.discipline?.trim() || null,
			equipment: input.equipment?.trim() || null,
			est_duration_min: input.est_duration_min,
			is_public: input.is_public,
			club_id: input.club_id,
			updated_at: new Date().toISOString()
		})
		.eq('id', id);
	if (error) throw dbError(error);
	await replaceSessionPlanChildren(id, input);
}

export async function deleteSessionPlan(id: string): Promise<void> {
	const { error } = await supabase.from('session_plans').delete().eq('id', id);
	if (error) throw dbError(error);
}

/** Flip a session plan's public visibility (owner-only via RLS). A public plan
 *  is readable logged-out at /share/session/[id]. */
export async function setSessionPlanPublic(id: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase
		.from('session_plans')
		.update({ is_public: isPublic, updated_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw dbError(error);
}

/** Distinct movement names the user has used across their own session plans,
 *  most-used first, for the editor's movement-name autocomplete (mirrors
 *  fetchGymExerciseNames). RLS on session_plan_items scopes the read to the
 *  owner; a session plan carries dozens of items, not thousands, so a direct
 *  distinct over the author's own plans is cheap — no RPC needed. Case is
 *  preserved (trim only), matching the gym datalist behaviour. */
export async function fetchSessionMovementNames(): Promise<string[]> {
	const userId = auth.user?.id;
	if (!userId) return [];
	const { data, error } = await supabase
		.from('session_plan_items')
		.select('movement_name, session_plans!inner(author_id)')
		.eq('session_plans.author_id', userId);
	if (error) {
		console.error('fetchSessionMovementNames failed', error);
		return [];
	}
	const counts = new Map<string, number>();
	for (const row of (data ?? []) as Array<{ movement_name: string | null }>) {
		const name = (row.movement_name ?? '').trim();
		if (name === '') continue;
		counts.set(name, (counts.get(name) ?? 0) + 1);
	}
	return [...counts.entries()]
		.sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
		.map(([name]) => name);
}

/** Attach (or detach with null) a session plan to a class event. Organiser-only
 *  at the DB layer (the events_session_plan_organiser trigger). A class carries
 *  a session plan or a gym routine, never both (events_one_class_content), so
 *  attaching a plan detaches any routine in the same write. */
export async function setEventSessionPlan(
	eventId: string,
	sessionPlanId: string | null
): Promise<void> {
	const { error } = await supabase
		.from('events')
		.update(
			sessionPlanId == null
				? { session_plan_id: null }
				: { session_plan_id: sessionPlanId, gym_routine_id: null }
		)
		.eq('id', eventId);
	if (error) throw dbError(error);
}

/** Attach (or detach with null) a gym routine to a class event (decisions
 *  § 1869). The events_gym_routine_organiser trigger admits only an organiser
 *  and only a template of the event's own club or a public template; attaching
 *  one detaches any session plan in the same write, as above. */
export async function setEventGymRoutine(
	eventId: string,
	gymRoutineId: string | null
): Promise<void> {
	const { error } = await supabase
		.from('events')
		.update(
			gymRoutineId == null
				? { gym_routine_id: null }
				: { gym_routine_id: gymRoutineId, session_plan_id: null }
		)
		.eq('id', eventId);
	if (error) throw dbError(error);
}

// ─── Admin moderation (web-only back-office; /admin/reports) ─────────
// Authorization is DB-enforced: every RPC below hard-denies a non-admin
// at the database (42501). am_i_admin only picks page chrome.

export interface PendingReportTarget {
	target_kind: ReportTargetKind;
	target_id: string;
	report_count: number;
	reporter_count: number;
	reasons: Record<string, number>;
	latest_at: string;
	shadow_hidden: boolean;
	/** The id of the page that shows the reported item (the item itself, or
	 *  the run / club / route carrying a comment / post / review); null for a
	 *  direct message or a target whose row is gone. */
	page_id: string | null;
}

export interface TargetReport {
	id: string;
	reporter_id: string;
	reason: string;
	notes: string | null;
	status: string;
	created_at: string;
	reviewed_at: string | null;
	reviewed_by: string | null;
	resolution: string | null;
	/// The reported direct message as it read at report time (migration
	/// 20271021000003); null for every other target kind.
	snapshot_body: string | null;
	snapshot_author_id: string | null;
	snapshot_sent_at: string | null;
}

/** Whether the current user is a moderator. Chrome gate only — the RPCs
 *  below are the real boundary. */
export async function amIAdmin(): Promise<boolean> {
	const { data, error } = await supabase.rpc('am_i_admin', undefined, { get: true });
	if (error) return false;
	return data === true;
}

/** The moderation queue: one row per reported target with pending reports. */
export async function fetchPendingReports(): Promise<PendingReportTarget[]> {
	const { data, error } = await supabase.rpc('fetch_pending_reports', undefined, { get: true });
	if (error) throw dbError(error);
	return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
		target_kind: r.target_kind as ReportTargetKind,
		target_id: r.target_id as string,
		report_count: Number(r.report_count ?? 0),
		reporter_count: Number(r.reporter_count ?? 0),
		reasons: (r.reasons ?? {}) as Record<string, number>,
		latest_at: r.latest_at as string,
		shadow_hidden: r.shadow_hidden === true,
		page_id: (r.page_id ?? null) as string | null,
	}));
}

/** Every individual report against one target (any status), newest first. */
export async function fetchReportsForTarget(
	targetKind: ReportTargetKind,
	targetId: string
): Promise<TargetReport[]> {
	const { data, error } = await supabase.rpc(
		'fetch_reports_for_target',
		{ p_target_kind: targetKind, p_target_id: targetId },
		{ get: true },
	);
	if (error) throw dbError(error);
	return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
		id: r.id as string,
		reporter_id: r.reporter_id as string,
		reason: r.reason as string,
		notes: (r.notes ?? null) as string | null,
		status: r.status as string,
		created_at: r.created_at as string,
		reviewed_at: (r.reviewed_at ?? null) as string | null,
		reviewed_by: (r.reviewed_by ?? null) as string | null,
		resolution: (r.resolution ?? null) as string | null,
		snapshot_body: (r.snapshot_body ?? null) as string | null,
		snapshot_author_id: (r.snapshot_author_id ?? null) as string | null,
		snapshot_sent_at: (r.snapshot_sent_at ?? null) as string | null,
	}));
}

/** Mark all pending reports on a target reviewed/dismissed with a note.
 *  Returns the number of reports resolved. */
export async function resolveTargetReports(
	targetKind: ReportTargetKind,
	targetId: string,
	status: ReportResolution,
	resolution: string | null
): Promise<number> {
	const { data, error } = await supabase.rpc('resolve_target_reports', {
		p_target_kind: targetKind,
		p_target_id: targetId,
		p_status: status,
		p_resolution: resolution,
	});
	if (error) throw dbError(error);
	return Number(data ?? 0);
}

/** Revert an auto-hide: clear shadow_hidden on a user/club/route.
 *  Returns true if a row was actually un-hidden. Admin-gated at the DB. */
export async function adminUnhideTarget(
	targetKind: ReportTargetKind,
	targetId: string
): Promise<boolean> {
	const { data, error } = await supabase.rpc('admin_unhide_target', {
		p_target_kind: targetKind,
		p_target_id: targetId,
	});
	if (error) throw dbError(error);
	return data === true;
}

// ─── Platform-fee earnings (operator back-office; /admin/earnings) ──────
// Same boundary as moderation: both RPCs raise 42501 for anyone not in
// app_admins, a host included (decisions § 1817).

export interface PlatformFeeHostRow {
	host_user_id: string;
	host_display_name: string | null;
	club_id: string | null;
	club_name: string | null;
	club_slug: string | null;
	currency: string;
	charge_count: number;
	gross_fee_cents: number;
	reversed_fee_cents: number;
	net_fee_cents: number;
}

/** Platform fees per UTC month of sale, per currency and source, net of
 *  refunds. Throws for a non-admin. */
export async function fetchPlatformFeeMonths(): Promise<PlatformFeeMonthRow[]> {
	const { data, error } = await supabase.rpc('admin_platform_fee_months', undefined, { get: true });
	if (error) throw dbError(error);
	return (data ?? []).map((r) => ({
		month: r.month,
		currency: r.currency,
		source: r.source === 'donation' ? 'donation' : 'event',
		charge_count: Number(r.charge_count ?? 0),
		gross_fee_cents: Number(r.gross_fee_cents ?? 0),
		reversed_fee_cents: Number(r.reversed_fee_cents ?? 0),
		net_fee_cents: Number(r.net_fee_cents ?? 0),
		refunded_count: Number(r.refunded_count ?? 0),
		partially_refunded_count: Number(r.partially_refunded_count ?? 0),
		refund_failed_count: Number(r.refund_failed_count ?? 0),
	}));
}

/** One UTC month's platform fees split by host + club + currency (`month` is
 *  any day in it, `YYYY-MM-DD`). Throws for a non-admin. */
export async function fetchPlatformFeesByHost(month: string): Promise<PlatformFeeHostRow[]> {
	const { data, error } = await supabase.rpc(
		'admin_platform_fees_by_host',
		{ p_month: month },
		{ get: true },
	);
	if (error) throw dbError(error);
	return (data ?? []).map((r) => ({
		host_user_id: r.host_user_id,
		host_display_name: r.host_display_name ?? null,
		club_id: r.club_id ?? null,
		club_name: r.club_name ?? null,
		club_slug: r.club_slug ?? null,
		currency: r.currency,
		charge_count: Number(r.charge_count ?? 0),
		gross_fee_cents: Number(r.gross_fee_cents ?? 0),
		reversed_fee_cents: Number(r.reversed_fee_cents ?? 0),
		net_fee_cents: Number(r.net_fee_cents ?? 0),
	}));
}

/** Club-owned session plans (the club's "session templates"). Visible to club
 *  members + writable by admins via RLS — mirrors fetchClubTemplates for
 *  training plans. */
export async function fetchClubSessionTemplates(clubId: string): Promise<SessionPlan[]> {
	const { data, error } = await supabase
		.from('session_plans')
		.select('*')
		.eq('club_id', clubId)
		.order('updated_at', { ascending: false });
	if (error) {
		console.error('fetchClubSessionTemplates failed', error);
		return [];
	}
	return (data ?? []) as SessionPlan[];
}

/** Publish a personal session plan into a club-owned copy (the original is left
 *  untouched on the user's /sessions list), mirroring publishPlanAsTemplate.
 *  Copies the head + blocks + items into a new club_id row; the publisher must
 *  own the source. Returns the new club-owned plan's id. */
export async function publishSessionAsTemplate(
	sourcePlanId: string,
	clubId: string
): Promise<string> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not signed in');

	const source = await fetchSessionPlan(sourcePlanId);
	if (!source) throw new Error('Source session plan not found');
	if (source.author_id !== userId) throw new Error('Only the plan owner can publish');

	const input: SessionPlanInput = {
		title: source.title,
		discipline: source.discipline,
		equipment: source.equipment,
		is_public: false,
		club_id: clubId,
		est_duration_min: source.est_duration_min,
		blocks: [...source.blocks]
			.sort((a, b) => a.position - b.position)
			.map((b) => ({ name: b.name })),
		items: (() => {
			const orderedBlocks = [...source.blocks].sort((a, b) => a.position - b.position);
			const blockIndexById = new Map(orderedBlocks.map((b, i) => [b.id, i]));
			return [...source.items]
				.sort((a, b) => a.position - b.position)
				.map((it) => ({
					movement_name: it.movement_name,
					kind: it.kind,
					duration_s: it.duration_s,
					reps: it.reps,
					per_side: it.per_side,
					tempo: it.tempo,
					cue: it.cue,
					block_index: it.block_id == null ? null : (blockIndexById.get(it.block_id) ?? null)
				}));
		})()
	};
	return createSessionPlan(input);
}

/** Clone a club session template into a new personal session plan (the
 *  clone_session_template RPC enforces author/member authorisation +
 *  rate-limits server-side). Returns the new plan's id. */
export async function cloneSessionTemplate(templateId: string): Promise<string> {
	const { data, error } = await supabase.rpc('clone_session_template', {
		template_id: templateId
	});
	if (error) {
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data as string;
}

/** Club-owned gym routines published as templates (gym_routines.club_id set).
 *  RLS exposes these to club members via private.is_club_member. */
export async function fetchClubGymRoutineTemplates(clubId: string): Promise<GymRoutineSummary[]> {
	const { data, error } = await supabase
		.from(TABLES.gym_routines)
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, last_modified_at, created_at')
		.eq('club_id', clubId)
		.order('last_modified_at', { ascending: false });
	if (error) {
		console.error('fetchClubGymRoutineTemplates failed', error);
		return [];
	}
	return (data ?? []) as GymRoutineSummary[];
}

/** Publish a personal gym routine into a club-owned template. The
 *  publish_gym_routine_as_template RPC is author + club-admin gated and
 *  deep-copies the routine + exercises + sets server-side (the personal
 *  original is left untouched). Returns the new club-owned routine id. */
export async function publishGymRoutineAsTemplate(routineId: string, clubId: string): Promise<string> {
	const { data, error } = await supabase.rpc('publish_gym_routine_as_template', {
		p_routine_id: routineId,
		p_club_id: clubId
	});
	if (error) {
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data as string;
}

/** Adopt a club gym-routine template into a new personal routine via the
 *  clone_gym_routine_template RPC (author-or-member gated, rate-limited
 *  server-side). Returns the new personal routine's id. */
export async function cloneGymRoutineTemplate(templateId: string): Promise<string> {
	const { data, error } = await supabase.rpc('clone_gym_routine_template', {
		p_template_id: templateId
	});
	if (error) {
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return data as string;
}

export type PublicGymRoutineEntry = GymRoutineSummary & {
	author_handle: string | null;
};

/// Browse the public gym-routine library — routines published as public
/// templates that any signed-in user can adopt (migration 20270224_001).
/// Optional case-insensitive title search, every character matched literally
/// (`literalSubstringPattern`, decisions § 1937). Each entry carries the author's
/// public display name (handle) joined from user_profiles; no other author
/// data is exposed. Mirrors fetchPublicPlanLibrary + the mobile
/// `ApiClient.fetchPublicGymRoutineLibrary`.
export async function fetchPublicGymRoutineLibrary(
	query = '',
	limit = 100
): Promise<{ routines: PublicGymRoutineEntry[]; error: string | null }> {
	// public_gym_routines redacts external_id + last_modified_at (migration
	// 20270319_001); created_at stands in for the required summary field.
	let q = supabase
		.from('public_gym_routines')
		.select('id, author_id, club_id, is_public_template, title, notes, exercise_count, created_at')
		.order('created_at', { ascending: false })
		.limit(limit);
	const trimmed = query.trim();
	if (trimmed) q = q.regexIMatch('title', literalSubstringPattern(trimmed));
	const { data, error } = await q;
	if (error) return { routines: [], error: error.message };
	const rows = ((data ?? []) as Array<Omit<GymRoutineSummary, 'last_modified_at'>>).map(
		(r) => ({ ...r, last_modified_at: r.created_at }) as GymRoutineSummary
	);
	const authorIds = [...new Set(rows.map((r) => r.author_id))];
	const byId = new Map<string, string | null>();
	if (authorIds.length > 0) {
		const { data: profiles } = await supabase
			.from('user_profiles')
			.select('id, display_name')
			.in('id', authorIds);
		for (const p of profiles ?? []) byId.set(p.id, p.display_name);
	}
	return {
		routines: rows.map((r) => ({ ...r, author_handle: byId.get(r.author_id) ?? null })),
		error: null,
	};
}

/** Publish (or unpublish) a personal gym routine to/from the public library.
 *  The set_gym_routine_public RPC is author-gated + refuses a club-owned
 *  routine server-side; publishing flips is_public_template on the routine
 *  itself (the routine IS the template — no deep-copy, unlike the plan
 *  library). Mirrors the mobile `ApiClient.setGymRoutinePublic`. */
export async function setGymRoutinePublic(routineId: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase.rpc('set_gym_routine_public', {
		p_routine_id: routineId,
		p_public: isPublic
	});
	if (error) throw dbError(error);
}

// ──────────────────── Race-director checkpoints (P1–P4) ────────────────────
//
// Aid-station checkpoint check-in → live results + cutoff board. The schema
// (event_checkpoints + checkpoint_crossings) lives in migration 20270201_001;
// see docs/features/race_director_ops.md. Crossings are written ONLY via the
// upsert_checkpoint_crossing RPC (server-side merge of two volunteers' stamps),
// never a direct table write. Health columns are column-locked from the public
// read and only reachable through fetch_checkpoint_crossings_for_organiser.

export interface EventCheckpoint {
	id: string;
	event_id: string;
	name: string;
	ordinal: number;
	route_marker_id: string | null;
	position_m: number | null;
	cutoff_elapsed_s: number | null;
	cutoff_clock: string | null;
	requires_weigh_in: boolean;
	created_by: string;
	created_at: string;
	updated_at: string;
}

/** Non-health subset of a crossing — what the column-locked public read returns
 *  and what the board renders for everyone. Health fields live only on
 *  OrganiserCrossing. */
export interface PublicCrossing {
	id: string;
	event_id: string;
	checkpoint_id: string;
	instance_start: string;
	user_id: string | null;
	bib: string | null;
	runner_name: string | null;
	in_time: string | null;
	out_time: string | null;
	recorded_at: string;
	updated_at: string;
}

/** Full crossing incl. Art 9 health columns — only ever returned by the
 *  organiser RPC (42501 to anyone who isn't an event organiser). */
export interface OrganiserCrossing extends PublicCrossing {
	body_weight_kg: number | null;
	body_weight_pct: number | null;
	medical_hold: boolean;
	medical_note: string | null;
	recorded_by: string | null;
}

export async function fetchEventCheckpoints(eventId: string): Promise<EventCheckpoint[]> {
	const { data, error } = await supabase
		.from(TABLES.event_checkpoints)
		.select(
			'id, event_id, name, ordinal, route_marker_id, position_m, cutoff_elapsed_s, cutoff_clock, requires_weigh_in, created_by, created_at, updated_at'
		)
		.eq('event_id', eventId)
		.order('ordinal', { ascending: true });
	if (error) throw dbError(error);
	return (data ?? []) as EventCheckpoint[];
}

export async function createEventCheckpoint(params: {
	eventId: string;
	name: string;
	ordinal: number;
	routeMarkerId?: string | null;
	positionM?: number | null;
	cutoffElapsedS?: number | null;
	cutoffClock?: string | null;
	requiresWeighIn?: boolean;
}): Promise<EventCheckpoint> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const name = params.name.trim();
	if (!name) throw new Error('Checkpoint name is required');
	const { data, error } = await supabase
		.from(TABLES.event_checkpoints)
		.insert({
			event_id: params.eventId,
			name,
			ordinal: params.ordinal,
			route_marker_id: params.routeMarkerId ?? null,
			position_m: params.positionM ?? null,
			cutoff_elapsed_s: params.cutoffElapsedS ?? null,
			cutoff_clock: params.cutoffClock ?? null,
			requires_weigh_in: params.requiresWeighIn ?? false,
			created_by: userId
		})
		.select(
			'id, event_id, name, ordinal, route_marker_id, position_m, cutoff_elapsed_s, cutoff_clock, requires_weigh_in, created_by, created_at, updated_at'
		)
		.single();
	if (error) throw dbError(error);
	return data as EventCheckpoint;
}

export async function updateEventCheckpoint(
	id: string,
	patch: Partial<{
		name: string;
		ordinal: number;
		routeMarkerId: string | null;
		positionM: number | null;
		cutoffElapsedS: number | null;
		cutoffClock: string | null;
		requiresWeighIn: boolean;
	}>
): Promise<void> {
	const row: Updatable<'event_checkpoints'> = { updated_at: new Date().toISOString() };
	if (patch.name !== undefined) row.name = patch.name.trim();
	if (patch.ordinal !== undefined) row.ordinal = patch.ordinal;
	if (patch.routeMarkerId !== undefined) row.route_marker_id = patch.routeMarkerId;
	if (patch.positionM !== undefined) row.position_m = patch.positionM;
	if (patch.cutoffElapsedS !== undefined) row.cutoff_elapsed_s = patch.cutoffElapsedS;
	if (patch.cutoffClock !== undefined) row.cutoff_clock = patch.cutoffClock;
	if (patch.requiresWeighIn !== undefined) row.requires_weigh_in = patch.requiresWeighIn;
	const { error } = await supabase.from(TABLES.event_checkpoints).update(row).eq('id', id);
	if (error) throw dbError(error);
}

export async function deleteEventCheckpoint(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.event_checkpoints).delete().eq('id', id);
	if (error) throw dbError(error);
}

/** Single writer for crossings — calls the upsert_checkpoint_crossing RPC,
 *  which authorises the caller as an organiser, merges two stamps (earliest
 *  in / latest out), and persists health fields only when the checkpoint
 *  requires_weigh_in AND p_health_consent=true. Pass health fields + consent
 *  only from the gated weigh-in UI. */
export async function upsertCheckpointCrossing(params: {
	eventId: string;
	checkpointId: string;
	instanceStart: string;
	userId?: string | null;
	bib?: string | null;
	runnerName?: string | null;
	inTime?: string | null;
	outTime?: string | null;
	healthConsent?: boolean;
	bodyWeightKg?: number | null;
	bodyWeightPct?: number | null;
	medicalHold?: boolean | null;
	medicalNote?: string | null;
}): Promise<OrganiserCrossing> {
	const { data, error } = await supabase.rpc('upsert_checkpoint_crossing', {
		p_event_id: params.eventId,
		p_checkpoint_id: params.checkpointId,
		p_instance_start: params.instanceStart,
		p_user_id: params.userId ?? null,
		p_bib: params.bib ?? null,
		p_runner_name: params.runnerName ?? null,
		p_in_time: params.inTime ?? null,
		p_out_time: params.outTime ?? null,
		p_health_consent: params.healthConsent ?? false,
		p_body_weight_kg: params.bodyWeightKg ?? null,
		p_body_weight_pct: params.bodyWeightPct ?? null,
		p_medical_hold: params.medicalHold ?? null,
		p_medical_note: params.medicalNote ?? null
	});
	if (error) throw dbError(error);
	return data as OrganiserCrossing;
}

/** Organiser board read — every crossing incl. health columns. 42501 if the
 *  caller isn't an event organiser. */
export async function fetchOrganiserCrossings(
	eventId: string,
	instanceStart: string
): Promise<OrganiserCrossing[]> {
	const { data, error } = await supabase.rpc(
		'fetch_checkpoint_crossings_for_organiser',
		{ p_event_id: eventId, p_instance_start: instanceStart },
		{ get: true }
	);
	if (error) throw dbError(error);
	return (data ?? []) as OrganiserCrossing[];
}

/** Public results read — the column-locked non-health crossing columns, gated
 *  by event-visibility RLS. Used by the account-optional public results page. */
export async function fetchPublicCrossings(
	eventId: string,
	instanceStart: string
): Promise<PublicCrossing[]> {
	const { data, error } = await supabase
		.from(TABLES.checkpoint_crossings)
		.select(
			'id, event_id, checkpoint_id, instance_start, user_id, bib, runner_name, in_time, out_time, recorded_at, updated_at'
		)
		.eq('event_id', eventId)
		.eq('instance_start', instanceStart)
		.order('checkpoint_id', { ascending: true })
		.order('in_time', { ascending: true });
	if (error) throw dbError(error);
	return (data ?? []) as PublicCrossing[];
}

/** Record an organiser DNF for a runner on the live board. Crossings carry no
 *  DNF flag (DNF derives from a blown cutoff in the projection), so an explicit
 *  organiser DNF is written through the account-optional event_results rail the
 *  public results + leaderboard already read. Supports both identities: an
 *  account row (user_id) upserts on (event,instance,user_id); a bib row upserts
 *  on (event,instance,bib). RLS gates the write to the event's organiser. */
export async function markCheckpointDnf(params: {
	eventId: string;
	instanceStart: string;
	userId?: string | null;
	bib?: string | null;
	runnerName?: string | null;
}): Promise<void> {
	if (!params.userId && !params.bib) throw new Error('DNF needs a user_id or a bib');
	const base = {
		event_id: params.eventId,
		instance_start: params.instanceStart,
		duration_s: 0,
		distance_m: 0,
		finisher_status: 'dnf' as const,
		updated_at: new Date().toISOString()
	};
	const { error } = params.userId
		? await supabase
				.from(TABLES.event_results)
				.upsert({ ...base, user_id: params.userId }, { onConflict: 'event_id,instance_start,user_id' })
		: await supabase.from(TABLES.event_results).upsert(
				{ ...base, bib: params.bib, finisher_name: params.runnerName ?? params.bib },
				{ onConflict: 'event_id,instance_start,bib' }
			);
	if (error) throw dbError(error);
}

// --- Achievements / badges ---
// Reads go through RLS: the owner sees all of their rows, a non-owner sees only
// is_public = true (the achievements_public_select policy). Awards are written
// only by the SECURITY DEFINER award function — no client insert/delete path.

/** A profile's public badges (or all badges, if you are the owner — RLS-gated). */
export async function fetchUserBadges(userId: string): Promise<Achievement[]> {
	const { data, error } = await supabase
		.from(TABLES.achievements)
		.select('*')
		.eq('user_id', userId)
		.order('earned_at', { ascending: false });
	if (error) throw dbError(error);
	return (data ?? []) as Achievement[];
}

/** The signed-in user's own badges (incl. private). Empty when signed out. */
export async function fetchMyBadges(): Promise<Achievement[]> {
	const { data: authUser } = await supabase.auth.getUser();
	const uid = authUser.user?.id;
	if (!uid) return [];
	return fetchUserBadges(uid);
}

/** Flip a badge's public visibility. Owner-only (enforced by RLS). */
export async function setBadgeVisibility(id: string, isPublic: boolean): Promise<void> {
	const { error } = await supabase
		.from(TABLES.achievements)
		.update({ is_public: isPublic })
		.eq('id', id);
	if (error) throw dbError(error);
}

/** Public read for the share page — returns null for a private / missing id. */
export async function fetchBadgeForShare(
	id: string
): Promise<{ badge: Achievement; ownerName: string | null } | null> {
	const { data, error } = await supabase
		.from(TABLES.achievements)
		.select('*')
		.eq('id', id)
		.eq('is_public', true)
		.maybeSingle();
	if (error || !data) return null;
	const badge = data as Achievement;
	const { data: profile } = await supabase
		.from('user_profiles')
		.select('display_name')
		.eq('id', badge.user_id)
		.maybeSingle();
	return { badge, ownerName: profile?.display_name ?? null };
}

export interface BadgeAwardFeedEntry {
	badge: Achievement;
	authorId: string;
	authorName: string | null;
	authorAvatarUrl: string | null;
}

/**
 * Public badge awards from people the viewer follows, cursor-paged over
 * (earned_at, id) like the run feed. Public rows only (RLS), newest first.
 */
export async function fetchFollowingBadgeAwards(opts?: {
	limit?: number;
	cursor?: { earned_at: string; id: string } | null;
}): Promise<BadgeAwardFeedEntry[]> {
	const limit = opts?.limit ?? 20;
	const authors = await resolveFollowedAuthorIds(null);
	if (authors.length === 0) return [];

	// The followee set is chunked: PostgREST serialises `.in()` into the
	// URL, so a viewer following many hundreds of people overflows the
	// gateway's request-line budget and the read is lost (decisions § 653) —
	// the whole badge feed, not a short page. Each chunk applies the same
	// cursor + ordering + limit; the global top-`limit` is a subset of the
	// union, which mergeRecencyPages collapses back down (earned_at desc,
	// id desc).
	const queryChunk = async (part: string[]) => {
		let q = supabase
			.from(TABLES.achievements)
			.select('*')
			.in('user_id', part)
			.eq('is_public', true)
			.order('earned_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(limit);
		if (opts?.cursor) {
			q = q.or(
				`earned_at.lt.${opts.cursor.earned_at},and(earned_at.eq.${opts.cursor.earned_at},id.lt.${opts.cursor.id})`
			);
		}
		const { data, error } = await q;
		if (error) throw dbError(error);
		return (data ?? []) as Achievement[];
	};

	const pages = await Promise.all(chunk(authors, FEED_FOLLOWEE_CHUNK).map(queryChunk));
	const rows = mergeRecencyPages(pages, limit, (r) => r.earned_at);
	if (rows.length === 0) return [];

	const byId = await fetchProfilesByIds([...new Set(rows.map((r) => r.user_id))]);
	return rows.map((badge) => {
		const p = byId.get(badge.user_id);
		return {
			badge,
			authorId: badge.user_id,
			authorName: p?.display_name ?? null,
			authorAvatarUrl: p?.avatar_url ?? null
		};
	});
}

// ─────────────────────── Challenges & competitions ───────────────────────

function challengeFromRow(row: {
	metric: string;
	scope: string;
	activity_type: string | null;
	[k: string]: unknown;
}): Challenge {
	return {
		...row,
		metric: row.metric as ChallengeMetric,
		scope: row.scope as ChallengeScope,
		activity_type: row.activity_type as ActivityType | null
	} as Challenge;
}

export async function fetchChallenges(
	opts: { mine?: boolean } = {}
): Promise<ChallengeWithMeta[]> {
	const userId = auth.user?.id;
	// RLS already scopes visibility (public + creator + participant + club
	// member). The `mine` filter narrows to challenges the caller has joined.
	let query = supabase
		.from(TABLES.challenges)
		.select('*')
		.order('ends_at', { ascending: true });
	const { data, error } = await query;
	if (error) throw dbError(error);
	const rows = (data ?? []).map(challengeFromRow);

	// The count comes off the row. `challenges.participant_count` is the
	// trigger-maintained, self-healing cache of exactly this number
	// (`20270308_001`, derived_state.md) and `select('*')` already carried it;
	// it was being ignored in favour of tallying a participant read that
	// spanned every listed challenge at once, with no bound. PostgREST
	// truncates a result at its configured row ceiling and reports nothing
	// when it does, so a couple of popular public challenges were enough to
	// exhaust the page: every board then under-reported, and — worse — a
	// genuine participant's own row could fall outside it, emptying their "My
	// challenges" tab and offering them "Join" on a challenge they were in.
	// This is the same read `enrichClubs` already makes of `clubs.member_count`
	// for the same reason.
	//
	// What is left needs no aggregate: the caller's OWN membership, scoped to
	// the caller, so the read is bounded by the number of challenges listed
	// rather than by how many people are in them.
	const ids = rows.map((r) => r.id);
	if (ids.length === 0) return [];
	const mineSet = new Set<string>();
	const myCompletedAt = new Map<string, string | null>();
	if (userId) {
		const { data: parts, error: partsError } = await queryChunked(ids, (part) =>
			supabase
				.from(TABLES.challenge_participants)
				.select('challenge_id, completed_at')
				.eq('user_id', userId)
				.in('challenge_id', part)
		);
		// `joined` drives the Join affordance; a dropped error offered "Join"
		// on every challenge the caller is already in.
		if (partsError) throw dbError(partsError);
		for (const p of parts ?? []) {
			mineSet.add(p.challenge_id);
			myCompletedAt.set(p.challenge_id, p.completed_at ?? null);
		}
	}
	const enriched: ChallengeWithMeta[] = rows.map((r) => ({
		...r,
		participant_count: (r as { participant_count?: number }).participant_count ?? 0,
		my_value: null,
		my_rank: null,
		joined: mineSet.has(r.id),
		completed_at: myCompletedAt.get(r.id) ?? null
	}));
	if (!opts.mine) return enriched;

	// The caller's banked value lives only in the `challenge_leaderboard`
	// aggregate, never on the `challenges` row — so without this fold every
	// joined row rendered a confident zero next to its goal while the dashboard
	// panel, reading the same aggregate, showed the real number. Auxiliary:
	// a failure here leaves my_value null, which the list renders as "not shown
	// here", not as zero.
	const joined = enriched.filter((c) => c.joined);
	try {
		return mergeMyProgress(joined, await myActiveChallenges());
	} catch (e) {
		console.debug('fetchChallenges progress enrichment failed', e);
		return joined;
	}
}

/**
 * Ranked, paginated, searchable Browse feed of public challenges the caller has
 * NOT joined. Server-side `browse_public_challenges` orders by popularity
 * (size + recent join velocity), suppresses dead boards, and excludes joined /
 * ended ones — so this never pulls the whole table to sort client-side.
 */
export async function browsePublicChallenges(
	opts: { search?: string | null; limit?: number; offset?: number } = {}
): Promise<ChallengeWithMeta[]> {
	const { data, error } = await supabase.rpc('browse_public_challenges', {
		p_search: opts.search?.trim() || undefined,
		p_limit: opts.limit ?? 24,
		p_offset: opts.offset ?? 0
	}, { get: true });
	if (error) throw dbError(error);
	type BrowseRow = {
		metric: string;
		scope: string;
		activity_type: string | null;
		participant_count: number;
		[k: string]: unknown;
	};
	return ((data ?? []) as BrowseRow[]).map((r) => ({
		...challengeFromRow(r),
		participant_count: r.participant_count ?? 0,
		my_value: null,
		my_rank: null,
		joined: false,
		completed_at: null
	}));
}

export async function fetchChallengeById(id: string): Promise<ChallengeWithMeta | null> {
	const userId = auth.user?.id;
	const { data, error } = await supabase
		.from(TABLES.challenges)
		.select('*')
		.eq('id', id)
		.maybeSingle();
	if (error) throw dbError(error);
	if (!data) return null;
	const challenge = challengeFromRow(data);
	// A dropped error here reported `participant_count: 0` and `joined: false`
	// on a challenge the caller may well have joined — so the page offered
	// "Join" to someone already in, against a board it claimed was empty. A
	// partial read failure fails the whole read.
	//
	// Scoped to the caller's own row, and the count taken off the cache on the
	// challenge row: reading every participant to find one of them and to
	// length the array made both answers depend on a page PostgREST silently
	// truncates, so a popular challenge reported a smaller board than it has
	// and could drop the viewer's own membership out of its own detail page.
	const { data: joinedRow, error: partsError } = userId
		? await supabase
				.from(TABLES.challenge_participants)
				.select('completed_at, team_club_id')
				.eq('challenge_id', id)
				.eq('user_id', userId)
				.maybeSingle()
		: { data: null, error: null };
	if (partsError) throw dbError(partsError);
	return {
		...challenge,
		participant_count: (data as { participant_count?: number }).participant_count ?? 0,
		my_value: null,
		my_rank: null,
		joined: !!joinedRow,
		completed_at: joinedRow?.completed_at ?? null,
		my_team_club_id: joinedRow?.team_club_id ?? null
	};
}

export async function createChallenge(input: {
	title: string;
	description?: string | null;
	metric: ChallengeMetric;
	scope: ChallengeScope;
	goal_value?: number | null;
	activity_type?: ActivityType | null;
	club_id?: string | null;
	starts_at: string;
	ends_at: string;
	is_public?: boolean;
}): Promise<Challenge> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from(TABLES.challenges)
		.insert({
			creator_id: userId,
			title: input.title.trim(),
			description: input.description?.trim() || null,
			metric: input.metric,
			scope: input.scope,
			goal_value: input.goal_value ?? null,
			activity_type: input.activity_type ?? null,
			club_id: input.club_id ?? null,
			starts_at: input.starts_at,
			ends_at: input.ends_at,
			is_public: input.is_public ?? true
		})
		.select()
		.single();
	if (error) {
		// Surface the create_challenge rate-limit P0001 (migration
		// 20270610_001 routed the trigger through the shared helper, so it
		// finally carries the bucket + retry figure) as the friendly
		// "wait N minutes" line instead of the editor's generic toast.
		const friendly = rateLimitErrorMessage(m, error);
		if (friendly) throw new Error(friendly);
		throw dbError(error);
	}
	return challengeFromRow(data);
}

// ─────────────────────── Charity fundraising (fundraising.md) ───────────────
// A fundraiser is polymorphic over (run | event). The public page reads the
// fundraiser row (RLS: visible when the anchor is public), the thermometer via
// fundraiser_totals, and the donation feed via fundraiser_feed (public-safe
// projection — donor identity / Stripe ids never reach the client). Donation
// checkout is a Stripe-hosted handoff; the webhook confirms the donation.

export interface CreateFundraiserInput {
	charityName: string;
	charityUrl?: string | null;
	title: string;
	story?: string | null;
	goalCents: number;
	currency?: string;
	runId?: string | null;
	eventId?: string | null;
}

function fundraiserFromRow(row: Record<string, unknown>): Fundraiser {
	return { ...(row as Fundraiser), status: row.status as FundraiserStatus };
}

/// Null means the fundraiser is not there; a failed read throws, so the
/// public page can offer a donor a retry instead of telling them the
/// campaign they were linked to does not exist.
export async function fetchFundraiserById(id: string): Promise<Fundraiser | null> {
	const { data, error } = await supabase.from('fundraisers').select('*').eq('id', id).maybeSingle();
	if (error) throw dbError(error);
	if (!data) return null;
	return fundraiserFromRow(data);
}

export async function fetchFundraiserForRun(runId: string): Promise<Fundraiser | null> {
	const { data, error } = await supabase
		.from('fundraisers')
		.select('*')
		.eq('run_id', runId)
		.maybeSingle();
	// Throws on a failed read, exactly as `fetchFundraiserById` does and for
	// the reason its comment gives: `.maybeSingle()` already distinguishes a
	// genuine miss (`{data: null, error: null}`) from a failure, and returning
	// null for both told a donor the campaign they were linked to does not
	// exist. The section's own loader catches this and keeps the owner's
	// "Create fundraiser" CTA alive — a branch that could never run while the
	// error was swallowed here.
	if (error) throw dbError(error);
	if (!data) return null;
	return fundraiserFromRow(data);
}

export async function fetchFundraiserForEvent(eventId: string): Promise<Fundraiser | null> {
	const { data, error } = await supabase
		.from('fundraisers')
		.select('*')
		.eq('event_id', eventId)
		.maybeSingle();
	// Throws on a failed read, exactly as `fetchFundraiserById` does and for
	// the reason its comment gives: `.maybeSingle()` already distinguishes a
	// genuine miss (`{data: null, error: null}`) from a failure, and returning
	// null for both told a donor the campaign they were linked to does not
	// exist. The section's own loader catches this and keeps the owner's
	// "Create fundraiser" CTA alive — a branch that could never run while the
	// error was swallowed here.
	if (error) throw dbError(error);
	if (!data) return null;
	return fundraiserFromRow(data);
}

export async function createFundraiser(input: CreateFundraiserInput): Promise<Fundraiser> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { data, error } = await supabase
		.from('fundraisers')
		.insert({
			owner_user_id: userId,
			run_id: input.runId ?? null,
			event_id: input.eventId ?? null,
			charity_name: input.charityName.trim(),
			charity_url: input.charityUrl?.trim() || null,
			title: input.title.trim(),
			story: input.story?.trim() || null,
			goal_cents: input.goalCents,
			currency: input.currency ?? 'usd'
		})
		.select('*')
		.single();
	if (error) throw dbError(error);
	return fundraiserFromRow(data);
}

export async function updateChallenge(
	id: string,
	patch: Partial<{
		title: string;
		description: string | null;
		goal_value: number | null;
		activity_type: ActivityType | null;
		starts_at: string;
		ends_at: string;
		is_public: boolean;
	}>
): Promise<void> {
	const { error } = await supabase.from(TABLES.challenges).update(patch).eq('id', id);
	if (error) throw dbError(error);
}

export async function deleteChallenge(id: string): Promise<void> {
	const { error } = await supabase.from(TABLES.challenges).delete().eq('id', id);
	if (error) throw dbError(error);
}

export async function joinChallenge(id: string, teamClubId?: string | null): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.challenge_participants)
		.insert({ challenge_id: id, user_id: userId, team_club_id: teamClubId ?? null });
	// The (challenge_id, user_id) primary key makes a double-tap — or a tap on
	// a list whose `joined` flag was computed before another tab wrote the row
	// — a duplicate, which is this call's own success condition restated.
	if (error && !isDuplicateKeyError(error)) throw dbError(error);
}

export async function leaveChallenge(id: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) throw new Error('Not authenticated');
	const { error } = await supabase
		.from(TABLES.challenge_participants)
		.delete()
		.eq('challenge_id', id)
		.eq('user_id', userId);
	if (error) throw dbError(error);
}

export async function fetchChallengeLeaderboard(
	id: string,
	byTeam = false
): Promise<ChallengeLeaderboardRow[]> {
	const { data, error } = await supabase.rpc('challenge_leaderboard', {
		p_challenge_id: id,
		p_by_team: byTeam
	}, { get: true });
	if (error) throw dbError(error);
	return (data ?? []).map((r: Record<string, unknown>) => ({
		user_id: (r.user_id as string | null) ?? null,
		display_name: (r.display_name as string | null) ?? null,
		team_club_id: (r.team_club_id as string | null) ?? null,
		value: Number(r.value ?? 0),
		rank: Number(r.rank ?? 0)
	}));
}

export async function myActiveChallenges(): Promise<ChallengeWithMeta[]> {
	const { data, error } = await supabase.rpc('my_active_challenges', undefined, { get: true });
	if (error) throw dbError(error);
	return (data ?? []).map((r: Record<string, unknown>) => ({
		...challengeFromRow(r as Parameters<typeof challengeFromRow>[0]),
		participant_count: Number(r.participant_count ?? 0),
		my_value: r.my_value === null || r.my_value === undefined ? null : Number(r.my_value),
		my_rank: r.my_rank === null || r.my_rank === undefined ? null : Number(r.my_rank),
		joined: true,
		completed_at: (r.completed_at as string | null) ?? null
	}));
}

/// Best-effort: ask the server to recompute the caller's completion for a
/// challenge after a run saves. Swallow-to-debug like other auxiliary effects —
/// the daily cron sweep is the durable backstop, so a transient failure here
/// never blocks the run save.
export async function recomputeChallengeCompletion(id: string): Promise<void> {
	const userId = auth.user?.id;
	if (!userId) return;
	try {
		const { error } = await supabase.rpc('recompute_challenge_completion', {
			p_challenge_id: id,
			p_user_id: userId
		});
		if (error) console.debug('recomputeChallengeCompletion failed', error);
	} catch (e) {
		console.debug('recomputeChallengeCompletion threw', e);
	}
}

/// Opportunistic completion recompute after a run saves: fan out
/// `recomputeChallengeCompletion` over the runner's joined challenges whose
/// window covers the run's `started_at`. Without this the daily cron sweep is
/// the ONLY path that awards a challenge_badge / stamps completed_at / sends the
/// `challenge_complete` notification — so completion lags up to ~24h and a goal
/// crossed by a late import past the sweep's tail window is never awarded.
/// Best-effort + swallow-to-debug like the plan-workout auto-match: a failure
/// here never blocks the save, and the RPC is idempotent (the challenge_badges
/// unique constraint), so a redundant call from client + cron is safe.
export async function recomputeChallengesForRun(runStartedAtIso: string): Promise<void> {
	if (!auth.user?.id) return;
	try {
		const active = await myActiveChallenges();
		const ids = challengesToRecomputeForRun(
			active.map((c) => ({
				id: c.id,
				goalValue: c.goal_value ?? null,
				startMs: Date.parse(c.starts_at),
				endMs: Date.parse(c.ends_at),
				completed: c.completed_at != null,
			})),
			Date.parse(runStartedAtIso),
		);
		for (const id of ids) {
			await recomputeChallengeCompletion(id);
		}
	} catch (e) {
		console.debug('recomputeChallengesForRun threw', e);
	}
}

export async function updateFundraiser(
	id: string,
	patch: Partial<Pick<CreateFundraiserInput, 'charityName' | 'charityUrl' | 'title' | 'story' | 'goalCents'>>
): Promise<void> {
	const row: Updatable<'fundraisers'> = { updated_at: new Date().toISOString() };
	if (patch.charityName !== undefined) row.charity_name = patch.charityName.trim();
	if (patch.charityUrl !== undefined) row.charity_url = patch.charityUrl?.trim() || null;
	if (patch.title !== undefined) row.title = patch.title.trim();
	if (patch.story !== undefined) row.story = patch.story?.trim() || null;
	if (patch.goalCents !== undefined) row.goal_cents = patch.goalCents;
	const { error } = await supabase.from('fundraisers').update(row).eq('id', id);
	if (error) throw dbError(error);
}

export async function closeFundraiser(id: string): Promise<void> {
	const { error } = await supabase
		.from('fundraisers')
		.update({ status: 'closed', updated_at: new Date().toISOString() })
		.eq('id', id);
	if (error) throw dbError(error);
}

/// Throws on a failed read. A campaign whose totals could not be fetched must
/// not render "0 raised · 0 supporters" — that tells a donor the fundraiser
/// they were sent to has raised nothing, which is a claim about someone else's
/// campaign we have no basis for. `null` stays the genuine miss: the RPC
/// answered with no rows because nothing has been donated yet.
export async function fetchFundraiserTotals(id: string): Promise<FundraiserTotals | null> {
	const { data, error } = await supabase.rpc('fundraiser_totals', { p_fundraiser_id: id }, { get: true });
	if (error) throw dbError(error);
	if (!data || (data as unknown[]).length === 0) return null;
	const row = (data as FundraiserTotals[])[0];
	return {
		raised_cents: Number(row.raised_cents) || 0,
		donor_count: Number(row.donor_count) || 0,
		goal_cents: Number(row.goal_cents) || 0,
		currency: row.currency
	};
}

/// Throws on a failed read — an empty list renders "Be the first to donate",
/// which is the same false claim in the supporters panel.
export async function fetchFundraiserFeed(
	id: string,
	limit = 50
): Promise<FundraiserFeedEntry[]> {
	const { data, error } = await supabase.rpc('fundraiser_feed', {
		p_fundraiser_id: id,
		p_limit: limit
	}, { get: true });
	if (error) throw dbError(error);
	return (data ?? []) as FundraiserFeedEntry[];
}

/// Begin a Stripe Checkout for a donation. The donations-checkout Edge Function
/// validates the fundraiser is open + visible + the owner can take payment,
/// inserts a pending donation row, and returns a hosted destination-charge
/// Checkout URL. The caller redirects the browser there. The donor may be
/// anonymous — no auth required.
///
/// `idempotencyKey` is required and the caller owns its lifetime: mint one per
/// donation ATTEMPT and re-send the same value on a retry, so the function
/// resolves back to the pending donation it already opened instead of opening a
/// second Checkout Session the donor could also pay. It cannot be minted here —
/// this function is the retry — and the server cannot derive one, because a
/// donor may be anonymous and repeat giving is legitimate (decisions § 776).
export async function startDonationCheckout(
	fundraiserId: string,
	amountCents: number,
	opts: {
		idempotencyKey: string;
		displayName?: string | null;
		message?: string | null;
		isAnonymous?: boolean;
	}
): Promise<{ url: string }> {
	const { data, error } = await supabase.functions.invoke('donations-checkout', {
		body: {
			fundraiser_id: fundraiserId,
			amount_cents: amountCents,
			idempotency_key: opts.idempotencyKey,
			display_name: opts.displayName ?? null,
			message: opts.message ?? null,
			is_anonymous: opts.isAnonymous ?? false
		}
	});
	if (error) {
		// Same unwrap as startEventCheckout. Rethrowing the raw error lost
		// the refusal, not just its wording: the function distinguishes a
		// fundraiser that has ENDED from one whose owner cannot take money
		// from a transient outage, and a donor shown one generic line
		// cannot tell "this is over" from "try again in a minute" — so they
		// retry a checkout that can never open.
		const code = await edgeFunctionErrorCode(error);
		throw new Error(code ?? (appErrorMessage(error) ?? 'donation_failed'));
	}
	const url = (data as { checkout_url?: string } | null)?.checkout_url;
	if (!url) throw new Error('No checkout URL returned');
	return { url };
}
