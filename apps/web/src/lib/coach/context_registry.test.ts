// Issue #1217: every field the Coach sends Anthropic must be named by a
// consent bullet, and gated on the disclosure version whose copy names it.
// Run with `npx tsx --test src/lib/coach/context_registry.test.ts` from apps/web.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	AI_DISCLOSURE_CURRENT_VERSION,
	AI_DISCLOSURE_VERSION_COACH,
	AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING,
	AI_DISCLOSURE_VERSION_FOOD_PHOTO_AI,
} from '../core/ai_disclosure';
import { en } from '../i18n/locales/en';
import {
	buildContext,
	COACH_CONTEXT_COLUMNS,
	COACH_CONTEXT_CONTAINERS,
	COACH_CONTEXT_REGISTRY,
	COACH_PLAN_COLUMNS,
	COACH_PLAN_WEEK_COLUMNS,
	COACH_PLAN_WORKOUT_COLUMNS,
	COACH_RUN_COLUMNS,
	COACH_SEASON_BLOCK_KEYS,
	withholdUndisclosed,
	type CoachPlanScope,
	type CoachProfileRow,
} from './context';

const HERE = import.meta.dirname ?? '.';
const NOTICE_SVELTE = readFileSync(
	resolve(HERE, '../components/AiDisclosureNotice.svelte'),
	'utf8',
);
const MOBILE = resolve(HERE, '../../../../mobile_android/lib');
const NOTICE_DART = readFileSync(resolve(MOBILE, 'widgets/ai_disclosure_notice.dart'), 'utf8');
const ARB_EN = JSON.parse(readFileSync(resolve(MOBILE, 'l10n/app_en.arb'), 'utf8')) as Record<
	string,
	unknown
>;

const USER = 'user-1';
const RECENT = new Date(Date.now() - 86_400_000).toISOString();

/// A row carrying every listed column, with `fixed` values where a lane's
/// filters or joins need them, so every selected field has something to emit.
function rowOf(columns: readonly string[], fixed: Record<string, unknown>): Record<string, unknown> {
	return {
		...Object.fromEntries(columns.map((c) => [c, `${c}-value`])),
		...fixed,
	};
}

/// One row in every table a lane reads, so every lane has something to emit.
/// The table-backed rows also carry columns the Coach does not select
/// (`user_id`, `updated_by`, …), as the real rows do.
function fullFixture(): Record<string, Record<string, unknown>[]> {
	return {
		training_plans: [
			rowOf(COACH_PLAN_COLUMNS, {
				id: 'p1',
				status: 'active',
				start_date: '2026-06-01',
				end_date: '2099-12-31',
				user_id: USER,
				is_template: false,
				assigned_by_coach_id: 'coach-1',
			}),
		],
		plan_weeks: [rowOf(COACH_PLAN_WEEK_COLUMNS, { id: 'w1', plan_id: 'p1', week_index: 0 })],
		plan_workouts: [
			rowOf(COACH_PLAN_WORKOUT_COLUMNS, {
				id: 'k1',
				week_id: 'w1',
				scheduled_date: '2026-06-02',
				target_hr_min_bpm: 140,
				target_hr_max_bpm: 155,
				updated_by: 'coach-1',
			}),
		],
		runs: [
			rowOf(COACH_RUN_COLUMNS, {
				id: 'r1',
				user_id: USER,
				started_at: RECENT,
				distance_m: 10_000,
				duration_s: 3_000,
				activity_type: 'run',
				metadata: { is_indoor: false, avg_bpm: 150, notes: 'private' },
				route_id: 'route-1',
			}),
		],
		gym_workouts: [{ id: 'g1', user_id: USER, title: 'Pull', started_at: RECENT }],
		gym_sets: [{ workout_id: 'g1', exercise_name: 'Row', reps: 5, weight_kg: 60 }],
		food_log: [{ user_id: USER, started_at: RECENT, calories: 2_000, protein_g: 100, carbs_g: 250, fat_g: 70 }],
		user_settings: [
			{
				user_id: USER,
				prefs: {
					weekly_mileage_goal_m: 40_000,
					coach_personality: 'direct',
					date_of_birth: '1990-01-01',
					resting_hr_bpm: 50,
					max_hr_bpm: 190,
					hr_zones: [120, 140, 160, 175],
				},
			},
		],
	};
}

/// Filter-aware stub that records which tables were read.
function recordingSupabase(
	tables: Record<string, Record<string, unknown>[]>,
	read: Set<string>,
	selects: Map<string, Set<string>> = new Map(),
) {
	return {
		from(table: string) {
			read.add(table);
			const rows = tables[table] ?? [];
			const eqs: Array<[string, unknown]> = [];
			const ins: Array<[string, unknown[]]> = [];
			const matched = () =>
				rows.filter(
					(r) =>
						eqs.every(([c, v]) => r[c] === v) && ins.every(([c, vs]) => vs.includes(r[c])),
				);
			const q: Record<string, unknown> = {};
			for (const m of ['order', 'gte']) q[m] = () => q;
			q.select = (cols: string) => {
				if (!selects.has(table)) selects.set(table, new Set());
				selects.get(table)!.add(cols);
				return q;
			};
			q.eq = (c: string, v: unknown) => {
				eqs.push([c, v]);
				return q;
			};
			q.in = (c: string, vs: unknown[]) => {
				ins.push([c, vs]);
				return q;
			};
			q.limit = () => Promise.resolve({ data: matched(), error: null });
			q.maybeSingle = () => Promise.resolve({ data: matched()[0] ?? null, error: null });
			q.then = (onFulfilled: (v: unknown) => unknown, onRejected?: (e: unknown) => unknown) =>
				Promise.resolve({ data: matched(), error: null }).then(onFulfilled, onRejected);
			return q;
		},
	};
}

const PROFILE: CoachProfileRow = {
	preferred_unit: 'km',
	health_data_consent_at: '2026-06-01T00:00:00.000Z',
};

async function contextAt(
	version: number,
	profile: CoachProfileRow = PROFILE,
	scope: CoachPlanScope = 'plan',
	tables = fullFixture(),
) {
	const read = new Set<string>();
	const selects = new Map<string, Set<string>>();
	const ctx = await buildContext(
		recordingSupabase(tables, read, selects) as never,
		USER,
		null,
		10,
		profile,
		'2026-06-15',
		version,
		scope,
	);
	return { data: ctx.data as Record<string, unknown>, read, selects };
}

/// Every registry path the emitted context carries. A `season` block is read
/// under the same entries as the top-level keys it repeats.
function emittedPaths(data: Record<string, unknown>): string[] {
	const out: string[] = [];
	for (const [key, value] of Object.entries(data)) {
		const container = COACH_CONTEXT_CONTAINERS.get(key);
		if (container === 'blocks') {
			for (const block of value as Record<string, unknown>[]) out.push(...emittedPaths(block));
		} else if (container && value != null) {
			const rows = (container === 'list' ? value : [value]) as Record<string, unknown>[];
			const fields = new Set(rows.flatMap((r) => Object.keys(r)));
			for (const field of fields) out.push(`${key}.${field}`);
		} else if (!container) {
			out.push(key);
		}
	}
	return out;
}

test('at the current disclosure, every emitted key is registered and every registered key is emitted', async () => {
	const { data } = await contextAt(AI_DISCLOSURE_CURRENT_VERSION);
	const emitted = emittedPaths(data);
	for (const path of emitted) {
		assert.ok(path in COACH_CONTEXT_REGISTRY, `"${path}" reaches Anthropic with no registry entry`);
	}
	// The other direction keeps this test honest: if the fixture stopped
	// exercising a lane, its keys would silently drop out of the check above.
	assert.deepEqual(
		[...emitted].sort(),
		Object.keys(COACH_CONTEXT_REGISTRY).sort(),
		'the fixture must drive every registered lane',
	);
});

for (const version of [AI_DISCLOSURE_VERSION_COACH, AI_DISCLOSURE_VERSION_FOOD_PHOTO_AI]) {
	test(`a v${version} acceptance gets a working Coach without the gym and nutrition lanes`, async () => {
		const { data, read } = await contextAt(version);
		assert.equal('recent_lifts' in data, false, 'recent_lifts is not named before v6');
		assert.equal('nutrition_7d' in data, false, 'nutrition_7d is not named before v6');
		// Not read at all, not read and dropped.
		for (const table of ['gym_workouts', 'gym_sets', 'food_log']) {
			assert.equal(read.has(table), false, `${table} must not be queried at v${version}`);
		}
		assert.equal((data.recent_runs as unknown[]).length, 1);
		assert.equal((data.plan as { id: string }).id, 'p1');
		for (const path of emittedPaths(data)) {
			const entry = COACH_CONTEXT_REGISTRY[path];
			if ('sentFrom' in entry) assert.ok(entry.sentFrom <= version, `"${path}" sent below its gate`);
		}
	});
}

test('a v6 acceptance gets the gym and nutrition lanes', async () => {
	const { data } = await contextAt(AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING);
	assert.deepEqual(data.recent_lifts, [
		{ date: RECENT.slice(0, 10), title: 'Pull', exercises: 1, sets: 1, volume_kg: 300 },
	]);
	assert.equal((data.nutrition_7d as { avg_calories: number }).avg_calories, 2_000);
});

test('raw resting and max HR are sent only at v6, and only with health-data consent', async () => {
	const rc = (data: Record<string, unknown>) => data.runner_context as Record<string, unknown>;
	for (const version of [AI_DISCLOSURE_VERSION_COACH, AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING - 1]) {
		const { data } = await contextAt(version);
		assert.equal('resting_hr_bpm' in rc(data), false, `resting_hr_bpm sent at v${version}`);
		assert.equal('max_hr_bpm' in rc(data), false, `max_hr_bpm sent at v${version}`);
		// The zones derived from them are named since v1 and keep flowing.
		assert.deepEqual(rc(data).hr_zones, [120, 140, 160, 175]);
	}
	const consented = await contextAt(AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING);
	assert.equal(rc(consented.data).resting_hr_bpm, 50);
	assert.equal(rc(consented.data).max_hr_bpm, 190);
	const withheld = await contextAt(AI_DISCLOSURE_VERSION_COACH_CROSS_TRAINING, {
		...PROFILE,
		health_data_consent_at: null,
	});
	assert.equal(rc(withheld.data).resting_hr_bpm, null);
	assert.equal(rc(withheld.data).max_hr_bpm, null);
	assert.equal(rc(withheld.data).hr_zones, null);
});

test('the display name is never sent, even when the profile row carries it', async () => {
	const { data } = await contextAt(AI_DISCLOSURE_CURRENT_VERSION, {
		...PROFILE,
		display_name: 'Runner',
	} as CoachProfileRow);
	assert.deepEqual(data.profile, { preferred_unit: 'km' });
	assert.equal('profile.display_name' in COACH_CONTEXT_REGISTRY, false);
});

test('an unregistered key throws instead of being sent', () => {
	assert.throws(
		() => withholdUndisclosed({ recent_runs: [], gym_notes: 'x' }, AI_DISCLOSURE_CURRENT_VERSION),
		/"gym_notes" is not in COACH_CONTEXT_REGISTRY/,
	);
	assert.throws(
		() =>
			withholdUndisclosed(
				{ runner_context: { weight_kg: 70 } },
				AI_DISCLOSURE_CURRENT_VERSION,
			),
		/"runner_context.weight_kg" is not in COACH_CONTEXT_REGISTRY/,
	);
});

test('withholdUndisclosed drops a nested field below its gate and keeps a null container', () => {
	assert.deepEqual(withholdUndisclosed({ profile: null, now_iso: 't' }, 1), {
		profile: null,
		now_iso: 't',
	});
	assert.deepEqual(
		withholdUndisclosed({ recent_lifts: [], nutrition_7d: null, recent_runs: [] }, 5),
		{ recent_runs: [] },
	);
});

test('every registry entry is gated on a known version, at or above the copy that names it', () => {
	for (const [path, entry] of Object.entries(COACH_CONTEXT_REGISTRY)) {
		if ('notPersonalData' in entry) continue;
		assert.ok(entry.sentFrom >= 1 && entry.sentFrom <= AI_DISCLOSURE_CURRENT_VERSION, path);
		assert.ok(entry.namedFrom >= 1 && entry.namedFrom <= AI_DISCLOSURE_CURRENT_VERSION, path);
		assert.ok(
			entry.sentFrom >= entry.namedFrom || (entry.legacyReason ?? '').length > 0,
			`"${path}" is sent at v${entry.sentFrom} but first named at v${entry.namedFrom}, with no legacyReason`,
		);
	}
});

test('every covering bullet is real copy, shown on web and on mobile', () => {
	for (const [path, entry] of Object.entries(COACH_CONTEXT_REGISTRY)) {
		if ('notPersonalData' in entry) continue;
		const key = entry.bullet;
		assert.ok(key in en, `${path}: ${key} is not in en.ts`);
		assert.ok(
			NOTICE_SVELTE.includes(`m('${key}')`),
			`${path}: AiDisclosureNotice.svelte does not render ${key}`,
		);
		const arbKey = key.replace(/^coachPage\.consent/, 'coachConsent');
		assert.ok(arbKey in ARB_EN, `${path}: ${arbKey} is not in app_en.arb`);
		assert.ok(
			NOTICE_DART.includes(`l10n.${arbKey},`),
			`${path}: ai_disclosure_notice.dart does not render ${arbKey}`,
		);
	}
});

test('the select lists and the registry name the same fields for every table-backed lane', async () => {
	const { selects } = await contextAt(AI_DISCLOSURE_CURRENT_VERSION);
	const tableOf: Record<string, string> = {
		plan: 'training_plans',
		plan_weeks: 'plan_weeks',
		plan_workouts: 'plan_workouts',
		recent_runs: 'runs',
	};
	assert.deepEqual(Object.keys(COACH_CONTEXT_COLUMNS).sort(), Object.keys(tableOf).sort());
	for (const [container, columns] of Object.entries(COACH_CONTEXT_COLUMNS)) {
		const registered = Object.keys(COACH_CONTEXT_REGISTRY)
			.filter((p) => p.startsWith(`${container}.`))
			.map((p) => p.slice(container.length + 1));
		assert.deepEqual(
			[...columns].sort(),
			registered.sort(),
			`${container}: every selected column needs a registry entry, and every entry a selected column`,
		);
		assert.equal(COACH_CONTEXT_CONTAINERS.has(container), true, container);
		// What reaches PostgREST is the column list itself, never `*`.
		assert.deepEqual(
			[...(selects.get(tableOf[container]) ?? [])],
			[columns.join(', ')],
			`${container}: the ${tableOf[container]} read must select exactly its column list`,
		);
	}
});

test('a column the Coach does not select never reaches the context, even when a row carries it', async () => {
	const { data } = await contextAt(AI_DISCLOSURE_CURRENT_VERSION);
	const plan = data.plan as Record<string, unknown>;
	const workout = (data.plan_workouts as Record<string, unknown>[])[0];
	const run = (data.recent_runs as Record<string, unknown>[])[0];
	for (const field of ['user_id', 'is_template', 'assigned_by_coach_id']) {
		assert.equal(field in plan, false, `plan.${field}`);
	}
	for (const field of ['id', 'updated_by']) assert.equal(field in workout, false, `plan_workouts.${field}`);
	for (const field of ['user_id', 'route_id']) assert.equal(field in run, false, `recent_runs.${field}`);
	assert.deepEqual(run.metadata, { is_indoor: false, avg_bpm: 150 });
});

test('heart-rate targets on plan workouts need health-data consent', async () => {
	const withConsent = await contextAt(AI_DISCLOSURE_CURRENT_VERSION);
	const consented = (withConsent.data.plan_workouts as Record<string, unknown>[])[0];
	assert.equal(consented.target_hr_min_bpm, 140);
	assert.equal(consented.target_hr_max_bpm, 155);

	const without = await contextAt(AI_DISCLOSURE_CURRENT_VERSION, {
		...PROFILE,
		health_data_consent_at: null,
	});
	const withheld = (without.data.plan_workouts as Record<string, unknown>[])[0];
	assert.equal(withheld.target_hr_min_bpm, null);
	assert.equal(withheld.target_hr_max_bpm, null);
	assert.equal(withheld.scheduled_date, '2026-06-02');
});

test('an unregistered field on a list row throws instead of being sent', () => {
	assert.throws(
		() =>
			withholdUndisclosed(
				{ plan_workouts: [{ scheduled_date: '2026-06-02', updated_by: 'coach-1' }] },
				AI_DISCLOSURE_CURRENT_VERSION,
			),
		/"plan_workouts.updated_by" is not in COACH_CONTEXT_REGISTRY/,
	);
	assert.throws(
		() => withholdUndisclosed({ plan: { id: 'p1', user_id: USER } }, AI_DISCLOSURE_CURRENT_VERSION),
		/"plan.user_id" is not in COACH_CONTEXT_REGISTRY/,
	);
});

/// Two plans chained back to back, each with a week and a workout, so a
/// season has more than one block to emit.
function seasonFixture(): Record<string, Record<string, unknown>[]> {
	const tables = fullFixture();
	const [p1] = tables.training_plans;
	const [w1] = tables.plan_weeks;
	const [k1] = tables.plan_workouts;
	tables.training_plans = [
		{ ...p1, end_date: '2026-08-30' },
		{ ...p1, id: 'p2', start_date: '2026-08-31', end_date: '2026-12-20' },
	];
	tables.plan_weeks = [w1, { ...w1, id: 'w2', plan_id: 'p2', week_index: 0 }];
	tables.plan_workouts = [k1, { ...k1, id: 'k2', week_id: 'w2', scheduled_date: '2026-08-31' }];
	return tables;
}

test('a season sends more plans under the same registered fields, so the plan bullet covers it', async () => {
	const { data, selects } = await contextAt(
		AI_DISCLOSURE_CURRENT_VERSION,
		PROFILE,
		'season',
		seasonFixture(),
	);
	const season = data.season as Record<string, unknown>[];
	assert.equal(season.length, 2);
	assert.equal('plan' in data, false);
	const planPaths = Object.keys(COACH_CONTEXT_REGISTRY).filter((p) =>
		[...COACH_SEASON_BLOCK_KEYS].some((k) => p.startsWith(`${k}.`)),
	);
	for (const block of season) {
		assert.deepEqual(Object.keys(block).sort(), [...COACH_SEASON_BLOCK_KEYS].sort());
		const paths = emittedPaths(block);
		assert.deepEqual([...new Set(paths)].sort(), planPaths.sort(), 'each block carries exactly the plan fields');
		for (const path of paths) {
			const entry = COACH_CONTEXT_REGISTRY[path];
			assert.ok('bullet' in entry && entry.bullet === 'coachPage.consentBulletPlan', path);
		}
	}
	for (const [container, table] of [
		['plan', 'training_plans'],
		['plan_weeks', 'plan_weeks'],
		['plan_workouts', 'plan_workouts'],
	] as const) {
		assert.deepEqual(
			[...(selects.get(table) ?? [])],
			[COACH_CONTEXT_COLUMNS[container].join(', ')],
			`${table}: a season reads exactly the plan tuple`,
		);
	}
});

test('a season block carries only plan keys, and its fields are withheld like the top-level ones', () => {
	assert.throws(
		() =>
			withholdUndisclosed(
				{ season: [{ plan: { id: 'p1' }, recent_runs: [] }] },
				AI_DISCLOSURE_CURRENT_VERSION,
			),
		/"season.recent_runs" is not a season block key/,
	);
	assert.throws(
		() =>
			withholdUndisclosed(
				{ season: [{ plan: { id: 'p1', user_id: USER }, plan_weeks: [], plan_workouts: [] }] },
				AI_DISCLOSURE_CURRENT_VERSION,
			),
		/"plan.user_id" is not in COACH_CONTEXT_REGISTRY/,
	);
	assert.deepEqual(
		withholdUndisclosed({ season: [] }, AI_DISCLOSURE_CURRENT_VERSION),
		{ season: [] },
	);
});
