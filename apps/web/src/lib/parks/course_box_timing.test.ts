// The box timing rule on the real catalogue courses (issue #1446, decisions
// § 2589): seeded runs with a 3 m drifting GPS error, scored by the matcher
// the server bundles. A run that did the course is timed when it stops just
// past or just short of the finish, starts recording on the start line,
// records a fix every 5 or 15 s, loses GPS for 90 s across the finish, or is
// a 50K at 8.7 h; a run that stops halfway or cuts the course is not.
//
// Each rate is over every course of Pocahontas, Deep Run and the Virginia
// Capital Trail (staged, but its geometry is the one that will load). The
// runs are deterministic, so a rate moves only when the rule or a course does.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { computeGlobalSegmentEfforts } from '../segments/segments';
import { gatesShareSpot, COURSE_GATE_BOX_DEPTH_M } from '../races/course_gates';
import { loadCourses, type ParkCourse } from './course_run_fixture';
import {
	SIM_PARK_DIRS,
	simLineSpan,
	simRun,
	simScenarios,
	simTimedRate,
	type SimScenario,
} from './course_box_timing_sim';

const ROOT = resolve(import.meta.dirname, '../../../../..');
const read = (path: string) => readFileSync(resolve(ROOT, path), 'utf8');
const COURSES = SIM_PARK_DIRS.flatMap((dir) => loadCourses(read, dir));
const SHORT = COURSES.filter((c) => c.lineM < 25_000);
const LONG = COURSES.filter((c) => c.lineM >= 25_000);
const SHARED = SHORT.filter((c) => gatesShareSpot(c.gates.start, c.gates.end));

const score = (track: Parameters<typeof computeGlobalSegmentEfforts>[0], geometry: ParkCourse['geometry']) =>
	computeGlobalSegmentEfforts(track, [geometry])[0];

function scenario(label: string): SimScenario {
	const s = simScenarios().find((x) => x.label === label);
	assert.ok(s, `scenario ${label}`);
	return s;
}

/** Timed share of `trials` runs per course, over the given courses. */
function rate(courses: readonly ParkCourse[], s: SimScenario, trials: number): { pct: number; detail: string } {
	let timed = 0;
	let total = 0;
	const detail: string[] = [];
	for (const c of courses) {
		const r = simTimedRate(c, s, trials, score);
		timed += r.timed;
		total += r.trials;
		detail.push(`${c.slug} ${r.timed}/${r.trials}`);
	}
	return { pct: (100 * timed) / total, detail: detail.join(', ') };
}

test('the catalogue has short courses, shared-box courses and 50K-length courses to run', () => {
	assert.ok(SHORT.length >= 8, `${SHORT.length} short courses`);
	assert.ok(SHARED.length >= 5, `${SHARED.length} shared-box courses`);
	assert.ok(LONG.some((c) => c.distanceM >= 50_000), 'a 50K');
});

const TIMED: [label: string, courses: () => readonly ParkCourse[], trials: number, atLeastPct: number][] = [
	['stop 5 m past the finish', () => SHORT, 10, 98],
	['stop 1 m past the finish', () => SHORT, 10, 95],
	['stop 3 m short of the finish line', () => SHARED, 10, 95],
	['stop 3 m short, stand 10 s', () => SHARED, 10, 95],
	['start recording 0.5 m behind the start line', () => SHORT, 10, 95],
	['start recording on the start line', () => SHORT, 10, 95],
	['a fix every 5 s', () => COURSES, 6, 95],
	['a fix every 15 s', () => COURSES, 6, 90],
	['90 s GPS gap across the finish', () => SHORT, 10, 95],
];

for (const [label, courses, trials, atLeast] of TIMED) {
	test(`timed: ${label}`, (t) => {
		const r = rate(courses(), scenario(label), trials);
		t.diagnostic(`${r.pct.toFixed(0)}% (${r.detail})`);
		assert.ok(r.pct >= atLeast, `${label}: ${r.pct.toFixed(0)}% timed, want at least ${atLeast}% (${r.detail})`);
	});
}

const REFUSED = ['stop halfway', 'cut the middle fifth'];

for (const label of REFUSED) {
	test(`no time: ${label}`, () => {
		const r = rate(COURSES, scenario(label), 4);
		assert.equal(r.pct, 0, `${label}: ${r.detail}`);
	});
}

test('a run that skips a third of the course is refused by the length guard', () => {
	const r = rate(COURSES, { ...scenario('stop 5 m past the finish'), cut: [0.3, 0.63], label: 'cut a third' }, 4);
	assert.equal(r.pct, 0, r.detail);
});

test('a 50K at 1.6 m/s (8.7 h) with a fix each second is timed, line to line less the shared box', () => {
	const s: SimScenario = { ...scenario('stop 5 m past the finish'), speedMps: 1.6, label: '50K' };
	for (const c of LONG.filter((x) => x.distanceM >= 50_000)) {
		for (let seed = 1; seed <= 2; seed++) {
			const e = score(simRun(c, s, seed), c.geometry);
			assert.ok(e, `${c.slug} seed ${seed}: no time`);
			const { startM, endM } = simLineSpan(c);
			const boxM = gatesShareSpot(c.gates.start, c.gates.end) ? COURSE_GATE_BOX_DEPTH_M : 0;
			const want = (endM - startM - boxM) / s.speedMps;
			assert.ok(Math.abs(e.time_seconds - want) / want < 0.02, `${c.slug}: ${e.time_seconds} s, about ${want.toFixed(0)} s`);
		}
	}
});

test('a time across a 90 s gap at the finish is within the gap of the time without one', () => {
	const gap = scenario('90 s GPS gap across the finish');
	const plain: SimScenario = { ...gap, gapS: undefined, label: 'no gap' };
	for (const c of SHORT) {
		const a = score(simRun(c, gap, 1), c.geometry);
		const b = score(simRun(c, plain, 1), c.geometry);
		assert.ok(a && b, c.slug);
		assert.ok(Math.abs(a.time_seconds - b.time_seconds) < 15, `${c.slug}: ${a.time_seconds} vs ${b.time_seconds}`);
	}
});
