// The synthetic-run generator behind fixtures/park_course_runs.json (issue
// #1342 step 5c): its committed outputs are current, and the runs it makes
// look like what a phone records, so a matcher test over them means
// something. The matcher's verdicts are park_course_runs.test.ts.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { FIXTURE, SQL_TEST, buildOutputs } from '../../../../../scripts/gen_park_course_runs.mjs';
import {
	NOISE_SIGMA_M,
	caseDefs,
	hopM,
	loadCourses,
	simulate,
	type CaseDef,
	type LatLng,
	type ParkCourse,
	type SimulatedRun,
} from './course_run_fixture';

const ROOT = resolve(import.meta.dirname, '../../../../..');
const read = (path: string) => readFileSync(resolve(ROOT, path), 'utf8');
const courses = loadCourses(read);
const defs = caseDefs(courses);
const runs = new Map<string, SimulatedRun>(defs.map((d) => [d.key, simulate(d.plan)]));

const def = (key: string): CaseDef => {
	const d = defs.find((x) => x.key === key);
	assert.ok(d, `no case ${key}`);
	return d;
};
const run = (key: string): SimulatedRun => {
	const r = runs.get(key);
	assert.ok(r, `no run ${key}`);
	return r;
};
const course = (slug: string): ParkCourse => {
	const c = courses.find((x) => x.slug === slug);
	assert.ok(c, `no course ${slug}`);
	return c;
};
const fixAt = (r: SimulatedRun, i: number): LatLng => ({ lat: r.fixes[i].latE6 / 1e6, lng: r.fixes[i].lngE6 / 1e6 });
const errorsOf = (r: SimulatedRun, from = 0, to = r.fixes.length) =>
	r.truth.slice(from, to).map((p, i) => hopM(p, fixAt(r, from + i)));
const rms = (xs: number[]) => Math.sqrt(xs.reduce((s, x) => s + x * x, 0) / xs.length);

test('the committed fixture and the generated block of park_course_boards_test.sql are current', async () => {
	const next = await buildOutputs();
	assert.equal(readFileSync(FIXTURE, 'utf8'), next.fixture, 'fixtures/park_course_runs.json is stale: run `pnpm gen:park-course-runs`');
	assert.equal(readFileSync(SQL_TEST, 'utf8'), next.sql, 'park_course_boards_test.sql is stale: run `pnpm gen:park-course-runs`');
});

test('a plan and its seed make the same run every time, and another seed another run', () => {
	const d = def('beaver_clean');
	assert.deepEqual(simulate(d.plan).fixes, run('beaver_clean').fixes);
	const other = simulate({ ...d.plan, seed: d.plan.seed + 1 });
	assert.equal(other.fixes.length, run('beaver_clean').fixes.length);
	assert.notDeepEqual(other.fixes, run('beaver_clean').fixes);
});

test('every clean run is 1 Hz with about 3 to 8 m of GPS error', () => {
	for (const d of defs.filter((x) => x.key.endsWith('_clean'))) {
		const r = run(d.key);
		for (let i = 1; i < r.fixes.length; i++) assert.equal(r.fixes[i].t - r.fixes[i - 1].t, 1, `${d.key}: fix ${i}`);
		const e = rms(errorsOf(r));
		assert.ok(e >= 3 && e <= 8, `${d.key}: ${e.toFixed(2)} m RMS`);
	}
	assert.ok(NOISE_SIGMA_M * Math.SQRT2 >= 3 && NOISE_SIGMA_M * Math.SQRT2 <= 8);
});

test('the canopy stretch thins the fixes to one every 8 s over checkpoint 2, with more error', () => {
	const r = run('beaver_canopy');
	const from = r.marks.canopy_in;
	const to = r.marks.canopy_out;
	const inside: number[] = [];
	for (let i = 1; i < r.fixes.length; i++) {
		const a = r.fixes[i - 1].t;
		const b = r.fixes[i].t;
		if (a >= from && b <= to) {
			inside.push(i);
			assert.equal(b - a, 8, `fix ${i} under the trees`);
		} else if (b < from || a > to) {
			assert.equal(b - a, 1, `fix ${i} outside the trees`);
		}
	}
	assert.ok(inside.length >= 25, `${inside.length} fixes under the trees`);
	const cp2 = course('beaver-lake-trail').checkpoints[1];
	const nearest = Math.min(...r.truth.map((p) => hopM(p, cp2)));
	const nearestAt = r.truth.findIndex((p) => hopM(p, cp2) === nearest);
	assert.ok(r.fixes[nearestAt].t >= from && r.fixes[nearestAt].t <= to, 'checkpoint 2 is passed under the trees');
	const under = rms(inside.filter((i) => r.fixes[i].t <= to).map((i) => hopM(r.truth[i], fixAt(r, i))));
	assert.ok(under > rms(errorsOf(run('beaver_clean'))) && under <= 12, `${under.toFixed(2)} m RMS under the trees`);
});

test('every run starts in the lot, a minute before it moves, and ends walking off past the finish', () => {
	for (const d of defs) {
		const r = run(d.key);
		const c = course(d.course);
		const first = fixAt(r, 0);
		assert.ok(hopM(first, c.line[0]) >= 100, `${d.key}: first fix ${hopM(first, c.line[0]).toFixed(0)} m from the start`);
		assert.ok(hopM(r.truth[0], r.truth[59]) < 0.01, `${d.key}: standing still for the first minute`);
		if (d.want.effort) {
			const last = r.truth[r.truth.length - 1];
			assert.ok(hopM(last, c.line[c.line.length - 1]) >= 60, `${d.key}: the run ends near the finish`);
			assert.ok(r.fixes[r.fixes.length - 1].t - r.marks[d.want.to] >= 60, `${d.key}: no cool-down`);
		}
	}
});

test('the three-lap run passes the start-finish point four times and the 5K runs are two passes', () => {
	const passes = (r: SimulatedRun, p: LatLng) => {
		let n = 0;
		let near = false;
		for (const q of r.truth) {
			const now = hopM(q, p) < 3;
			if (now && !near) n++;
			near = now;
		}
		return n;
	};
	assert.equal(passes(run('beaver_three_laps'), course('beaver-lake-trail').line[0]), 4);
	for (const key of ['5k_two_passes_slow_fast', '5k_two_passes_fast_slow']) {
		const r = run(key);
		assert.ok(r.marks.pass2_start > r.marks.pass1_end + 60, `${key}: a minute's rest between the passes`);
	}
});

test('each refusal case is what its name says', () => {
	const beaver = course('beaver-lake-trail');
	const [cp1, cp2, cp3] = beaver.checkpoints;
	const minTo = (r: SimulatedRun, p: LatLng) => Math.min(...r.truth.map((q) => hopM(q, p)));

	const cut = run('beaver_shortcut');
	assert.ok(minTo(cut, cp2) >= 60, `the shortcut comes ${minTo(cut, cp2).toFixed(0)} m from checkpoint 2`);
	assert.ok(minTo(cut, cp1) < 5 && minTo(cut, cp3) < 5, 'and runs through the other two');
	let walked = 0;
	for (let i = 1; i < cut.truth.length; i++) walked += hopM(cut.truth[i - 1], cut.truth[i]);
	assert.ok(walked > 0.75 * beaver.distanceM, 'inside the length guard');

	const wrong = run('beaver_wrong_way');
	const order = [cp1, cp2, cp3].map((p) => wrong.truth.findIndex((q) => hopM(q, p) < 5));
	assert.ok(order.every((i) => i >= 0) && order[2] < order[1] && order[1] < order[0], 'every checkpoint, in reverse order');

	const short = run('beaver_short');
	const from = short.fixes.findIndex((f) => f.t >= short.marks.start);
	let onCourse = 0;
	for (let i = from + 1; i < short.truth.length; i++) onCourse += hopM(short.truth[i - 1], short.truth[i]);
	assert.ok(Math.abs(onCourse - (beaver.lineM - 150)) < 15, `stops ${(beaver.lineM - onCourse).toFixed(0)} m short of the finish`);
	assert.ok([cp1, cp2, cp3].every((p) => minTo(short, p) < 5), 'after every checkpoint');

	const near = run('beaver_nearby');
	assert.ok(minTo(near, beaver.gates.start) >= 45, 'never within reach of the start line');
	assert.ok(minTo(near, beaver.line[0]) < 80, 'but close by');
});
