// A run over a real park course is timed on that course and nowhere else
// (issue #1342 step 5c). The TS reader of fixtures/park_course_runs.json, the
// case table the `segments` pair shares with
// apps/mobile_android/test/park_course_runs_test.dart: synthetic 1 Hz runs
// with realistic GPS error over the six committed Pocahontas course lines,
// each scored against all six courses at once, as the segment-match function
// scores a run against its bbox candidates.
//
// Each case is checked twice: against what it is for (an effort within
// tolerance of the true elapsed time between its marks, or none), and
// against `matched`, the result recorded when the fixture was generated, on
// every course, which the Dart twin must reproduce to the millisecond.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	computeGlobalSegmentEfforts,
	type GlobalSegmentEffortResult,
	type GlobalSegmentGeometry,
} from '../segments/segments';
import {
	caseDefs,
	decodeTrack,
	loadCourses,
	simulate,
	toTrack,
	type CourseRunFixture,
} from './course_run_fixture';

const ROOT = resolve(import.meta.dirname, '../../../../..');
const read = (path: string) => readFileSync(resolve(ROOT, path), 'utf8');
const fixture = JSON.parse(read('fixtures/park_course_runs.json')) as CourseRunFixture;
const baseMs = Date.parse(fixture.base_time);

const geometries: GlobalSegmentGeometry[] = fixture.courses.map((c) => {
	const gj = JSON.parse(read(c.geojson));
	const line = gj.features.find((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString');
	const gate = (g: typeof c.start_gate) => ({ lat: g.lat, lng: g.lng, bearingDeg: g.bearing_deg, halfWidthM: g.half_width_m });
	return {
		points: line.geometry.coordinates.map((p: number[]) => ({ lat: p[1], lng: p[0] })),
		distance_m: c.distance_m,
		checkpoints: c.checkpoints,
		startGate: gate(c.start_gate),
		endGate: gate(c.end_gate),
	};
});
const slugs = fixture.courses.map((c) => c.slug);
const caseBy = (key: string) => {
	const c = fixture.cases.find((x) => x.key === key);
	assert.ok(c, `no case ${key}`);
	return c;
};

for (const c of fixture.cases) {
	test(`park course run: ${c.name}`, () => {
		const track = decodeTrack(c.track, baseMs);
		const results = computeGlobalSegmentEfforts(track, geometries);
		const own = results[slugs.indexOf(c.course)];
		if (c.want.effort) {
			assert.ok(own, `no effort on ${c.course} (${c.why})`);
			assert.equal(own.matched_by, 'gate');
			const off = own.time_seconds - c.want.truth_s;
			assert.ok(
				Math.abs(off) <= c.want.tolerance_s,
				`timed ${own.time_seconds.toFixed(2)} s against a true ${c.want.truth_s} s (${off.toFixed(2)} s off, tolerance ${c.want.tolerance_s} s)`,
			);
		} else {
			assert.equal(own, null, `timed ${own?.time_seconds} s on ${c.course} (${c.why})`);
		}
		results.forEach((r, i) => {
			const recorded = c.matched[slugs[i]];
			if (!recorded) {
				assert.equal(r, null, `${slugs[i]}: timed ${r?.time_seconds} s, the fixture recorded nothing`);
				return;
			}
			assert.ok(r, `${slugs[i]}: no effort, the fixture recorded ${recorded.time_seconds} s`);
			assert.ok(Math.abs(r.time_seconds - recorded.time_seconds) < 0.001, `${slugs[i]}: ${r.time_seconds} vs ${recorded.time_seconds}`);
			assert.equal(Date.parse(r.started_at) - baseMs, recorded.started_offset_ms);
			assert.equal(r.matched_by, recorded.matched_by);
		});
	});
}

test('the fixture covers every case issue #1342 step 5c lists', () => {
	const keys = new Set(fixture.cases.map((c) => c.key));
	for (const key of [
		'beaver_clean',
		'5k_clean',
		'10k_clean',
		'half_clean',
		'marathon_clean',
		'50k_clean',
		'beaver_canopy',
		'beaver_shortcut',
		'beaver_wrong_way',
		'beaver_short',
		'beaver_nearby',
		'beaver_three_laps',
		'5k_two_passes_slow_fast',
		'5k_two_passes_fast_slow',
		'10k_one_lap',
		'marathon_one_lap',
		'50k_one_lap',
	]) {
		assert.ok(keys.has(key), `no case ${key}`);
	}
	for (const slug of slugs) {
		assert.ok(
			fixture.cases.some((c) => c.course === slug && c.want.effort && c.matched[slug]),
			`${slug}: no run of the net is timed on it`,
		);
	}
});

test('the shortcut is refused by checkpoint 2 alone: without the checkpoints the same run is timed', () => {
	const c = caseBy('beaver_shortcut');
	const beaver = geometries[slugs.indexOf('beaver-lake-trail')];
	const track = decodeTrack(c.track, baseMs);
	assert.equal(computeGlobalSegmentEfforts(track, [beaver])[0], null);
	const unguarded = computeGlobalSegmentEfforts(track, [{ ...beaver, checkpoints: [] }])[0];
	assert.ok(unguarded, 'the cut is inside the length guard, so only a checkpoint can refuse it');
	assert.equal(unguarded.matched_by, 'gate');
});

test('the wrong way round is refused by the lines alone: it passes every checkpoint, in reverse', () => {
	const c = caseBy('beaver_wrong_way');
	const beaver = geometries[slugs.indexOf('beaver-lake-trail')];
	const track = decodeTrack(c.track, baseMs);
	const reversed = { ...beaver, checkpoints: [...(beaver.checkpoints ?? [])].reverse() };
	assert.equal(computeGlobalSegmentEfforts(track, [reversed])[0], null, 'the start and end lines face the other way');
});

test('a run that completes a shorter course is timed on it: one lap of the 10K is a 5K, of the marathon a half', () => {
	assert.ok(caseBy('10k_one_lap').matched['swift-creek-5k'], 'one 10K lap is the 5K course');
	assert.ok(caseBy('marathon_one_lap').matched['swift-creek-half'], 'one marathon lap is the half course');
	assert.deepEqual(Object.keys(caseBy('50k_one_lap').matched), [], 'the 50K lap is no other course');
});

test('the three-lap run is timed on its third lap, not its fastest (the second), by the same-line loop rule', () => {
	const c = caseBy('beaver_three_laps');
	const defs = caseDefs(loadCourses(read));
	const def = defs.find((d) => d.key === c.key);
	assert.ok(def);
	const marks = simulate(def.plan).marks;
	const lap2 = marks.lap2_end - marks.lap1_end;
	const own = c.matched['beaver-lake-trail'];
	assert.ok(own);
	assert.ok(lap2 < own.time_seconds - 100, `lap 2 (${lap2.toFixed(0)} s) is the fastest and is not the time`);
});

// decisions § 2402 (m6): on a loop whose start and end lines sit on one
// point, the crossing that closes a lap never opens the next, so lap 2 of
// three is never a pass. With GPS error the two lines' crossings can fall on
// different fixes, and then the lap that closed a pass also opens one: over
// 60 seeds of the run above, lap 2 is the time in 2. Whether every lap of a
// same-line loop should be a candidate is the owner's call (§ 2402 names it);
// until it is made, this records that the rule as written is not what GPS
// noise lets the matcher do every time.
test(
	'on a same-line loop, the middle of three laps is never the time, whatever the GPS error',
	{ todo: 'decisions § 2402 m6 is noise-dependent: lap 2 is the time in 2 of 60 seeds; owner call on issue #1342' },
	() => {
		const courses = loadCourses(read);
		const def = caseDefs(courses).find((d) => d.key === 'beaver_three_laps');
		assert.ok(def);
		const beaver = courses.find((c) => c.slug === 'beaver-lake-trail');
		assert.ok(beaver);
		for (let seed = 1; seed <= 60; seed++) {
			const run = simulate({ ...def.plan, seed });
			const lap2 = run.marks.lap2_end - run.marks.lap1_end;
			const eff: GlobalSegmentEffortResult | null = computeGlobalSegmentEfforts(toTrack(run.fixes, baseMs), [
				beaver.geometry,
			])[0];
			assert.ok(eff, `seed ${seed}: no effort`);
			assert.ok(Math.abs(eff.time_seconds - lap2) > 60, `seed ${seed}: lap 2 (${lap2.toFixed(0)} s) was timed`);
		}
	},
);
