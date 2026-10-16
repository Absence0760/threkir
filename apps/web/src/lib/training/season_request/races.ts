// Pure validation + clamping for the AI season request (issue #1181).
//
// The AI is the interface, never the planner (decisions.md §12). The model
// only lists the races the runner's description names — each one's name,
// date, distance, priority and goal time. It never authors a workout, a
// volume or a plan: the runner confirms the list, and the deterministic
// season builder chains one generated plan per A race from it.
//
// Nothing the model emitted is trusted. Every race passes through
// `validateSeasonRaces`, server-side, before it reaches a client: a field
// outside its band drops the race (or the field) and names why in
// `assumptions`, one key per adjustment, each rendered as a localized line.
//
// The rules, in order:
//   1. An entry that is not an object, or has no usable name, is dropped
//      (`race_dropped_invalid`).
//   2. Date: a real `yyyy-mm-dd` strictly after today and at most two years
//      out. A date up to a year in the past is the model resolving a partial
//      date ("4 April") to this year when the runner meant the next one, so
//      it moves forward a year (`race_date_next_year`); anything else —
//      today included — is dropped (`race_dropped_date`).
//   3. Distance: 5 km to 400 km, inclusive. Outside it the race is dropped
//      (`race_dropped_distance`), never clamped — a clamped distance names a
//      race that does not exist. A distance within 0.5 % of a standard road
//      distance snaps to it exactly, so "42.2" plans as a marathon.
//   4. Goal time: kept only when its pace sits between 2:30 and 20:00 per km;
//      otherwise the race keeps no goal (`goal_time_dropped`). The slow end
//      is wider than the plan wizard's because a 100-mile goal is mostly
//      walking.
//   5. Duplicates — the same date with the same distance (within 1 %), or the
//      same name on the same date — collapse into the first, keeping the
//      stronger priority and any goal time (`race_duplicate_merged`).
//   6. Sorted by date (the longer race first on a shared day) and capped at
//      `MAX_SEASON_RACES`, keeping the earliest (`races_capped`).
//   7. Priority: a race with no readable A/B/C becomes B
//      (`priority_default`). When no race is A, the longest becomes A — the
//      later one on a tie, since a season builds toward its end
//      (`priority_a_assigned`).
//
// Kept free of the Anthropic SDK and the `$app/env` graph so the clamp logic
// is unit-testable in isolation (races.test.ts).

import { isoEpochDay, MAX_RACE_DATE_YEARS } from '../plan_request/inputs';
import { GOAL_DISTANCES_M } from '../training';
import type { SeasonRace, SeasonRacePriority, SeasonRequestResult } from '../season_types';

/// Why the race list holds what it holds when it is not simply what the
/// runner wrote. The clients render one localized line per key, so a key
/// added here needs a label on web (`seasonAssumptionMessageKey`) and mobile
/// (`seasonAssumptionLabel`).
export const SEASON_REQUEST_ASSUMPTIONS = [
	'race_dropped_invalid',
	'race_dropped_date',
	'race_dropped_distance',
	'race_date_next_year',
	'goal_time_dropped',
	'race_duplicate_merged',
	'races_capped',
	'priority_default',
	'priority_a_assigned',
] as const;
export type SeasonRequestAssumption = (typeof SEASON_REQUEST_ASSUMPTIONS)[number];

export const MIN_SEASON_RACE_DISTANCE_M = 5_000;
export const MAX_SEASON_RACE_DISTANCE_M = 400_000;
export const MAX_SEASON_RACES = 12;
/// `plan_workouts.race_name`'s CHECK (migration 20270830000002): 1..120
/// characters once trimmed. A race confirmed from this list is written there.
export const MAX_SEASON_RACE_NAME_CHARS = 120;
export const MIN_SEASON_GOAL_PACE_SEC_PER_KM = 150;
export const MAX_SEASON_GOAL_PACE_SEC_PER_KM = 1200;
export const DEFAULT_SEASON_PRIORITY: SeasonRacePriority = 'B';

const STANDARD_SNAP_FRACTION = 0.005;
const DUPLICATE_DISTANCE_FRACTION = 0.01;
const CONTROL_CHARS = /\p{Cc}/gu;
const PRIORITY_RANK: Record<SeasonRacePriority, number> = { A: 3, B: 2, C: 1 };

function asRecord(raw: unknown): Record<string, unknown> | null {
	return raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : null;
}

function finiteNumber(raw: unknown): number | null {
	return typeof raw === 'number' && Number.isFinite(raw) ? raw : null;
}

function cleanName(raw: unknown): string | null {
	if (typeof raw !== 'string') return null;
	const cleaned = raw.replace(CONTROL_CHARS, ' ').replace(/\s+/g, ' ').trim();
	if (cleaned.length === 0) return null;
	return Array.from(cleaned).slice(0, MAX_SEASON_RACE_NAME_CHARS).join('').trim();
}

function isoFromEpochDay(day: number): string {
	return new Date(day * 86_400_000).toISOString().slice(0, 10);
}

function addYears(iso: string, years: number): number | null {
	const [y, m, d] = iso.split('-').map(Number);
	return isoEpochDay(`${String(y + years).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`);
}

type DateOutcome = { date: string; rolled: boolean } | null;

function resolveDate(raw: unknown, todayIso: string): DateOutcome {
	const today = isoEpochDay(todayIso);
	const race = isoEpochDay(raw);
	if (today === null || race === null) return null;
	const limit = addYears(todayIso, MAX_RACE_DATE_YEARS);
	if (limit === null) return null;
	if (race > today) return race <= limit ? { date: raw as string, rolled: false } : null;
	// Race day is today: too late to plan for, and not a misread year.
	if (race === today) return null;
	// Up to a year back: a partial date resolved to the wrong year.
	const yearAgo = addYears(todayIso, -1);
	if (yearAgo === null || race <= yearAgo) return null;
	const next = addYears(raw as string, 1);
	if (next === null || next <= today || next > limit) return null;
	return { date: isoFromEpochDay(next), rolled: true };
}

function resolveDistanceM(raw: unknown): number | null {
	const km = finiteNumber(raw);
	if (km === null) return null;
	const m = km * 1000;
	if (m < MIN_SEASON_RACE_DISTANCE_M || m > MAX_SEASON_RACE_DISTANCE_M) return null;
	for (const standard of Object.values(GOAL_DISTANCES_M)) {
		if (Math.abs(m - standard) <= standard * STANDARD_SNAP_FRACTION) return standard;
	}
	return Math.round(m);
}

function resolvePriority(raw: unknown): SeasonRacePriority | null {
	if (typeof raw !== 'string') return null;
	const p = raw.trim().toUpperCase();
	return p === 'A' || p === 'B' || p === 'C' ? p : null;
}

function goalTimeFits(goalTimeSec: number, distanceM: number): boolean {
	const pace = goalTimeSec / (distanceM / 1000);
	return pace >= MIN_SEASON_GOAL_PACE_SEC_PER_KM && pace <= MAX_SEASON_GOAL_PACE_SEC_PER_KM;
}

function sameRace(a: SeasonRace, b: SeasonRace): boolean {
	if (a.date !== b.date) return false;
	if (a.name.toLowerCase() === b.name.toLowerCase()) return true;
	const longer = Math.max(a.distanceM, b.distanceM);
	return Math.abs(a.distanceM - b.distanceM) <= longer * DUPLICATE_DISTANCE_FRACTION;
}

interface Candidate {
	race: SeasonRace;
	priorityGiven: boolean;
}

/// Validate + clamp the model's raw tool-call output into a confirmed-ready
/// race list. Never throws. Accepts either the tool input object (`{races}`)
/// or the bare array. This is the single trust boundary between the LLM and
/// the season planner.
export function validateSeasonRaces(raw: unknown, todayIso: string): SeasonRequestResult {
	const list = Array.isArray(raw) ? raw : asRecord(raw)?.races;
	const entries = Array.isArray(list) ? list : [];
	const seen = new Set<SeasonRequestAssumption>();
	const note = (a: SeasonRequestAssumption) => seen.add(a);

	const candidates: Candidate[] = [];
	for (const entry of entries) {
		const o = asRecord(entry);
		const name = o ? cleanName(o.name) : null;
		if (!o || name === null) {
			note('race_dropped_invalid');
			continue;
		}
		const date = resolveDate(o.date, todayIso);
		if (date === null) {
			note('race_dropped_date');
			continue;
		}
		const distanceM = resolveDistanceM(o.distance_km);
		if (distanceM === null) {
			note('race_dropped_distance');
			continue;
		}
		if (date.rolled) note('race_date_next_year');

		let goalTimeSec: number | null = null;
		const rawGoal = finiteNumber(o.goal_time_sec);
		if (rawGoal !== null) {
			const rounded = Math.round(rawGoal);
			if (rounded > 0 && goalTimeFits(rounded, distanceM)) goalTimeSec = rounded;
			else note('goal_time_dropped');
		}

		const priority = resolvePriority(o.priority);
		candidates.push({
			race: { name, date: date.date, distanceM, priority: priority ?? DEFAULT_SEASON_PRIORITY, goalTimeSec },
			priorityGiven: priority !== null,
		});
	}

	const unique: Candidate[] = [];
	for (const c of candidates) {
		const kept = unique.find((u) => sameRace(u.race, c.race));
		if (!kept) {
			unique.push(c);
			continue;
		}
		note('race_duplicate_merged');
		if (c.priorityGiven && (!kept.priorityGiven || PRIORITY_RANK[c.race.priority] > PRIORITY_RANK[kept.race.priority])) {
			kept.race.priority = c.race.priority;
			kept.priorityGiven = true;
		}
		if (kept.race.goalTimeSec === null && c.race.goalTimeSec !== null) {
			kept.race.goalTimeSec = c.race.goalTimeSec;
		}
	}

	unique.sort((a, b) =>
		a.race.date < b.race.date ? -1 : a.race.date > b.race.date ? 1 : b.race.distanceM - a.race.distanceM,
	);
	if (unique.length > MAX_SEASON_RACES) {
		unique.length = MAX_SEASON_RACES;
		note('races_capped');
	}

	if (unique.some((c) => !c.priorityGiven)) note('priority_default');
	if (unique.length > 0 && !unique.some((c) => c.race.priority === 'A')) {
		let pick = unique[0];
		for (const c of unique) {
			if (c.race.distanceM >= pick.race.distanceM) pick = c;
		}
		pick.race.priority = 'A';
		note('priority_a_assigned');
	}

	return {
		races: unique.map((c) => c.race),
		assumptions: SEASON_REQUEST_ASSUMPTIONS.filter((a) => seen.has(a)),
	};
}
