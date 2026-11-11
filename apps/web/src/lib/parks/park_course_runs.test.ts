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
	courseEndBearing,
	decodeTrack,
	loadCourses,
	paceMps,
	simulate,
	slice,
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

test('the three-lap run is timed on its fastest lap, the second', () => {
	const c = caseBy('beaver_three_laps');
	const def = caseDefs(loadCourses(read)).find((d) => d.key === c.key);
	assert.ok(def);
	const marks = simulate(def.plan).marks;
	const lap2 = marks.lap2_end - marks.lap1_end;
	const own = c.matched['beaver-lake-trail'];
	assert.ok(own);
	assert.ok(Math.abs(own.time_seconds - lap2) <= 5, `timed ${own.time_seconds.toFixed(1)} s, lap 2 took ${lap2.toFixed(1)} s`);
});

// decisions § 2463: every complete lap is timed and the fastest counts, on a
// loop whose start and end lines are one point and on one whose lines are
// apart, whatever the GPS error. The fastest lap is put first, second and
// third in turn, over 60 seeds each. Before § 2463 the finish of a lap never
// opened the next on a one-point loop, and lap 2 was the time in 2 of 60
// seeds of the middle-fastest run.
{
	const courses = loadCourses(read);
	const def = caseDefs(courses).find((d) => d.key === 'beaver_three_laps');
	assert.ok(def);
	const beaver = courses.find((c) => c.slug === 'beaver-lake-trail');
	assert.ok(beaver);
	const lapEnds = ['lap1_end', 'lap2_end', 'lap3_end'];
	const withPaces = (paces: readonly number[]) => ({
		...def.plan,
		steps: def.plan.steps.map((s) => {
			const lap = s.kind === 'move' && s.endMark ? lapEnds.indexOf(s.endMark) : -1;
			return lap < 0 || s.kind !== 'move' ? s : { ...s, speedMps: paceMps(paces[lap]) };
		}),
	});
	// The start line moved 100 m along the loop: the finish is then 100 m
	// before the start, and each lap is timed from 100 m to the finish.
	const apartM = 100;
	const startAt = slice(beaver.line, apartM, apartM + 1)[0];
	const startBearing = courseEndBearing(slice(beaver.line, apartM, beaver.lineM), false);
	assert.ok(startBearing !== null);
	const apart: GlobalSegmentGeometry = {
		...beaver.geometry,
		distance_m: beaver.geometry.distance_m - apartM,
		startGate: { lat: startAt.lat, lng: startAt.lng, bearingDeg: startBearing, halfWidthM: 15 },
	};
	for (const [label, geometry, lapShare] of [
		['start and finish on one point', beaver.geometry, 1],
		['start 100 m past the finish', apart, (beaver.lineM - apartM) / beaver.lineM],
	] as const) {
		for (const paces of [
			[270, 360, 330],
			[360, 270, 330],
			[360, 330, 270],
		]) {
			test(`every lap is timed (${label}): laps at ${paces.join(', ')} s/km, the fastest is the effort over 60 seeds`, () => {
				const fastest = paces.indexOf(Math.min(...paces));
				for (let seed = 1; seed <= 60; seed++) {
					const run = simulate({ ...withPaces(paces), seed });
					const ends = lapEnds.map((m) => run.marks[m]);
					const starts = [run.marks.lap1_start, ends[0], ends[1]];
					const laps = ends.map((end, k) => (end - starts[k]) * lapShare);
					const eff: GlobalSegmentEffortResult | null = computeGlobalSegmentEfforts(toTrack(run.fixes, baseMs), [
						geometry,
					])[0];
					assert.ok(eff, `seed ${seed}: no effort`);
					// Which lap it is, not how close: two line crossings' GPS error
					// over 60 seeds reaches past one case's tolerance (6.1 s at
					// worst here), but never near a quarter of the gap to the
					// next-fastest lap (27 s or more).
					const errs = laps.map((l) => Math.abs(eff.time_seconds - l));
					const next = Math.min(...laps.filter((_, k) => k !== fastest));
					assert.ok(
						errs[fastest] < (next - laps[fastest]) / 4,
						`seed ${seed}: timed ${eff.time_seconds.toFixed(1)} s, laps ${laps.map((l) => l.toFixed(1)).join(', ')} s`,
					);
				}
			});
		}
	}
}
