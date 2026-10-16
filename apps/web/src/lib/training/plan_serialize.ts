/**
 * Plan import / export — a Markdown (and JSON) round-trip for training
 * plans. Two use cases:
 *
 *  1. Export your plan to share / archive / hand to a coach.
 *  2. Paste a plan (from a coach, a book, or a previous export) and have
 *     it parsed into weeks + workouts ready to persist.
 *
 * The Markdown shape is a small header block + one table row per
 * workout, keyed by week number + date. It's deliberately
 * human-editable: a coach can paste a hand-built table and it parses,
 * and an exported plan re-imports to the same workouts (the round-trip
 * the tests pin). Pure — no Supabase / DOM.
 *
 * Lossy by design on import: pace tolerance, structured-interval JSON,
 * and duration-based steps aren't represented in the table, so a parsed
 * plan carries distance + pace + notes per workout and nulls the rest.
 * Phase + weekly volume are *recomputed* on import (phase from week
 * position, volume from the summed distances) rather than trusted from
 * the text.
 */

import { GOAL_DISTANCES_M, phaseFor } from './training';
import type { GeneratedPlan, GoalEvent, PlanPhase, WorkoutKind } from './training';
import { RACE_PRIORITIES, type RacePriority } from './plan_races';

const METRES_PER_MILE = 1609.344;

export const WORKOUT_KINDS: readonly WorkoutKind[] = [
	'easy',
	'long',
	'recovery',
	'tempo',
	'interval',
	'marathon_pace',
	'walk_run',
	'race',
	'rest',
];

const GOAL_EVENTS: readonly GoalEvent[] = [
	'distance_5k',
	'distance_10k',
	'distance_half',
	'distance_full',
	'custom',
];

/// Minimal per-workout shape the exporter needs. Callers flatten their
/// weeks + workouts (DB rows or a GeneratedPlan) into this.
export interface ExportWorkout {
	week_index: number; // 0-based
	scheduled_date: string; // ISO YYYY-MM-DD
	kind: string;
	target_distance_m: number | null;
	target_pace_sec_per_km: number | null;
	notes: string | null;
	target_duration_seconds?: number | null;
	race_name?: string | null;
	race_priority?: string | null;
}

export interface ExportPlan {
	name: string;
	goalEvent: string;
	goalDistanceM: number;
	goalTimeSec: number | null;
	startDate: string;
	workouts: ExportWorkout[];
}

/// A parsed plan, ready to hand to `createTrainingPlan`.
export interface ParsedPlan {
	name: string;
	goalEvent: GoalEvent;
	goalDistanceM: number;
	goalTimeSec: number | null;
	startDate: string;
	generated: GeneratedPlan;
}

function fmtKmCell(metres: number | null): string {
	if (metres == null || metres <= 0) return '';
	return `${(metres / 1000).toFixed(2)} km`;
}

function fmtPaceCell(secPerKm: number | null): string {
	if (secPerKm == null || secPerKm <= 0) return '';
	// Round to whole seconds first — rounding the seconds field in isolation
	// (Math.round(x % 60)) can produce a malformed ":60" for a fractional
	// input (e.g. 359.6 → "5:60" instead of "6:00") that then re-parses to
	// the wrong minute.
	const total = Math.round(secPerKm);
	const m = Math.floor(total / 60);
	const s = total % 60;
	return `${m}:${String(s).padStart(2, '0')}`;
}

function fmtHmsCell(sec: number | null): string {
	if (sec == null || sec <= 0) return '';
	const total = Math.round(sec);
	const h = Math.floor(total / 3600);
	const m = Math.floor((total % 3600) / 60);
	const s = total % 60;
	return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

/// Notes can't contain a raw pipe (it would break the table) or a
/// newline; collapse both so a round-trip stays on one row.
function sanitizeCell(s: string | null): string {
	if (!s) return '';
	return s.replace(/\|/g, '/').replace(/\s*\n\s*/g, ' ').trim();
}

export function planToMarkdown(plan: ExportPlan): string {
	const lines: string[] = [];
	lines.push(`# ${sanitizeCell(plan.name) || 'Training plan'}`);
	lines.push('');
	lines.push(`- Goal event: ${plan.goalEvent}`);
	lines.push(`- Goal distance: ${(plan.goalDistanceM / 1000).toFixed(2)} km`);
	if (plan.goalTimeSec != null && plan.goalTimeSec > 0) {
		lines.push(`- Goal time: ${fmtHmsCell(plan.goalTimeSec)}`);
	}
	lines.push(`- Start date: ${plan.startDate}`);
	lines.push('');
	// The race columns appear only when a race carries one of them, so a plan
	// without named races exports the six-column table older importers read.
	const raceCols = plan.workouts.some(
		(w) =>
			w.kind === 'race' &&
			(!!w.race_name || !!w.race_priority || (w.target_duration_seconds ?? 0) > 0),
	);
	if (raceCols) {
		lines.push('| Week | Date | Type | Distance | Pace | Notes | Race | Priority | Goal |');
		lines.push('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
	} else {
		lines.push('| Week | Date | Type | Distance | Pace | Notes |');
		lines.push('| --- | --- | --- | --- | --- | --- |');
	}
	const sorted = [...plan.workouts].sort((a, b) =>
		a.scheduled_date < b.scheduled_date ? -1 : a.scheduled_date > b.scheduled_date ? 1 : 0,
	);
	for (const w of sorted) {
		const base = `| ${w.week_index + 1} | ${w.scheduled_date} | ${w.kind} | ${fmtKmCell(
			w.target_distance_m,
		)} | ${fmtPaceCell(w.target_pace_sec_per_km)} | ${sanitizeCell(w.notes)} |`;
		if (!raceCols) {
			lines.push(base);
		} else if (w.kind === 'race') {
			lines.push(
				`${base} ${sanitizeCell(w.race_name ?? null)} | ${w.race_priority ?? ''} | ${fmtHmsCell(
					w.target_duration_seconds ?? null,
				)} |`,
			);
		} else {
			lines.push(`${base}  |  |  |`);
		}
	}
	return lines.join('\n') + '\n';
}

export function planToJson(plan: ExportPlan): string {
	return JSON.stringify(plan, null, 2);
}

class PlanParseError extends Error {}

function parseDistanceCell(cell: string): number | null {
	const t = cell.trim();
	if (!t) return null;
	const m = t.match(/^([\d.]+)\s*(km|mi|m)?$/i);
	if (!m) throw new PlanParseError(`Couldn't read distance "${cell}".`);
	const num = parseFloat(m[1]);
	if (Number.isNaN(num)) throw new PlanParseError(`Couldn't read distance "${cell}".`);
	const unit = (m[2] ?? 'km').toLowerCase();
	if (unit === 'mi') return num * METRES_PER_MILE;
	if (unit === 'm') return num;
	return num * 1000;
}

function parsePaceCell(cell: string): number | null {
	const t = cell.trim();
	if (!t) return null;
	const m = t.match(/^(\d{1,2}):(\d{2})$/);
	if (!m) throw new PlanParseError(`Couldn't read pace "${cell}" — use m:ss.`);
	return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
}

function parseHms(t: string): number | null {
	const trimmed = t.trim();
	if (!trimmed) return null;
	const parts = trimmed.split(':').map((p) => parseInt(p, 10));
	if (parts.some((p) => Number.isNaN(p))) return null;
	if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
	if (parts.length === 2) return parts[0] * 60 + parts[1];
	return null;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const RACE_NAME_MAX = 120;

interface ParsedRow {
	weekIndex: number;
	scheduled_date: string;
	kind: WorkoutKind;
	target_distance_m: number | null;
	target_pace_sec_per_km: number | null;
	notes: string | null;
	race_name: string | null;
	race_priority: RacePriority | null;
	target_duration_seconds: number | null;
}

type Column =
	| 'week'
	| 'date'
	| 'type'
	| 'distance'
	| 'pace'
	| 'notes'
	| 'race'
	| 'priority'
	| 'goal';

const COLUMN_ALIASES: Record<string, Column> = {
	week: 'week',
	date: 'date',
	type: 'type',
	kind: 'type',
	distance: 'distance',
	pace: 'pace',
	notes: 'notes',
	note: 'notes',
	race: 'race',
	priority: 'priority',
	goal: 'goal',
};

const LEGACY_COLUMNS: readonly Column[] = ['week', 'date', 'type', 'distance', 'pace', 'notes'];

/// Maps a header row to column positions, or null when the header is the
/// legacy six-column one (or a prefix of it) or names a column this parser
/// does not know — both of which keep the positional reading.
function headerColumns(cells: string[]): Map<Column, number> | null {
	const names = cells.map((c) => COLUMN_ALIASES[c.trim().toLowerCase()]);
	if (names.some((n) => !n)) return null;
	if (names.every((n, i) => n === LEGACY_COLUMNS[i])) return null;
	const map = new Map<Column, number>();
	names.forEach((n, i) => {
		if (map.has(n)) throw new PlanParseError(`Column "${cells[i]}" appears twice.`);
		map.set(n, i);
	});
	for (const required of ['week', 'date', 'type'] as const) {
		if (!map.has(required)) throw new PlanParseError(`The table has no ${required} column.`);
	}
	return map;
}

function parseRaceName(cell: string): string | null {
	const t = cell.trim();
	if (!t) return null;
	if (t.length > RACE_NAME_MAX) {
		throw new PlanParseError(`Race name "${t.slice(0, 40)}…" is longer than ${RACE_NAME_MAX} characters.`);
	}
	return t;
}

function parsePriorityCell(cell: string): RacePriority | null {
	const t = cell.trim().toUpperCase();
	if (!t) return null;
	if (!(RACE_PRIORITIES as readonly string[]).includes(t)) {
		throw new PlanParseError(`Bad race priority "${cell}" — use A, B or C.`);
	}
	return t as RacePriority;
}

function parseGoalCell(cell: string): number | null {
	const t = cell.trim();
	if (!t) return null;
	const sec = /^\d+(:\d{2}){1,2}$/.test(t) ? parseHms(t) : null;
	if (sec == null || sec <= 0) throw new PlanParseError(`Couldn't read goal time "${cell}" — use h:mm:ss.`);
	return sec;
}

function isSeparatorRow(cells: string[]): boolean {
	return cells.every((c) => /^:?-{2,}:?$/.test(c.trim()) || c.trim() === '');
}

/// Parse a Markdown export (or a hand-written table in the same shape)
/// into a plan ready for `createTrainingPlan`. Throws a readable
/// Error on malformed input so the UI can surface it.
export function parsePlanMarkdown(text: string): ParsedPlan {
	const rawLines = text.split('\n');
	let name = '';
	let goalEventToken: string | null = null;
	let goalDistanceM: number | null = null;
	let goalTimeSec: number | null = null;
	let startDate: string | null = null;
	const rows: ParsedRow[] = [];
	let sawHeaderRow = false;
	let columns: Map<Column, number> | null = null;

	for (const raw of rawLines) {
		const line = raw.trim();
		if (!line) continue;
		if (line.startsWith('# ')) {
			if (!name) name = line.slice(2).trim();
			continue;
		}
		if (line.startsWith('- ')) {
			const body = line.slice(2);
			const colon = body.indexOf(':');
			if (colon === -1) continue;
			const key = body.slice(0, colon).trim().toLowerCase();
			const val = body.slice(colon + 1).trim();
			if (key === 'goal event') goalEventToken = val;
			else if (key === 'goal distance') goalDistanceM = parseDistanceCell(val);
			else if (key === 'goal time') goalTimeSec = parseHms(val);
			else if (key === 'start date') startDate = val;
			continue;
		}
		if (line.startsWith('|')) {
			const cells = line
				.split('|')
				.slice(1, -1)
				.map((c) => c.trim());
			// Notes is the only optional column; a hand-written table may omit
			// its trailing cell, leaving the five required columns (Week, Date,
			// Kind, Distance, Pace). Require those five — fewer is a non-table
			// line to skip; a short-but-present row then surfaces a readable
			// validation error below instead of being silently dropped.
			if (isSeparatorRow(cells)) continue;
			// Header row (the `Week | Date | …` titles) — read once. A header
			// naming the race columns, or ordering columns differently, maps
			// cells by name; the legacy one keeps the positional reading.
			if (!sawHeaderRow) {
				const legacyHeader = cells.length >= 2 && /week/i.test(cells[0]) && /date/i.test(cells[1]);
				const named = rows.length === 0 && cells.some((c) => c.trim().toLowerCase() === 'week');
				if (legacyHeader || named) {
					sawHeaderRow = true;
					columns = rows.length === 0 ? headerColumns(cells) : null;
					continue;
				}
			}
			if (!columns && cells.length < 5) continue;
			const cell = (col: Column): string => {
				const i = columns?.get(col);
				return i == null ? '' : (cells[i] ?? '');
			};
			const [weekCell, dateCell, kindCell, distCell, paceCell, ...noteCells] = columns
				? [cell('week'), cell('date'), cell('type'), cell('distance'), cell('pace'), cell('notes')]
				: cells;
			const weekNum = parseInt(weekCell, 10);
			if (Number.isNaN(weekNum) || weekNum < 1) {
				throw new PlanParseError(`Bad week number "${weekCell}".`);
			}
			if (!ISO_DATE.test(dateCell)) {
				throw new PlanParseError(`Bad date "${dateCell}" — use YYYY-MM-DD.`);
			}
			const kind = kindCell.trim().toLowerCase() as WorkoutKind;
			if (!WORKOUT_KINDS.includes(kind)) {
				throw new PlanParseError(`Unknown workout type "${kindCell}".`);
			}
			const race_name = parseRaceName(cell('race'));
			const race_priority = parsePriorityCell(cell('priority'));
			const target_duration_seconds = parseGoalCell(cell('goal'));
			if (
				kind !== 'race' &&
				(race_name != null || race_priority != null || target_duration_seconds != null)
			) {
				throw new PlanParseError(
					`Race, Priority and Goal only apply to race rows — ${dateCell} is a ${kind} workout.`,
				);
			}
			rows.push({
				weekIndex: weekNum - 1,
				scheduled_date: dateCell,
				kind,
				target_distance_m: parseDistanceCell(distCell),
				target_pace_sec_per_km: parsePaceCell(paceCell),
				notes: noteCells.join('|').trim() || null,
				race_name,
				race_priority,
				target_duration_seconds,
			});
		}
	}

	if (rows.length === 0) {
		throw new PlanParseError('No workout rows found. Expected a | Week | Date | … | table.');
	}

	rows.sort((a, b) => (a.scheduled_date < b.scheduled_date ? -1 : a.scheduled_date > b.scheduled_date ? 1 : 0));

	const totalWeeks = Math.max(...rows.map((r) => r.weekIndex)) + 1;
	const byWeek = new Map<number, ParsedRow[]>();
	for (const r of rows) {
		const list = byWeek.get(r.weekIndex) ?? [];
		list.push(r);
		byWeek.set(r.weekIndex, list);
	}

	const weeks = [...byWeek.keys()]
		.sort((a, b) => a - b)
		.map((weekIndex) => {
			const wos = byWeek.get(weekIndex)!;
			const target_volume_m = wos.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
			return {
				week_index: weekIndex,
				phase: phaseFor(weekIndex, totalWeeks) as PlanPhase,
				target_volume_m,
				notes: null,
				workouts: wos.map((w) => ({
					scheduled_date: w.scheduled_date,
					kind: w.kind,
					target_distance_m: w.target_distance_m,
					target_duration_seconds: w.target_duration_seconds,
					target_pace_sec_per_km: w.target_pace_sec_per_km,
					target_pace_tolerance_sec: null,
					structure: null,
					notes: w.notes,
					race_name: w.race_name,
					race_priority: w.race_priority,
				})),
			};
		});

	const goalEvent: GoalEvent =
		goalEventToken && GOAL_EVENTS.includes(goalEventToken as GoalEvent)
			? (goalEventToken as GoalEvent)
			: 'custom';
	// For a known event use the canonical distance — the table's "Goal
	// distance" line is rounded to 2 dp of km (42.20 km), so trusting it
	// would round a marathon's 42195 m to 42200. For a custom event keep
	// the parsed distance, falling back to the longest workout.
	let resolvedDistance: number;
	if (goalEvent !== 'custom') {
		resolvedDistance = GOAL_DISTANCES_M[goalEvent];
	} else if (goalDistanceM != null && goalDistanceM > 0) {
		resolvedDistance = goalDistanceM;
	} else {
		resolvedDistance = Math.max(0, ...rows.map((r) => r.target_distance_m ?? 0));
	}
	if (!(resolvedDistance > 0)) {
		throw new PlanParseError('Could not determine a goal distance.');
	}

	const start = startDate && ISO_DATE.test(startDate) ? startDate : rows[0].scheduled_date;
	const endDate = rows[rows.length - 1].scheduled_date;

	return {
		name: name || 'Imported plan',
		goalEvent,
		goalDistanceM: resolvedDistance,
		goalTimeSec,
		startDate: start,
		generated: {
			weeks,
			paces: { easy: 0, marathon: 0, tempo: 0, interval: 0, repetition: 0 },
			vdot: null,
			endDate,
			goalDistanceM: resolvedDistance,
			pacesAreFallback: true,
		},
	};
}

/// Parse a JSON export (the `ExportPlan` shape) back into a plan ready
/// for `createTrainingPlan`. Round-trips with `planToJson`.
export function parsePlanJson(text: string): ParsedPlan {
	let obj: unknown;
	try {
		obj = JSON.parse(text);
	} catch {
		throw new PlanParseError('Not valid JSON.');
	}
	const p = obj as Partial<ExportPlan>;
	if (!p || !Array.isArray(p.workouts)) {
		throw new PlanParseError('JSON is missing a workouts array.');
	}
	// Re-route through the Markdown builder so JSON + Markdown share one
	// reconstruction path (phase recompute, volume summing, validation).
	return parsePlanMarkdown(
		planToMarkdown({
			name: p.name ?? 'Imported plan',
			goalEvent: p.goalEvent ?? 'custom',
			goalDistanceM: p.goalDistanceM ?? 0,
			goalTimeSec: p.goalTimeSec ?? null,
			startDate: p.startDate ?? '',
			workouts: p.workouts as ExportWorkout[],
		}),
	);
}
