/**
 * What a race on the calendar hands the plan builder: the chained start floor
 * when the runner already has a plan ending before this race, the goal time
 * they set for it, and the description the AI plan box is prefilled with.
 *
 * Pure logic, no Supabase / auth.
 *
 * Dart twin: apps/mobile_android/lib/race_plan_prefill.dart (parity pair —
 * keep the selection rules, text, cap and test counts in lockstep).
 * `racePlanHref` is web-only: the phone opens `PlanNewScreen` with the same
 * fields as constructor arguments.
 *
 * The description is English and metric on purpose: it is a machine-read
 * request to the plan extractor (`/api/coach/plan-request`), like the Coach's
 * own `?describe=` handoff, not UI copy. It carries only what the AI plan
 * consent bullet names — the goal race, a target time and a recent time.
 * Weekly volume and the longest recent run are deliberately left out: the
 * bullet does not cover them (decisions § 2154).
 */

import { racePlanPreset } from './race_plan_preset';
import { seasonRecoveryDays } from './season_plan';

/// The AI plan box's own maxlength, which `/plans/new` also clamps `describe` to.
export const RACE_PLAN_DESCRIBE_MAX = 600;
/// A listing name longer than this is cut, so the race always fits the cap.
export const RACE_PLAN_DESCRIBE_NAME_MAX = 120;
export const RACE_PLAN_SURFACE_MAX = 40;

export interface RacePlanRace {
	name: string;
	raceDateIso: string;
	distanceM: number | null;
}

export interface RacePlanCourse {
	ascentM?: number | null;
	descentM?: number | null;
	surface?: string | null;
}

export interface RacePlanEffort {
	distanceM: number;
	durationS: number;
	ageDays: number;
}

export interface RacePlanOwnPlan {
	id: string;
	name: string;
	status: string;
	endDateIso: string;
	goalDistanceM: number | null;
	goalTimeSeconds: number | null;
}

export interface RacePlanChain {
	planId: string;
	planName: string;
	planEndIso: string;
	recoveryDays: number;
	/// The first day the new plan may start: the day after the earlier plan
	/// ends plus its race's recovery days.
	notBeforeIso: string;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function epochDay(iso: string): number | null {
	if (!ISO_DATE.test(iso)) return null;
	const [y, m, d] = iso.split('-').map(Number);
	const ms = Date.UTC(y, m - 1, d);
	const back = new Date(ms);
	if (back.getUTCFullYear() !== y || back.getUTCMonth() !== m - 1 || back.getUTCDate() !== d) {
		return null;
	}
	return Math.floor(ms / 86_400_000);
}

function isoFromEpochDay(day: number): string {
	const d = new Date(day * 86_400_000);
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/**
 * The plan this race should be chained after, or null when none applies.
 *
 * Candidates are the runner's active plans ending before race day; the latest
 * ending one is the block this race follows. Null when the recovery floor is
 * already behind today (nothing to avoid) or when a plan cannot be built for
 * the race from that floor, so "Add to my season" is only ever offered when
 * it can succeed.
 */
export function racePlanChain(
	plans: readonly RacePlanOwnPlan[],
	race: RacePlanRace,
	todayIso: string,
): RacePlanChain | null {
	const raceDay = epochDay(race.raceDateIso);
	const today = epochDay(todayIso);
	if (raceDay === null || today === null) return null;
	let best: { plan: RacePlanOwnPlan; end: number } | null = null;
	for (const p of plans) {
		if (p.status !== 'active') continue;
		const end = epochDay(p.endDateIso);
		if (end === null || end >= raceDay) continue;
		if (best === null || end > best.end) best = { plan: p, end };
	}
	if (best === null) return null;
	const recoveryDays = seasonRecoveryDays(best.plan.goalDistanceM ?? 0);
	const floor = best.end + 1 + recoveryDays;
	if (floor <= today) return null;
	const notBeforeIso = isoFromEpochDay(floor);
	const preset = racePlanPreset({
		raceDateIso: race.raceDateIso,
		distanceM: race.distanceM,
		todayIso,
		notBeforeIso,
	});
	if (!preset.ok) return null;
	return {
		planId: best.plan.id,
		planName: best.plan.name,
		planEndIso: best.plan.endDateIso,
		recoveryDays,
		notBeforeIso,
	};
}

/// The goal time the runner set for this race: an active plan of theirs that
/// ends on race day and carries one. The first such plan wins.
export function racePlanGoalTimeS(
	plans: readonly RacePlanOwnPlan[],
	raceDateIso: string,
): number | null {
	for (const p of plans) {
		if (p.status !== 'active' || p.endDateIso !== raceDateIso) continue;
		const t = p.goalTimeSeconds;
		if (t != null && Number.isFinite(t) && t > 0) return Math.round(t);
	}
	return null;
}

function kmText(metres: number): string {
	const tenths = Math.round(metres / 100);
	const whole = Math.trunc(tenths / 10);
	const frac = tenths % 10;
	return frac === 0 ? `${whole}` : `${whole}.${frac}`;
}

function clockText(totalS: number): string {
	const s = Math.round(totalS);
	const h = Math.trunc(s / 3600);
	const m = Math.trunc((s % 3600) / 60);
	const sec = s % 60;
	const pad = (n: number) => String(n).padStart(2, '0');
	return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

function positive(n: number | null | undefined): n is number {
	return n != null && Number.isFinite(n) && n > 0;
}

function collapse(text: string): string {
	return text.replace(/\s+/g, ' ').trim();
}

/**
 * The AI plan box's description for a race, at most `maxChars` long.
 *
 * Built from sentences in priority order — race and date, distance, goal,
 * recent fitness, course — and a sentence that would overflow the cap is
 * dropped whole, along with everything after it, so the text is deterministic
 * and never ends mid-word. The race sentence always fits because the name is
 * cut to RACE_PLAN_DESCRIBE_NAME_MAX first.
 */
export function racePlanDescribe(
	input: {
		race: RacePlanRace;
		goalTimeS?: number | null;
		recentEffort?: RacePlanEffort | null;
		course?: RacePlanCourse | null;
	},
	maxChars: number = RACE_PLAN_DESCRIBE_MAX,
): string {
	const name = collapse(input.race.name).slice(0, RACE_PLAN_DESCRIBE_NAME_MAX).trim();
	const sentences: string[] = [`Race: ${name} on ${input.race.raceDateIso}.`];
	if (positive(input.race.distanceM)) sentences.push(`Distance: ${kmText(input.race.distanceM)} km.`);
	if (positive(input.goalTimeS)) sentences.push(`Goal time: ${clockText(input.goalTimeS)}.`);
	const e = input.recentEffort;
	if (e && positive(e.distanceM) && positive(e.durationS) && Number.isFinite(e.ageDays)) {
		const days = Math.max(0, Math.round(e.ageDays));
		const when = days === 0 ? 'today' : days === 1 ? '1 day ago' : `${days} days ago`;
		sentences.push(`Recent effort: ${kmText(e.distanceM)} km in ${clockText(e.durationS)}, ${when}.`);
	}
	const c = input.course;
	if (c) {
		const parts: string[] = [];
		if (positive(c.ascentM)) parts.push(`${Math.round(c.ascentM)} m ascent`);
		if (positive(c.descentM)) parts.push(`${Math.round(c.descentM)} m descent`);
		const surface = c.surface ? collapse(c.surface).slice(0, RACE_PLAN_SURFACE_MAX).trim() : '';
		if (surface) parts.push(`${surface} surface`);
		if (parts.length > 0) sentences.push(`Course: ${parts.join(', ')}.`);
	}
	let out = sentences[0].slice(0, maxChars);
	for (const s of sentences.slice(1)) {
		if (out.length + 1 + s.length > maxChars) break;
		out = `${out} ${s}`;
	}
	return out;
}

/// The `/plans/new` link a race opens. Web-only (see the file header).
export function racePlanHref(input: {
	race: RacePlanRace;
	/// The calendar listing, so the created plan links back to it.
	listingId?: string | null;
	notBeforeIso?: string | null;
	describe?: string | null;
}): string {
	const q = new URLSearchParams({
		type: 'training',
		raceDate: input.race.raceDateIso,
		raceName: input.race.name,
	});
	if (input.race.distanceM != null) q.set('raceDistance', String(input.race.distanceM));
	if (input.listingId) q.set('raceListing', input.listingId);
	if (input.notBeforeIso) q.set('notBefore', input.notBeforeIso);
	if (input.describe) q.set('describe', input.describe);
	return `/plans/new?${q}`;
}
