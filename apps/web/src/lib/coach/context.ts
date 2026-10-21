// Builds the JSON context block fed into the coach prompt: profile,
// runner prefs (HR zones, mileage goal, coach_personality), the active
// (or pinned) plan + plan weeks + plan workouts — or the season of plans
// chained after it, as `season` blocks — the most recent
// runs and lifts, and a 7-day nutrition summary — each field only when
// the runner's accepted AI disclosure names it (COACH_CONTEXT_REGISTRY).
// Pure function over a Supabase client — same code path in dev and prod.

import type { SupabaseClient } from '@supabase/supabase-js';
import {
	AI_DISCLOSURE_VERSION_COACH,
	AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING,
} from '../core/ai_disclosure';
import { SELECT_SEPARATOR, type Join } from '../core/database';
import { TABLES } from '../core/schema';
import type { Database } from '../database.types';
import type { MessageKey } from '../i18n/messages';
import { dbError } from '../core/supabase_error';
import { distinctExerciseCount } from '../gym/gym_prs';
import { pickCurrentPlan, plansFollowing } from '../training/plan_current';
import type { CoachPlanScope } from './types';

export type { CoachPlanScope };

export interface CoachContext {
	data?: unknown;
}

/// One entry per field the Coach context can send to Anthropic.
///
/// - `sentFrom` — the lowest accepted AI-disclosure version the field is sent at.
///   `buildContext` withholds it below that, field by field, so a runner who
///   accepted an older disclosure keeps a working Coach with what they agreed
///   to instead of being locked out until they re-accept.
/// - `bullet` — the consent bullet (`AiDisclosureNotice`) that names it.
/// - `namedFrom` — the disclosure version whose copy first named it. A field
///   gated below that was sent before any copy described it; that is allowed
///   only with a written `legacyReason`, so the gap is a recorded decision
///   rather than an accident.
export type CoachContextEntry =
	| {
			sentFrom: number;
			bullet: MessageKey;
			namedFrom: number;
			legacyReason?: string;
	  }
	| { notPersonalData: string };

const V1 = AI_DISCLOSURE_VERSION_COACH;
const V6 = AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING;

type Row<T extends keyof Database['public']['Tables']> = Database['public']['Tables'][T]['Row'];

/// The columns each table-backed lane selects: explicit rather than `*`, so a
/// column added to the table stays out of the Coach until it is listed here,
/// registered below and named by a consent bullet (decisions § 2220).
export const COACH_PLAN_COLUMNS = [
	'id',
	'name',
	'status',
	'goal_event',
	'goal_distance_m',
	'goal_time_seconds',
	'current_5k_seconds',
	'vdot',
	'days_per_week',
	'start_date',
	'end_date',
	'rules',
	'notes',
] as const satisfies readonly (keyof Row<'training_plans'>)[];

export const COACH_PLAN_WEEK_COLUMNS = [
	'id',
	'week_index',
	'phase',
	'target_volume_m',
	'notes',
] as const satisfies readonly (keyof Row<'plan_weeks'>)[];

export const COACH_PLAN_WORKOUT_COLUMNS = [
	'week_id',
	'scheduled_date',
	'kind',
	'target_distance_m',
	'target_duration_seconds',
	'target_pace_sec_per_km',
	'target_pace_end_sec_per_km',
	'target_pace_tolerance_sec',
	'pace_zone',
	'target_hr_min_bpm',
	'target_hr_max_bpm',
	'target_rpe_min',
	'target_rpe_max',
	'structure',
	'notes',
	'race_name',
	'race_priority',
	'completed_at',
	'manually_completed',
	'skipped_at',
] as const satisfies readonly (keyof Row<'plan_workouts'>)[];

/// `metadata` is narrowed further, key by key, by `pickAllowedRunMetadata`.
export const COACH_RUN_COLUMNS = [
	'id',
	'started_at',
	'distance_m',
	'duration_s',
	'activity_type',
	'metadata',
] as const satisfies readonly (keyof Row<'runs'>)[];

type Sel<C extends readonly string[]> = Join<C, typeof SELECT_SEPARATOR>;
const PLAN_SELECT = COACH_PLAN_COLUMNS.join(SELECT_SEPARATOR) as Sel<typeof COACH_PLAN_COLUMNS>;
const PLAN_WEEK_SELECT = COACH_PLAN_WEEK_COLUMNS.join(SELECT_SEPARATOR) as Sel<
	typeof COACH_PLAN_WEEK_COLUMNS
>;
const PLAN_WORKOUT_SELECT = COACH_PLAN_WORKOUT_COLUMNS.join(SELECT_SEPARATOR) as Sel<
	typeof COACH_PLAN_WORKOUT_COLUMNS
>;
const RUN_SELECT = COACH_RUN_COLUMNS.join(SELECT_SEPARATOR) as Sel<typeof COACH_RUN_COLUMNS>;

/// Plan-workout fields derived from the runner's heart rate, so held to the
/// same health-data consent as `runner_context.hr_zones`.
const COACH_PLAN_WORKOUT_HEALTH_COLUMNS: ReadonlySet<string> = new Set([
	'target_hr_min_bpm',
	'target_hr_max_bpm',
]);

/// Top-level keys registered field by field below (`profile.display_name`,
/// `plan_workouts.kind`, …) rather than as a whole: an `object` is one row, a
/// `list` is rows that each carry those fields, and `blocks` is a list of
/// objects whose keys are `COACH_SEASON_BLOCK_KEYS`, each withheld under the
/// same entries as the top-level key of that name.
export const COACH_CONTEXT_CONTAINERS: ReadonlyMap<string, 'object' | 'list' | 'blocks'> =
	new Map([
		['profile', 'object'],
		['runner_context', 'object'],
		['plan', 'object'],
		['plan_weeks', 'list'],
		['plan_workouts', 'list'],
		['recent_runs', 'list'],
		['season', 'blocks'],
	]);

/// What one block of `season` carries: one plan with its weeks and workouts,
/// the same three keys and fields a single plan is sent with. A season adds
/// plans, never fields, so the plan consent bullet covers it unchanged.
export const COACH_SEASON_BLOCK_KEYS: ReadonlySet<string> = new Set([
	'plan',
	'plan_weeks',
	'plan_workouts',
]);

/// The selected columns of each table-backed container, so the registry test
/// can hold the select lists and the registry to the same set.
export const COACH_CONTEXT_COLUMNS: Readonly<Record<string, readonly string[]>> = {
	plan: COACH_PLAN_COLUMNS,
	plan_weeks: COACH_PLAN_WEEK_COLUMNS,
	plan_workouts: COACH_PLAN_WORKOUT_COLUMNS,
	recent_runs: COACH_RUN_COLUMNS,
};

const SETTINGS_LEGACY =
	'Sent since the v1 Coach as part of the settings the runner gives the Coach; ' +
	'the owner judged it low sensitivity and kept it ungated so a v1-v5 ' +
	'Coach keeps working (issue #1217). v6 copy names it.';

const HR_INPUT_LEGACY =
	'An input the "configured HR zones" of the v1 copy are computed from, and ' +
	'health-consent gated since v1; kept ungated by disclosure version per ' +
	'issue #1217. v6 copy names it.';

/// The plan and runs lanes have been sent since the v1 Coach, whose plan and
/// runs bullets name them, so their fields are gated and named at v1.
const PLAN_FIELD: CoachContextEntry = {
	sentFrom: V1,
	bullet: 'coachPage.consentBulletPlan',
	namedFrom: V1,
};
const RUN_FIELD: CoachContextEntry = {
	sentFrom: V1,
	bullet: 'coachPage.consentBulletRuns',
	namedFrom: V1,
};

/// Every key `buildContext` may emit, and what discloses it (issue #1217).
/// `buildContext` throws on a key that is missing here, and
/// `context_registry.test.ts` drives every lane to prove none is, so a new
/// lane cannot reach Anthropic without a covering consent bullet.
export const COACH_CONTEXT_REGISTRY: Readonly<Record<string, CoachContextEntry>> = {
	'profile.display_name': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletCoachSettings',
		namedFrom: V6,
		legacyReason: SETTINGS_LEGACY,
	},
	'profile.preferred_unit': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletCoachSettings',
		namedFrom: V6,
		legacyReason: SETTINGS_LEGACY,
	},
	'runner_context.weekly_mileage_goal_m': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletCoachSettings',
		namedFrom: V6,
		legacyReason: SETTINGS_LEGACY,
	},
	'runner_context.coach_personality': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletCoachSettings',
		namedFrom: V6,
		legacyReason: SETTINGS_LEGACY,
	},
	'runner_context.date_of_birth': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletProfile',
		namedFrom: V1,
	},
	'runner_context.hr_zones': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletProfile',
		namedFrom: V1,
	},
	'runner_context.resting_hr_bpm': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletCoachSettings',
		namedFrom: V6,
		legacyReason: HR_INPUT_LEGACY,
	},
	'runner_context.max_hr_bpm': {
		sentFrom: V1,
		bullet: 'coachPage.consentBulletCoachSettings',
		namedFrom: V6,
		legacyReason: HR_INPUT_LEGACY,
	},
	'plan.id': PLAN_FIELD,
	'plan.name': PLAN_FIELD,
	'plan.status': PLAN_FIELD,
	'plan.goal_event': PLAN_FIELD,
	'plan.goal_distance_m': PLAN_FIELD,
	'plan.goal_time_seconds': PLAN_FIELD,
	'plan.current_5k_seconds': PLAN_FIELD,
	'plan.vdot': PLAN_FIELD,
	'plan.days_per_week': PLAN_FIELD,
	'plan.start_date': PLAN_FIELD,
	'plan.end_date': PLAN_FIELD,
	'plan.rules': PLAN_FIELD,
	'plan.notes': PLAN_FIELD,
	'plan_weeks.id': PLAN_FIELD,
	'plan_weeks.week_index': PLAN_FIELD,
	'plan_weeks.phase': PLAN_FIELD,
	'plan_weeks.target_volume_m': PLAN_FIELD,
	'plan_weeks.notes': PLAN_FIELD,
	'plan_workouts.week_id': PLAN_FIELD,
	'plan_workouts.scheduled_date': PLAN_FIELD,
	'plan_workouts.kind': PLAN_FIELD,
	'plan_workouts.target_distance_m': PLAN_FIELD,
	'plan_workouts.target_duration_seconds': PLAN_FIELD,
	'plan_workouts.target_pace_sec_per_km': PLAN_FIELD,
	'plan_workouts.target_pace_end_sec_per_km': PLAN_FIELD,
	'plan_workouts.target_pace_tolerance_sec': PLAN_FIELD,
	'plan_workouts.pace_zone': PLAN_FIELD,
	// Null without health-data consent (COACH_PLAN_WORKOUT_HEALTH_COLUMNS).
	'plan_workouts.target_hr_min_bpm': PLAN_FIELD,
	'plan_workouts.target_hr_max_bpm': PLAN_FIELD,
	'plan_workouts.target_rpe_min': PLAN_FIELD,
	'plan_workouts.target_rpe_max': PLAN_FIELD,
	'plan_workouts.structure': PLAN_FIELD,
	'plan_workouts.notes': PLAN_FIELD,
	'plan_workouts.race_name': PLAN_FIELD,
	'plan_workouts.race_priority': PLAN_FIELD,
	'plan_workouts.completed_at': PLAN_FIELD,
	'plan_workouts.manually_completed': PLAN_FIELD,
	'plan_workouts.skipped_at': PLAN_FIELD,
	'recent_runs.id': RUN_FIELD,
	'recent_runs.started_at': RUN_FIELD,
	'recent_runs.distance_m': RUN_FIELD,
	'recent_runs.duration_s': RUN_FIELD,
	'recent_runs.activity_type': RUN_FIELD,
	// Narrowed key by key by pickAllowedRunMetadata, avg_bpm only with
	// health-data consent.
	'recent_runs.metadata': RUN_FIELD,
	recent_lifts: { sentFrom: V6, bullet: 'coachPage.consentBulletLifts', namedFrom: V6 },
	nutrition_7d: { sentFrom: V6, bullet: 'coachPage.consentBulletNutrition', namedFrom: V6 },
	now_iso: { notPersonalData: 'The server clock, so the model knows what "today" is.' },
};

/// Whether `path` may be sent to a runner who accepted `disclosureVersion`.
/// An unregistered path throws: sending it would be sending data no consent
/// bullet names, and the handler turns the throw into a 503 rather than a
/// Coach reply built on it.
export function coachContextAllows(path: string, disclosureVersion: number): boolean {
	const entry = COACH_CONTEXT_REGISTRY[path];
	if (!entry) {
		throw new Error(`coach context key "${path}" is not in COACH_CONTEXT_REGISTRY`);
	}
	return 'notPersonalData' in entry || disclosureVersion >= entry.sentFrom;
}

/// Drop every field the runner's accepted disclosure does not cover, and
/// throw on any field the registry does not know. Applied to the assembled
/// context as the last step, so it holds for every lane, present and future.
export function withholdUndisclosed(
	data: Record<string, unknown>,
	disclosureVersion: number,
): Record<string, unknown> {
	const out: Record<string, unknown> = {};
	for (const [key, value] of Object.entries(data)) {
		const container = COACH_CONTEXT_CONTAINERS.get(key);
		if (container === 'blocks' && value != null) {
			out[key] = (value as Record<string, unknown>[]).map((block) => {
				for (const inner of Object.keys(block)) {
					if (!COACH_SEASON_BLOCK_KEYS.has(inner)) {
						throw new Error(`coach context key "${key}.${inner}" is not a season block key`);
					}
				}
				return withholdUndisclosed(block, disclosureVersion);
			});
			continue;
		}
		if (container) {
			if (value == null) {
				out[key] = value;
				continue;
			}
			const withhold = (row: Record<string, unknown>) => {
				const inner: Record<string, unknown> = {};
				for (const [field, v] of Object.entries(row)) {
					if (coachContextAllows(`${key}.${field}`, disclosureVersion)) inner[field] = v;
				}
				return inner;
			};
			out[key] =
				container === 'list'
					? (value as Record<string, unknown>[]).map(withhold)
					: withhold(value as Record<string, unknown>);
			continue;
		}
		if (coachContextAllows(key, disclosureVersion)) out[key] = value;
	}
	return out;
}

/// Holds the emitted shape to the column list, whatever the client returned.
function pickColumns(row: unknown, columns: readonly string[]): Record<string, unknown> {
	const r = row as Record<string, unknown>;
	const out: Record<string, unknown> = {};
	for (const c of columns) if (c in r) out[c] = r[c];
	return out;
}

/// The slice of the `get_my_profile()` row the coach context reads. The
/// handler fetches this row for the consent gate and passes it in, so
/// the same SECURITY DEFINER RPC isn't issued twice per coach message.
export interface CoachProfileRow {
	display_name: string | null;
	preferred_unit: string | null;
	health_data_consent_at: string | null;
}

type PlanWindowRow = { id: string; start_date: string; end_date: string };

/// One plan as the Coach is sent it, with the weeks and workouts of it that
/// fall in the week window.
interface PlanBlock {
	plan: Record<string, unknown>;
	plan_weeks: Record<string, unknown>[];
	plan_workouts: Record<string, unknown>[];
}

const WEEK_MS = 7 * 86_400_000;

async function activePlanRows(supabase: SupabaseClient, userId: string): Promise<PlanWindowRow[]> {
	const { data, error } = await supabase
		.from('training_plans')
		.select(PLAN_SELECT)
		.eq('user_id', userId)
		.eq('status', 'active')
		.eq('is_template', false)
		.order('start_date', { ascending: true });
	if (error) throw dbError(error);
	return (data ?? []) as unknown as PlanWindowRow[];
}

async function pinnedPlanRow(
	supabase: SupabaseClient,
	userId: string,
	planId: string,
): Promise<PlanWindowRow | null> {
	const { data, error } = await supabase
		.from('training_plans')
		.select(PLAN_SELECT)
		.eq('id', planId)
		.eq('user_id', userId)
		.maybeSingle();
	if (error) throw dbError(error);
	return (data ?? null) as unknown as PlanWindowRow | null;
}

/// The plans `scope` covers, in chain order, the anchor first. Several plans
/// can be active at once when their windows don't overlap (decisions § 2008);
/// without a pinned plan the anchor is the one plan_current.ts picks, or the
/// next to start when none is current. `today` is the runner's local date,
/// which the handler takes from the request and checks against its own clock
/// (decisions § 2052). A failed read throws: answering as if the runner had no
/// plan would be a confident wrong answer.
async function plansInScope(
	supabase: SupabaseClient,
	userId: string,
	planId: string | null,
	scope: CoachPlanScope,
	today: string,
): Promise<PlanWindowRow[]> {
	if (scope === 'none') return [];
	if (scope === 'plan' && planId) {
		const pinned = await pinnedPlanRow(supabase, userId, planId);
		return pinned ? [pinned] : [];
	}
	const [pinned, active] = await Promise.all([
		planId ? pinnedPlanRow(supabase, userId, planId) : Promise.resolve(null),
		activePlanRows(supabase, userId),
	]);
	let anchor = pinned;
	if (!planId) {
		const { current, upcoming } = pickCurrentPlan(active, today);
		anchor = current ?? upcoming;
	}
	if (!anchor) return [];
	return scope === 'season' ? plansFollowing(anchor, active) : [anchor];
}

/// The week window the Coach reads, anchored on the first plan in scope: from
/// COACH_PLAN_WEEKS_LOOKBACK weeks before the anchor's current week, for
/// COACH_PLAN_WEEKS_CAP weeks. A later plan in a season contributes only the
/// weeks that start inside it, so a season is bounded by the same window as a
/// single plan, not by how many plans it holds. Week `i` of a plan starts
/// `7 * i` days after its `start_date`. Exported for its unit test.
export function coachPlanWeekWindow(
	anchorStart: string,
	today: string,
): { fromMs: number; toMs: number } {
	const startMs = Date.parse(anchorStart);
	const todayMs = Date.parse(today);
	if (!Number.isFinite(startMs) || !Number.isFinite(todayMs)) {
		return { fromMs: -Infinity, toMs: Infinity };
	}
	const currentWeek = Math.max(0, Math.floor((todayMs - startMs) / WEEK_MS));
	const fromMs = startMs + Math.max(0, currentWeek - COACH_PLAN_WEEKS_LOOKBACK) * WEEK_MS;
	return { fromMs, toMs: fromMs + COACH_PLAN_WEEKS_CAP * WEEK_MS };
}

/// The first week index of a plan starting at `planStart` that is still inside
/// a window beginning at `fromMs`: a week that straddles the window's start
/// counts, as the anchor's current week does.
function firstWeekInWindow(planStart: string, fromMs: number): number {
	const startMs = Date.parse(planStart);
	if (!Number.isFinite(startMs) || !Number.isFinite(fromMs)) return 0;
	return Math.max(0, Math.floor((fromMs - startMs) / WEEK_MS));
}

/// The plans in scope with the weeks and workouts of theirs that fall in the
/// week window, at most COACH_PLAN_WEEKS_CAP weeks and COACH_PLAN_WORKOUTS_CAP
/// workouts across all of them, so a long plan or a long season cannot grow the
/// prompt without limit (bug-hunt 2026-07-r2 H2, issue #374). A later plan with
/// no week in the window is left out. A plan whose whole run is before the
/// window (a fully elapsed plan viewed explicitly) falls back to its final
/// weeks, so the coach still sees the taper and race rather than an empty plan.
async function loadPlanBlocks(
	supabase: SupabaseClient,
	plans: PlanWindowRow[],
	today: string,
	healthConsentGranted: boolean,
): Promise<PlanBlock[]> {
	if (plans.length === 0) return [];
	const { fromMs, toMs } = coachPlanWeekWindow(plans[0].start_date, today);
	const inWindow = plans.filter((p, i) => i === 0 || !(Date.parse(p.start_date) >= toMs));
	const weekReads = await Promise.all(
		inWindow.map((p) =>
			supabase
				.from('plan_weeks')
				.select(PLAN_WEEK_SELECT)
				.eq('plan_id', p.id)
				.gte('week_index', firstWeekInWindow(p.start_date, fromMs))
				.order('week_index', { ascending: true })
				.limit(COACH_PLAN_WEEKS_CAP),
		),
	);
	let budget = COACH_PLAN_WEEKS_CAP;
	const weeksByPlan = inWindow.map((p, i) => {
		const { data, error } = weekReads[i];
		if (error) throw dbError(error);
		const startMs = Date.parse(p.start_date);
		const rows = ((data ?? []) as unknown as { week_index: number }[]).filter(
			(w) => !(startMs + w.week_index * WEEK_MS >= toMs),
		);
		const taken = rows.slice(0, Math.max(0, budget));
		budget -= taken.length;
		return taken as unknown as Record<string, unknown>[];
	});
	if (weeksByPlan.every((w) => w.length === 0)) {
		const { data, error } = await supabase
			.from('plan_weeks')
			.select(PLAN_WEEK_SELECT)
			.eq('plan_id', plans[0].id)
			.order('week_index', { ascending: false })
			.limit(COACH_PLAN_WEEKS_CAP);
		if (error) throw dbError(error);
		weeksByPlan[0] = ((data ?? []) as unknown as Record<string, unknown>[]).slice().reverse();
	}

	const weekIds = weeksByPlan.flat().map((w) => w.id as string);
	const workoutsByWeek = new Map<string, Record<string, unknown>[]>();
	if (weekIds.length > 0) {
		const { data, error } = await supabase
			.from('plan_workouts')
			.select(PLAN_WORKOUT_SELECT)
			.in('week_id', weekIds)
			.order('scheduled_date', { ascending: true })
			.limit(COACH_PLAN_WORKOUTS_CAP);
		if (error) throw dbError(error);
		for (const w of data ?? []) {
			const row = pickColumns(w, COACH_PLAN_WORKOUT_COLUMNS);
			if (!healthConsentGranted) {
				for (const c of COACH_PLAN_WORKOUT_HEALTH_COLUMNS) {
					if (c in row) row[c] = null;
				}
			}
			const weekId = row.week_id as string;
			if (!workoutsByWeek.has(weekId)) workoutsByWeek.set(weekId, []);
			workoutsByWeek.get(weekId)!.push(row);
		}
	}

	const blocks: PlanBlock[] = [];
	inWindow.forEach((p, i) => {
		const weeks = weeksByPlan[i];
		if (i > 0 && weeks.length === 0) return;
		blocks.push({
			plan: pickColumns(p, COACH_PLAN_COLUMNS),
			plan_weeks: weeks.map((w) => pickColumns(w, COACH_PLAN_WEEK_COLUMNS)),
			plan_workouts: weeks.flatMap((w) => workoutsByWeek.get(w.id as string) ?? []),
		});
	});
	return blocks;
}

export async function buildContext(
	supabase: SupabaseClient,
	userId: string,
	planId: string | null,
	runsLimit: number,
	profileRow: CoachProfileRow | null,
	today: string,
	disclosureVersion: number,
	planScope: CoachPlanScope = 'plan',
): Promise<CoachContext> {
	// `profileRow` is the `get_my_profile()` result the handler already
	// fetched for the coach-consent gate — passed in rather than re-queried
	// so a duplicate SECURITY DEFINER RPC round-trip doesn't fire on every
	// coach message. The RPC is the self-read path because `subscription_tier`
	// is column-level revoked from authenticated callers (migration
	// 20260707_001). `subscription_tier` is intentionally dropped from the
	// profile projection emitted to Anthropic — the handler already knows
	// tier and adjusts limits server-side; sending billing-tier metadata to
	// a sub-processor violates Art 5(1)(c) data minimisation (audit/coach
	// May 2026 Medium #9).
	const profileRowTyped = profileRow;
	const profile = profileRowTyped
		? {
				display_name: profileRowTyped.display_name,
				preferred_unit: profileRowTyped.preferred_unit,
			}
		: null;

	// GDPR Art 9(2)(a): special-category health-adjacent data (DOB +
	// HR metrics, dietary intake) only flows to Anthropic when the user
	// has actively granted health-data consent via Settings → Preferences.
	// The `coach_consent_at` (Art 6(1)(a) AI consent) gate in handler.ts
	// authorises using the Coach AT ALL; this is the second, distinct gate
	// for the *health* category. See migration
	// `20260921_001_user_profiles_gdpr_consent_timestamps.sql` for the
	// two-gate design and audit/coach May 2026 High #1. Derived from the
	// passed-in profile row, so it's known before any query — the nutrition
	// lane below can join the parallel fan-out instead of waiting on a
	// profile fetch. This is the CALLER's consent; because every lane is now
	// scoped to `userId` (the caller), the data being gated is the caller's
	// own — the consent tenant and data tenant match by construction.
	const healthConsentGranted = profileRowTyped?.health_data_consent_at != null;

	// These five reads are mutually independent: the active plan (+ its
	// week→workout sub-chain), recent runs, recent lifts (+ their sets),
	// user settings, and the consent-gated 7-day nutrition rollup. They
	// used to run as five sequential awaits, so every coach message stacked
	// ~5 Supabase round-trips of latency before the first token streamed.
	// Fan them out with Promise.all so the endpoint pays ~one round-trip
	// instead (perf-hunt 2026-06-10). Each lane keeps its own internal
	// sequential sub-chain where one query genuinely feeds the next.
	// Scope every data lane to the caller explicitly — do NOT lean on RLS
	// alone. Migrations 20261103_001 + 20261116_001 additively granted an
	// active coach read on their athletes' runs/plans, so an RLS-only read
	// from a coach's own /coach chat would UNION the athlete's rows into the
	// coach's context (and the no-plan_id branch could return the athlete's
	// active plan). The `.eq('user_id', userId)` in plansInScope keeps this
	// the caller's own data; plan_weeks/plan_workouts inherit the scope
	// transitively through the plan (they carry no user_id column).
	const planLane = (async (): Promise<PlanBlock[]> =>
		loadPlanBlocks(
			supabase,
			await plansInScope(supabase, userId, planId, planScope, today),
			today,
			healthConsentGranted,
		))();

	// Persona-hunt Round 2 finding Pro #3. `metadata` is a free-form
	// jsonb bag (docs/backend/metadata.md). Some keys are useful coaching
	// signal (activity_type, avg_bpm, workout_kind, etc.); many are
	// not — `notes` (free-form, anything the runner typed), `event`
	// + `position` (parkrun athlete + finishing place), raw `laps[]`
	// arrays, `imported_from`, `strava_id` / `garmin_id`, internal
	// flags like `recovered_from_crash`, owner-only data the
	// `public_runs` view explicitly strips. Selecting metadata whole
	// shipped all of it to Anthropic — defence-in-depth violation
	// against the same Art 5(1)(c) minimisation the surrounding code
	// (subscription_tier strip, health-consent gate) defends elsewhere.
	//
	// Allowlist the keys the coach actually uses for advice. Pre-fix
	// behaviour for unallowlisted keys: included. Post-fix: dropped.
	const runsLane = (async () => {
		const { data: rawRecentRuns } = await supabase
			.from(TABLES.runs)
			.select(RUN_SELECT)
			.eq('user_id', userId)
			.order('started_at', { ascending: false })
			.limit(runsLimit);
		return (rawRecentRuns ?? []).map((r) => ({
			...pickColumns(r, COACH_RUN_COLUMNS),
			metadata: pickAllowedRunMetadata(
				r.metadata as Record<string, unknown> | null,
				healthConsentGranted,
			),
		}));
	})();

	// Tier-1 multi-modal coach context (docs/features/multi_modal.md §
	// "Cross-modality touches"). The coach SEES recent lift sessions +
	// a 7-day nutrition rollup and reasons about them — advisory, it
	// never auto-mutates a plan. Both are BOUNDED so prompt size + per-
	// call cost stay flat as history grows: a fixed cap of recent lift
	// sessions (summaries, not raw sets) and a 7-day rolling nutrition
	// summary (daily averages, not every food row). When the user logs
	// neither, both self-hide (empty array / null) and the JSON stays
	// the same size as today's running-only payload.
	//
	// gym_workouts / food_log are owner-only today, but scope them to the
	// caller explicitly anyway — the same not-rely-on-RLS-alone defence the
	// plan/runs lanes now apply, so a future additive coach-visibility grant
	// (as already happened to runs/plans) can't quietly leak an athlete's
	// lifts/nutrition into a coach's own context. gym_sets inherits the scope
	// transitively through the workout ids (no user_id column).
	//
	// Both lanes also need the v6 disclosure, the first copy that names them
	// (issue #1217). Below it they don't query at all rather than querying
	// and being stripped: what is never read can't leak by a later refactor.
	const liftsLane = (async (): Promise<LiftSummary[]> => {
		if (!coachContextAllows('recent_lifts', disclosureVersion)) return [];
		const { data: liftWorkouts } = await supabase
			.from(TABLES.gym_workouts)
			.select('id, title, started_at')
			.eq('user_id', userId)
			.order('started_at', { ascending: false })
			.limit(COACH_LIFTS_CAP);
		if (!liftWorkouts || liftWorkouts.length === 0) return [];
		const ids = (liftWorkouts as { id: string }[]).map((w) => w.id);
		const { data: liftSets } = await supabase
			.from(TABLES.gym_sets)
			.select('workout_id, exercise_name, reps, weight_kg')
			.in('workout_id', ids);
		return summarizeRecentLifts(
			liftWorkouts as LiftWorkoutRow[],
			(liftSets ?? []) as LiftSetRow[],
		);
	})();

	const settingsLane = (async (): Promise<Record<string, unknown>> => {
		const { data: userSettings } = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.maybeSingle();
		return (userSettings?.prefs ?? {}) as Record<string, unknown>;
	})();

	// Nutrition is health-adjacent (dietary intake), so it crosses the
	// same Art 9(2)(a) special-category boundary as DOB / HR and is
	// gated on the SAME health-data consent. Lifts (working-set tonnage)
	// are activity data like runs — ungated, sent whenever logged. A 200-
	// row cap over a 7-day window is plenty to compute daily averages and
	// bounds the worst case (a power-logger).
	const nutritionLane = (async (): Promise<NutritionSummary | null> => {
		if (healthConsentGranted && coachContextAllows('nutrition_7d', disclosureVersion)) {
			const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000).toISOString();
			const { data: foodRows } = await supabase
				.from(TABLES.food_log)
				.select('started_at, calories, protein_g, carbs_g, fat_g')
				.eq('user_id', userId)
				.gte('started_at', sevenDaysAgo)
				.order('started_at', { ascending: false })
				.limit(200);
			return summarizeNutrition((foodRows ?? []) as FoodLogRow[], new Date());
		}
		return null;
	})();

	const [planBlocks, recentRuns, recentLifts, prefs, nutrition7d] =
		await Promise.all([planLane, runsLane, liftsLane, settingsLane, nutritionLane]);

	// A season is sent as blocks so each week and workout stays with its plan;
	// a single plan keeps the flat keys the Coach has always been sent.
	const planContext: Record<string, unknown> =
		planScope === 'season'
			? { season: planBlocks }
			: {
					plan: planBlocks[0]?.plan ?? null,
					plan_weeks: planBlocks[0]?.plan_weeks ?? [],
					plan_workouts: planBlocks[0]?.plan_workouts ?? [],
				};

	const runnerContext = {
		// Non-health prefs are always safe to send.
		weekly_mileage_goal_m: prefs.weekly_mileage_goal_m ?? null,
		coach_personality: prefs.coach_personality ?? null,
		// Health-category fields — gated on Art 9 consent. When
		// consent has not been (or has been withdrawn from)
		// `health_data_consent_at`, these emit as null so the model
		// produces generic advice instead of HR-zone-specific advice.
		date_of_birth: healthConsentGranted ? (prefs.date_of_birth ?? null) : null,
		resting_hr_bpm: healthConsentGranted ? (prefs.resting_hr_bpm ?? null) : null,
		max_hr_bpm: healthConsentGranted ? (prefs.max_hr_bpm ?? null) : null,
		hr_zones: healthConsentGranted ? (prefs.hr_zones ?? null) : null,
	};

	return {
		data: withholdUndisclosed({
			profile: profile ?? null,
			runner_context: runnerContext,
			...planContext,
			recent_runs: recentRuns ?? [],
			recent_lifts: recentLifts,
			nutrition_7d: nutrition7d,
			// LAST, not first: this is the only ever-changing field, and the
			// serialized context is sent as an Anthropic ephemeral-cache block
			// (providers.ts) that only hits on a byte-identical prefix. Leading
			// with the timestamp busts the cache on every message; trailing it
			// keeps the whole prefix stable across a conversation. Issue #390.
			now_iso: new Date().toISOString(),
		}, disclosureVersion),
	};
}

/// Fixed cap on lift sessions sent to the coach. Bounded so the prompt
/// size + per-call cost stay roughly flat as gym history grows — the
/// coach reasons about recent training, not a lifetime log.
export const COACH_LIFTS_CAP = 8;

/// Fixed caps on the plan window sent to the coach. Bounded — like
/// recent_runs / recent_lifts — so a long or REST-inserted plan, or a
/// season of several, can't grow the prompt without limit. `WEEKS_CAP`
/// covers a full marathon block; `WORKOUTS_CAP` is WEEKS_CAP × the 7-day
/// max. `WEEKS_LOOKBACK` keeps a couple of recently-completed weeks for
/// adherence context while the cap fills with the current + upcoming
/// weeks. Both caps hold across every plan of a season together.
export const COACH_PLAN_WEEKS_CAP = 20;
export const COACH_PLAN_WORKOUTS_CAP = 140;
export const COACH_PLAN_WEEKS_LOOKBACK = 2;

interface LiftWorkoutRow {
	id: string;
	title: string | null;
	started_at: string;
}

interface LiftSetRow {
	workout_id: string;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
}

export interface LiftSummary {
	/// Local-ish calendar date (YYYY-MM-DD) of the session.
	date: string;
	title: string | null;
	/// Distinct exercises in the session, counted on the canonical grouping
	/// key so a lift logged under two spellings is one exercise here as it is
	/// everywhere else in the app.
	exercises: number;
	/// Total logged sets.
	sets: number;
	/// Σ(reps · weight_kg) across the session, rounded. Bodyweight-only
	/// sets (no weight) contribute 0, matching the lift-load model.
	volume_kg: number;
}

export interface NutritionSummary {
	/// Distinct days with at least one logged item in the window.
	days_logged: number;
	/// Daily averages over the days logged (total ÷ days_logged), rounded.
	/// Null when no row in the window carried that macro.
	avg_calories: number | null;
	avg_protein_g: number | null;
	avg_carbs_g: number | null;
	avg_fat_g: number | null;
}

/// Collapse recent gym workouts + their sets into bounded per-session
/// summaries (no raw set rows cross the sub-processor boundary). Pure +
/// unit-tested. Workouts arrive newest-first; we keep the first `cap`.
export function summarizeRecentLifts(
	workouts: LiftWorkoutRow[],
	sets: LiftSetRow[],
	cap: number = COACH_LIFTS_CAP,
): LiftSummary[] {
	const byWorkout = new Map<string, LiftSetRow[]>();
	for (const s of sets) {
		const arr = byWorkout.get(s.workout_id) ?? [];
		arr.push(s);
		byWorkout.set(s.workout_id, arr);
	}
	return workouts.slice(0, cap).map((w) => {
		const mine = byWorkout.get(w.id) ?? [];
		let volume = 0;
		for (const s of mine) {
			if (
				s.reps != null &&
				s.weight_kg != null &&
				s.reps > 0 &&
				s.weight_kg > 0
			) {
				volume += s.reps * s.weight_kg;
			}
		}
		return {
			date: w.started_at.slice(0, 10),
			title: w.title,
			// Counted on the canonical grouping key, not the runtime's own
			// fold: the model is being told how many exercises the session
			// held, and every keyed surface in the app answers that with
			// `normaliseExerciseName` (§ 1274).
			exercises: distinctExerciseCount(mine.map((s) => s.exercise_name)),
			sets: mine.length,
			volume_kg: Math.round(volume),
		};
	});
}

interface FoodLogRow {
	started_at: string;
	calories: number | null;
	protein_g: number | null;
	carbs_g: number | null;
	fat_g: number | null;
}

/// Roll a window of food-log rows into 7-day daily averages. Pure +
/// unit-tested. Returns null when nothing falls in the trailing 7-day
/// window so the key is omitted (self-hiding). Averages divide the
/// macro total by the number of DAYS LOGGED (not row count), so the
/// figure reads as "on a day you log, you average X".
export function summarizeNutrition(
	rows: FoodLogRow[],
	now: Date,
): NutritionSummary | null {
	const cutoff = now.getTime() - 7 * 86_400_000;
	const recent = rows.filter((r) => {
		const t = new Date(r.started_at).getTime();
		return Number.isFinite(t) && t >= cutoff;
	});
	if (recent.length === 0) return null;
	const days = new Set<string>();
	let cal = 0;
	let calN = 0;
	let pro = 0;
	let proN = 0;
	let carb = 0;
	let carbN = 0;
	let fat = 0;
	let fatN = 0;
	for (const r of recent) {
		days.add(r.started_at.slice(0, 10));
		if (r.calories != null) {
			cal += r.calories;
			calN++;
		}
		if (r.protein_g != null) {
			pro += r.protein_g;
			proN++;
		}
		if (r.carbs_g != null) {
			carb += r.carbs_g;
			carbN++;
		}
		if (r.fat_g != null) {
			fat += r.fat_g;
			fatN++;
		}
	}
	const dayCount = days.size;
	const avg = (total: number, present: number): number | null =>
		present > 0 && dayCount > 0 ? Math.round(total / dayCount) : null;
	return {
		days_logged: dayCount,
		avg_calories: avg(cal, calN),
		avg_protein_g: avg(pro, proN),
		avg_carbs_g: avg(carb, carbN),
		avg_fat_g: avg(fat, fatN),
	};
}

/// Keys on `runs.metadata` that the coach is allowed to see. Adding a
/// key here is a deliberate decision — every key crosses a sub-
/// processor boundary and must justify its coaching value. Audited
/// against docs/backend/metadata.md.
const COACH_METADATA_ALLOWLIST: ReadonlySet<string> = new Set([
	'avg_bpm', // Art 9 heart-rate — stripped unless health consent granted (COACH_HEALTH_METADATA_KEYS); HR zones use it
	'workout_kind', // structured workouts — coach reads to track plan adherence
	'workout_step_results', // per-step planned-vs-actual; coach summarises adherence
	'manual_completion', // user marked a workout done — affects plan completion
	'is_indoor', // treadmill / track session — coach phrases advice differently
	'elevation_m', // total gain — useful for route-context advice
]);

/// Allowlisted keys that are Art 9(2)(a) special-category health data.
/// Stripped from the coach payload unless the runner granted health-data
/// consent — the same gate `runner_context` applies to DOB / HR zones,
/// now enforced at the per-run metadata layer too.
const COACH_HEALTH_METADATA_KEYS: ReadonlySet<string> = new Set(['avg_bpm']);

export function pickAllowedRunMetadata(
	metadata: Record<string, unknown> | null,
	healthConsentGranted: boolean,
): Record<string, unknown> | null {
	if (!metadata) return null;
	const out: Record<string, unknown> = {};
	for (const key of Object.keys(metadata)) {
		if (!COACH_METADATA_ALLOWLIST.has(key)) continue;
		if (!healthConsentGranted && COACH_HEALTH_METADATA_KEYS.has(key)) continue;
		out[key] = metadata[key];
	}
	// Return null when the allowlist would emit an empty object so
	// the JSON payload stays compact + omits the key entirely.
	return Object.keys(out).length === 0 ? null : out;
}
