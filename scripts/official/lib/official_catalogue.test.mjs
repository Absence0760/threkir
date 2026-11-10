// Unit tests for the official content catalogue and its release stage
// (issue #1190, decisions § 2446).
// Run: node --test scripts/official/lib/official_catalogue.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { CATALOGUE_ROOT, officialCatalogueStage, readCatalogue } from '../sync.mjs';
import {
	GOAL_EVENTS,
	PLAN_PHASES,
	SYNC_COLUMNS,
	WORKOUT_KINDS,
	catalogueNote,
	checkCatalogue,
	checkChallenge,
	checkPlan,
	checkRaceCourse,
	checkRoutine,
	officialCatalogueSql,
	payloadOf,
} from './official_catalogue.mjs';
import { STAGES } from '../../prod_sync/run.mjs';
import { prodConfigStages } from '../../prod_sync/config.mjs';
import { parseCsv, runStages } from '../../prod_sync/lib/stages.mjs';

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../../..');
const CLUB = '11111111-1111-4111-8111-111111111111';
const PUBLISHER = { clubSlug: 'official', clubId: CLUB };

const plan = () =>
	/** @type {any} */ ({
	slug: 'p',
	name: 'P',
	goal_event: 'distance_5k',
	goal_distance_m: 5000,
	days_per_week: 3,
	end_day: 6,
	weeks: [{ week_index: 0, phase: 'race', workouts: [{ day: 6, kind: 'race', target_distance_m: 5000 }] }],
});
const routine = () =>
	/** @type {any} */ ({
	slug: 'r',
	title: 'R',
	exercises: [{ name: 'Plank', modality: 'time', sets: [{ target_duration_s: 30 }] }],
});
const challenge = () =>
	/** @type {any} */ ({
	slug: 'c',
	recurrence: 'monthly',
	title: 'Run 50 km in {period}',
	metric: 'distance',
	goal_value: 50000,
});
const course = () =>
	/** @type {any} */ ({
	slug: 'k',
	name: 'K',
	description: 'Traced from the published course map.',
	source_ref: 'https://example.org/map.pdf',
	distance_m: 1000,
	listing: { provider: 'runsignup', provider_race_id: '1' },
	waypoints: [
		{ lat: 1, lng: 2 },
		{ lat: 1.001, lng: 2 },
	],
});
const empty = () => ({ plans: [], gym_routines: [], challenges: [], race_courses: [] });

test('the committed catalogue reads and passes every check', () => {
	const catalogue = readCatalogue();
	assert.ok(catalogue.plans.length > 0, 'plans');
	assert.ok(catalogue.gym_routines.length > 0, 'gym routines');
	assert.ok(catalogue.challenges.length > 0, 'challenges');
});

test('the three Postgres enums the plan check enumerates match the generated types', () => {
	const src = fs.readFileSync(path.join(REPO, 'apps/web/src/lib/database.types.ts'), 'utf8');
	const constants = src.slice(src.indexOf('export const Constants'));
	/** @param {string} name */
	const read = (name) => {
		const m = constants.match(new RegExp(`${name}: \\[([^\\]]*)\\]`));
		assert.ok(m, `${name} is in Constants`);
		return [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]);
	};
	assert.deepEqual(GOAL_EVENTS, read('goal_event'));
	assert.deepEqual(PLAN_PHASES, read('plan_phase'));
	assert.deepEqual(WORKOUT_KINDS, read('workout_kind'));
});

test('race courses are gated by a flag a migration seeds off, and the committed config leaves it off', () => {
	const migration = fs.readFileSync(
		path.join(REPO, 'apps/backend/supabase/migrations/20271211000001_official_catalogue_items.sql'),
		'utf8',
	);
	assert.match(migration, /insert into private\.feature_flags \(name, enabled\)\s*values \('official_race_courses', false\)/);
	const config = JSON.parse(fs.readFileSync(path.join(REPO, 'apps/backend/ops/prod_config.json'), 'utf8'));
	const toggle = config.feature_flags.official_race_courses;
	assert.ok(!toggle || toggle.enabled === false || typeof toggle.signoff === 'string', 'turning it on carries its sign-off');
});

test('a plan item is refused for what the database or the library would refuse', () => {
	assert.doesNotThrow(() => checkPlan(plan()));
	assert.throws(() => checkPlan({ ...plan(), goal_event: 'distance_3k' }), /goal_event: must be one of/);
	assert.throws(() => checkPlan({ ...plan(), days_per_week: 1 }), /days_per_week/);
	assert.throws(() => checkPlan({ ...plan(), notes: 'x' }), /unknown key notes/);
	const pace = plan();
	pace.weeks[0].workouts[0] = { ...pace.weeks[0].workouts[0], target_duration_seconds: 1500 };
	assert.throws(() => checkPlan(pace), /duration beside a distance/);
	const twice = plan();
	twice.weeks[0].workouts.push({ day: 6, kind: 'easy', target_distance_m: 1000 });
	assert.throws(() => checkPlan(twice), /second workout on one day/);
	const late = plan();
	late.weeks[0].workouts[0].day = 7;
	assert.throws(() => checkPlan(late), /day/);
	const structured = plan();
	Object.assign(structured.weeks[0].workouts[0], { structure: { steady: { pace_sec_per_km: 300 } } });
	assert.throws(() => checkPlan(structured), /absolute pace/);
	const rest = plan();
	rest.weeks[0].workouts[0] = { day: 6, kind: 'rest', target_rpe_min: 2 };
	assert.throws(() => checkPlan(rest), /rest day with an effort target/);
});

test('a routine item is refused for what the CHECK constraints would refuse', () => {
	assert.doesNotThrow(() => checkRoutine(routine()));
	assert.throws(() => checkRoutine({ ...routine(), exercises: [] }), /at least one exercise/);
	const bad = routine();
	bad.exercises[0].modality = 'reps';
	assert.throws(() => checkRoutine(bad), /modality: must be one of/);
	const sets = routine();
	Object.assign(sets.exercises[0].sets[0], { target_reps_min: 10, target_reps_max: 8 });
	assert.throws(() => checkRoutine(sets), /minimum above its maximum/);
	const load = routine();
	Object.assign(load.exercises[0].sets[0], { target_weight_kg: 20, target_percent_1rm: 70 });
	assert.throws(() => checkRoutine(load), /both a weight and a %1RM/);
	const tempo = routine();
	Object.assign(tempo.exercises[0].sets[0], { tempo: '3-1-1' });
	assert.throws(() => checkRoutine(tempo), /tempo/);
	const superset = routine();
	Object.assign(superset.exercises[0], { superset_group: 1 });
	assert.throws(() => checkRoutine(superset), /superset_group and superset_order/);
	assert.throws(() => checkRoutine({ ...routine(), title: 'x'.repeat(121) }), /title/);
});

test('a challenge item names its period, has a goal, and a streak fits its shortest window', () => {
	assert.doesNotThrow(() => checkChallenge(challenge()));
	assert.throws(() => checkChallenge({ ...challenge(), title: 'Run 50 km' }), /\{period\}/);
	assert.throws(() => checkChallenge({ ...challenge(), recurrence: 'weekly' }), /recurrence/);
	assert.throws(() => checkChallenge({ ...challenge(), goal_value: null }), /goal_value/);
	assert.throws(() => checkChallenge({ ...challenge(), metric: 'park_courses' }), /needs a park_region_code/);
	assert.throws(() => checkChallenge({ ...challenge(), metric: 'streak_days', goal_value: 29 }), /shortest window/);
	assert.doesNotThrow(() => checkChallenge({ ...challenge(), metric: 'streak_days', goal_value: 28 }));
	assert.throws(() => checkChallenge({ ...challenge(), title: `${'x'.repeat(110)} {period}` }), /title/);
	assert.throws(() => checkChallenge({ ...challenge(), activity_type: 'swim' }), /activity_type/);
});

test('a park_courses board carries an ISO 3166-2 region, and no other board takes one', () => {
	const passport = JSON.parse(fs.readFileSync(new URL('./fixtures/virginia-park-passport.json', import.meta.url), 'utf8'));
	assert.doesNotThrow(() => checkChallenge(passport));
	assert.equal(payloadOf({ ...empty(), challenges: [passport] }).challenges[0].park_region_code, 'US-VA');
	assert.match(officialCatalogueSql({ ...empty(), challenges: [passport] }, PUBLISHER), /"park_region_code":"US-VA"/);
	for (const bad of ['us-va', 'US', 'USA-VA', 'US-VAXX', 'US_VA', '', 7, null]) {
		assert.throws(() => checkChallenge({ ...passport, park_region_code: bad }), /needs a park_region_code/, String(bad));
	}
	const { park_region_code: _region, ...noRegion } = passport;
	assert.throws(() => checkChallenge(noRegion), /needs a park_region_code/);
	assert.throws(() => checkChallenge({ ...challenge(), park_region_code: 'US-VA' }), /only a park_courses board/);
	assert.throws(() => checkChallenge({ ...challenge(), park_region_code: null }), /only a park_courses board/);
});

test('a race course names its race once, its published source, and real geometry', () => {
	assert.doesNotThrow(() => checkRaceCourse(course()));
	assert.throws(() => checkRaceCourse({ ...course(), listing_id: CLUB }), /exactly one of listing and listing_id/);
	const byId = course();
	delete (/** @type {any} */ (byId)).listing;
	assert.doesNotThrow(() => checkRaceCourse({ ...byId, listing_id: CLUB }));
	assert.throws(() => checkRaceCourse({ ...course(), source_ref: 'nyrr map' }), /source_ref/);
	assert.throws(() => checkRaceCourse({ ...course(), waypoints: [{ lat: 1, lng: 2 }] }), /two waypoints/);
	assert.throws(() => checkRaceCourse({ ...course(), waypoints: [{ lat: 91, lng: 2 }, { lat: 1, lng: 2 }] }), /lat/);
	assert.throws(() => checkRaceCourse({ ...course(), surface: 'grass' }), /surface/);
});

test('the catalogue refuses a repeated slug and a missing list', () => {
	assert.throws(() => checkCatalogue({ ...empty(), challenges: [challenge(), challenge()] }), /repeats the slug c/);
	assert.throws(() => checkCatalogue(/** @type {any} */ ({ plans: [], gym_routines: [], challenges: [] })), /race_courses: must be a list/);
});

test('the catalogue files are named by their slug, under every known kind', () => {
	const root = fs.mkdtempSync(path.join(tmpdir(), 'official-catalogue-'));
	try {
		fs.mkdirSync(path.join(root, 'challenges'));
		fs.writeFileSync(path.join(root, 'challenges', 'c.json'), JSON.stringify(challenge()));
		assert.throws(() => readCatalogue(root), /catalogue\/plans is missing/, 'a missing kind is refused, not read as empty');
		for (const kind of ['plans', 'gym_routines', 'race_courses']) {
			fs.mkdirSync(path.join(root, kind));
			fs.writeFileSync(path.join(root, kind, '.gitkeep'), '');
		}
		assert.deepEqual(readCatalogue(root), { ...empty(), challenges: [challenge()] }, 'an empty kind keeps a .gitkeep');
		fs.writeFileSync(path.join(root, 'challenges', 'other.json'), JSON.stringify(challenge()));
		assert.throws(() => readCatalogue(root), /holds the slug c; name the file <slug>\.json/);
		fs.rmSync(path.join(root, 'challenges', 'other.json'));
		fs.mkdirSync(path.join(root, 'segments'));
		assert.throws(() => readCatalogue(root), /catalogue\/segments is not a kind/);
	} finally {
		fs.rmSync(root, { recursive: true, force: true });
	}
});

test('the payload drops a plan preset and keeps everything else', () => {
	const catalogue = { ...empty(), plans: [{ ...plan(), preset: { goalEvent: 'distance_5k' } }] };
	const payload = payloadOf(catalogue);
	assert.equal('preset' in payload.plans[0], false);
	assert.deepEqual(payload.plans[0], plan());
});

test('the stage SQL resolves the author at run time and loads the whole catalogue in one call', () => {
	const sql = officialCatalogueSql({ ...empty(), challenges: [challenge()] }, PUBLISHER);
	assert.match(sql, /^set local role service_role;/);
	assert.match(sql, /private\.resolve_club_publisher\('official', '11111111-1111-4111-8111-111111111111'::uuid\)/);
	assert.equal(sql.match(/private\.load_official_catalogue\(/g)?.length, 1);
	assert.match(sql, /select l\.kind, l\.slug, l\.action, l\.target_id, p\.author_id as published_by/);
	assert.match(sql, /\$official_catalogue\$\{"plans":\[\],/);
	assert.throws(() => officialCatalogueSql(empty(), { clubSlug: 'x', clubId: 'nope' }), /not a club slug and id/);
	assert.throws(() => officialCatalogueSql({ ...empty(), plans: [{ slug: 'x' }] }, PUBLISHER), /plan x/);
});

test('a dollar tag inside the payload cannot end the literal', () => {
	const sneaky = { ...challenge(), description: 'ends with $official_catalogue$ here' };
	const sql = officialCatalogueSql({ ...empty(), challenges: [sneaky] }, PUBLISHER);
	assert.match(sql, /\$official_catalogue_1\$\{/);
	assert.match(sql, /\}\$official_catalogue_1\$::jsonb/);
});

test('the release runs the catalogue last, after the prod config, so a flag it flips is read', () => {
	assert.equal(STAGES.at(-1), officialCatalogueStage);
	assert.ok(STAGES.indexOf(prodConfigStages) < STAGES.indexOf(officialCatalogueStage));
	const stage = officialCatalogueStage();
	assert.equal(stage.id, 'official-catalogue');
	assert.match(stage.note, /\d+ plans, \d+ gym routines, \d+ challenges, 0 race courses/);
});

test('the stage summary counts each action, and a course reads as waiting on its flag', () => {
	const catalogue = { ...empty(), race_courses: [course()] };
	assert.match(catalogueNote(catalogue), /load only while official_race_courses is on/);
	const stage = { id: 'official-catalogue', title: 'Official content catalogue', sql: 'select 1;' };
	let out = '';
	const csv = `${SYNC_COLUMNS.join(',')}\nchallenge,c@2027-03,created,${CLUB},${CLUB}\nrace_course,k,gated,,${CLUB}\n`;
	const ok = runStages([stage], {
		dryRun: true,
		runSql: (script) => {
			assert.match(script, /rollback;\n$/);
			return { ok: true, stdout: csv, stderr: '' };
		},
		write: (md) => {
			out += md;
		},
	});
	assert.equal(ok, true);
	assert.match(out, /1 created, 1 gated\./);
	assert.deepEqual(parseCsv(csv).header, SYNC_COLUMNS);
});

test('the committed catalogue root is the one the stage reads', () => {
	assert.equal(path.relative(REPO, CATALOGUE_ROOT), path.join('scripts', 'official', 'catalogue'));
});
