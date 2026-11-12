// What the coach assistant sends to Anthropic about an athlete (issue #1215
// Phase 4). Shared AI Coach answers (kind coach_share) are left out of the
// thread: the athlete shared them with the coach, not with the AI under the
// coach's account, and they can carry health-derived advice. Messages from
// before the coaching link began are left out too. Every field is registered against the athlete's per-link consent
// copy, the #1217 pattern: `withholdUnconsented` drops a field the athlete's
// accepted version does not name and throws on one the registry does not
// know, so a new lane cannot reach the model without a bullet that names it.
//
// The reads run on the COACH's session. RLS already lets an active coach read
// the athlete's runs and plans (§ 98, 20261116_001) and their own
// conversation; each read is scoped to the athlete explicitly anyway. No
// health data is read at all: no heart rate, no metadata, no nutrition, no
// date of birth.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { MessageKey } from '../../i18n/messages';
import { dbError } from '../../core/supabase_error';
import { TABLES } from '../../core/schema';

export type CoachAssistEntry =
	| { sentFrom: number; bullet: MessageKey }
	| { coachOwn: string }
	| { notPersonalData: string };

const THREAD: CoachAssistEntry = { sentFrom: 1, bullet: 'coachAssist.consentBulletThread' };
const PLAN: CoachAssistEntry = { sentFrom: 1, bullet: 'coachAssist.consentBulletPlan' };
const RUNS: CoachAssistEntry = { sentFrom: 1, bullet: 'coachAssist.consentBulletRuns' };

export const COACH_ASSIST_CONTAINERS: ReadonlyMap<string, 'object' | 'list'> = new Map([
	['thread', 'list'],
	['plan', 'object'],
	['upcoming_workouts', 'list'],
	['recent_runs', 'list'],
]);

export const COACH_ASSIST_REGISTRY: Readonly<Record<string, CoachAssistEntry>> = {
	'thread.from': THREAD,
	'thread.text': THREAD,
	'thread.sent_at': THREAD,
	'plan.name': PLAN,
	'plan.goal_event': PLAN,
	'plan.goal_distance_m': PLAN,
	'plan.goal_time_seconds': PLAN,
	'plan.start_date': PLAN,
	'plan.end_date': PLAN,
	'upcoming_workouts.scheduled_date': PLAN,
	'upcoming_workouts.kind': PLAN,
	'upcoming_workouts.target_distance_m': PLAN,
	'upcoming_workouts.target_duration_seconds': PLAN,
	'upcoming_workouts.target_pace_sec_per_km': PLAN,
	'upcoming_workouts.completed_at': PLAN,
	'upcoming_workouts.skipped_at': PLAN,
	'recent_runs.started_at': RUNS,
	'recent_runs.distance_m': RUNS,
	'recent_runs.duration_s': RUNS,
	'recent_runs.activity_type': RUNS,
	coach_request: {
		coachOwn: 'What the coach types; covered by the coach\'s own AI disclosure (v7).',
	},
	mode: { notPersonalData: 'Whether the coach asked for a reply or a plan suggestion.' },
	today: { notPersonalData: 'The coach\'s local date, so "tomorrow" means something.' },
};

/** Whether `path` may be sent for an athlete who accepted `consentVersion`. */
export function coachAssistAllows(path: string, consentVersion: number): boolean {
	const entry = COACH_ASSIST_REGISTRY[path];
	if (!entry) throw new Error(`coach assist key "${path}" is not in COACH_ASSIST_REGISTRY`);
	return !('sentFrom' in entry) || consentVersion >= entry.sentFrom;
}

/** Drop what the athlete's consent does not name; throw on an unregistered key. */
export function withholdUnconsented(
	data: Record<string, unknown>,
	consentVersion: number,
): Record<string, unknown> {
	const out: Record<string, unknown> = {};
	for (const [key, value] of Object.entries(data)) {
		const container = COACH_ASSIST_CONTAINERS.get(key);
		if (!container) {
			if (coachAssistAllows(key, consentVersion)) out[key] = value;
			continue;
		}
		if (value == null) {
			out[key] = value;
			continue;
		}
		const pick = (row: Record<string, unknown>) => {
			const inner: Record<string, unknown> = {};
			for (const [field, v] of Object.entries(row)) {
				if (coachAssistAllows(`${key}.${field}`, consentVersion)) inner[field] = v;
			}
			return inner;
		};
		out[key] =
			container === 'list'
				? (value as Record<string, unknown>[]).map(pick)
				: pick(value as Record<string, unknown>);
	}
	return out;
}

export const COACH_ASSIST_THREAD_CAP = 20;
export const COACH_ASSIST_MESSAGE_CHARS = 1000;
export const COACH_ASSIST_RUNS_CAP = 10;
export const COACH_ASSIST_WORKOUT_DAYS = 14;
export const COACH_ASSIST_WORKOUTS_CAP = 30;

export type CoachAssistMode = 'reply' | 'plan_tweak';

export interface CoachAssistInput {
	coachId: string;
	athleteId: string;
	mode: CoachAssistMode;
	request: string | null;
	today: string;
	consentVersion: number;
	/// When the coaching link began: earlier messages are not sent.
	linkedSince: string | null;
}

/** Plan weeks the workout window can reach: week `i` runs from `start_date + 7i`
 *  for seven days, so a 14-day window spans at most three of them. */
export const COACH_ASSIST_WINDOW_WEEKS = Math.floor(COACH_ASSIST_WORKOUT_DAYS / 7) + 1;

/** The week indexes `[today, today + COACH_ASSIST_WORKOUT_DAYS]` falls in, or
 *  null when the window ends before the plan starts. */
export function coachAssistWeekWindow(startDate: string, today: string): { first: number; last: number } | null {
	const dayMs = 86_400_000;
	const fromDay = Math.round((Date.parse(`${today}T00:00:00Z`) - Date.parse(`${startDate}T00:00:00Z`)) / dayMs);
	if (!Number.isFinite(fromDay)) return null;
	const last = Math.floor((fromDay + COACH_ASSIST_WORKOUT_DAYS) / 7);
	if (last < 0) return null;
	return { first: Math.max(0, Math.floor(fromDay / 7)), last };
}

function addDays(iso: string, days: number): string {
	const d = new Date(`${iso}T00:00:00Z`);
	d.setUTCDate(d.getUTCDate() + days);
	return d.toISOString().slice(0, 10);
}

/**
 * The context block for one draft. A failed read throws: a draft written as
 * if the athlete had no plan or no messages would be confidently wrong.
 */
export async function buildCoachAssistContext(
	supabase: SupabaseClient,
	input: CoachAssistInput,
): Promise<Record<string, unknown>> {
	const { coachId, athleteId, today } = input;
	const pair = [coachId, athleteId];

	const threadLane = (async () => {
		let query = supabase
			.from(TABLES.direct_messages)
			.select('sender_id, body, created_at')
			.in('sender_id', pair)
			.in('recipient_id', pair)
			.is('unsent_at', null)
			.neq('kind', 'coach_share');
		if (input.linkedSince) query = query.gte('created_at', input.linkedSince);
		const { data, error } = await query
			.order('created_at', { ascending: false })
			.limit(COACH_ASSIST_THREAD_CAP);
		if (error) throw dbError(error);
		return (data ?? [])
			.filter((m) => typeof m.body === 'string' && m.body.length > 0)
			.reverse()
			.map((m) => ({
				from: m.sender_id === athleteId ? 'athlete' : 'coach',
				text: (m.body as string).slice(0, COACH_ASSIST_MESSAGE_CHARS),
				sent_at: m.created_at,
			}));
	})();

	const planLane = (async () => {
		const { data: plans, error } = await supabase
			.from('training_plans')
			.select('id, name, goal_event, goal_distance_m, goal_time_seconds, start_date, end_date')
			.eq('user_id', athleteId)
			.eq('status', 'active')
			.eq('is_template', false)
			.gte('end_date', today)
			.order('start_date', { ascending: true })
			.limit(1);
		if (error) throw dbError(error);
		const plan = plans?.[0];
		if (!plan) return { plan: null, upcoming: [] as Record<string, unknown>[] };
		const window = coachAssistWeekWindow(plan.start_date as string, today);
		let weekIds: string[] = [];
		if (window) {
			const { data: weeks, error: weekErr } = await supabase
				.from('plan_weeks')
				.select('id')
				.eq('plan_id', plan.id)
				.gte('week_index', window.first)
				.lte('week_index', window.last)
				.limit(COACH_ASSIST_WINDOW_WEEKS);
			if (weekErr) throw dbError(weekErr);
			weekIds = (weeks ?? []).map((w) => w.id);
		}
		let upcoming: Record<string, unknown>[] = [];
		if (weekIds.length > 0) {
			const { data: workouts, error: woErr } = await supabase
				.from('plan_workouts')
				.select(
					'scheduled_date, kind, target_distance_m, target_duration_seconds, target_pace_sec_per_km, completed_at, skipped_at',
				)
				.in('week_id', weekIds)
				.gte('scheduled_date', today)
				.lte('scheduled_date', addDays(today, COACH_ASSIST_WORKOUT_DAYS))
				.order('scheduled_date', { ascending: true })
				.limit(COACH_ASSIST_WORKOUTS_CAP);
			if (woErr) throw dbError(woErr);
			upcoming = (workouts ?? []) as Record<string, unknown>[];
		}
		return {
			plan: {
				name: plan.name,
				goal_event: plan.goal_event,
				goal_distance_m: plan.goal_distance_m,
				goal_time_seconds: plan.goal_time_seconds,
				start_date: plan.start_date,
				end_date: plan.end_date,
			} as Record<string, unknown>,
			upcoming,
		};
	})();

	const runsLane = (async () => {
		const { data, error } = await supabase
			.from(TABLES.runs)
			.select('started_at, distance_m, duration_s, activity_type')
			.eq('user_id', athleteId)
			.order('started_at', { ascending: false })
			.limit(COACH_ASSIST_RUNS_CAP);
		if (error) throw dbError(error);
		return (data ?? []) as Record<string, unknown>[];
	})();

	const [thread, planned, runs] = await Promise.all([threadLane, planLane, runsLane]);

	return withholdUnconsented(
		{
			mode: input.mode,
			today,
			coach_request: input.request,
			thread,
			plan: planned.plan,
			upcoming_workouts: planned.upcoming,
			recent_runs: runs,
		},
		input.consentVersion,
	);
}
