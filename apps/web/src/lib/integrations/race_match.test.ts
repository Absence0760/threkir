import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { Gate } from '../geo/gate_crossing';
import {
	bestRaceMatch,
	isRaceMatchCandidate,
	raceMatch,
	raceMatchFixes,
	raceMatchScore,
	RACE_MATCH_RADIUS_M,
	RACE_MATCH_THRESHOLD,
	runCrossesCourse,
	startedOnRaceDay,
	type ListingMatchInput,
	type RaceMatchFix,
	type RunMatchInput
} from './race_match';

// Issue #1389: the 2026 Richmond Marathon, 07:00 EST on Sat 14 Nov 2026, a
// course from a Broad St start (heading east) to a 5th & Byrd finish (heading
// south), against TFC Turkey Trot on Thanksgiving.
const RACE_START = '2026-11-14T12:00:00Z';
const COURSE: [number, number][] = [
	[37.548, -77.461],
	[37.548, -77.45],
	[37.54, -77.444],
	[37.5355, -77.444]
];
const START_LINE: Gate = { lat: 37.548, lng: -77.46, bearingDeg: 90, halfWidthM: 15 };
const FINISH_LINE: Gate = { lat: 37.5365, lng: -77.444, bearingDeg: 180, halfWidthM: 15 };
const LINES = { start: START_LINE, finish: FINISH_LINE };

/** The course walked at 4 m/s, one fix a second from the race start. */
function walk(points: [number, number][], startedAt = RACE_START): RaceMatchFix[] {
	const t0 = Date.parse(startedAt);
	const out: RaceMatchFix[] = [];
	let t = t0;
	for (let i = 0; i < points.length - 1; i++) {
		const [aLat, aLng] = points[i];
		const [bLat, bLng] = points[i + 1];
		const dy = (bLat - aLat) * 111_195;
		const dx = (bLng - aLng) * 111_195 * Math.cos((aLat * Math.PI) / 180);
		const steps = Math.max(1, Math.ceil(Math.hypot(dx, dy) / 4));
		for (let k = 0; k < steps; k++) {
			const f = k / steps;
			out.push({ lat: aLat + f * (bLat - aLat), lng: aLng + f * (bLng - aLng), tMs: t });
			t += 1000;
		}
	}
	const [lLat, lLng] = points[points.length - 1];
	out.push({ lat: lLat, lng: lLng, tMs: t });
	return out;
}

const RICHMOND_RUN: RunMatchInput = { startedAt: RACE_START, distanceM: 42_600, track: walk(COURSE) };

const RICHMOND: ListingMatchInput = {
	race_date: '2026-11-14',
	distance_m: 42_195,
	location: { lat: 37.5407, lng: -77.436 },
	lines: LINES
};
const TURKEY_TROT: ListingMatchInput = {
	race_date: '2026-11-26',
	distance_m: 5_000,
	location: { lat: 37.545, lng: -77.44 },
	lines: null
};

test('startedOnRaceDay: the race morning is on the day, Thanksgiving is not', () => {
	assert.equal(startedOnRaceDay(RACE_START, '2026-11-14'), true);
	assert.equal(startedOnRaceDay(RACE_START, '2026-11-26'), false);
});

test('startedOnRaceDay: the window is the day from UTC+14 to UTC-12', () => {
	assert.equal(startedOnRaceDay('2026-11-13T10:00:00Z', '2026-11-14'), true);
	assert.equal(startedOnRaceDay('2026-11-13T09:59:59Z', '2026-11-14'), false);
	assert.equal(startedOnRaceDay('2026-11-15T11:59:59Z', '2026-11-14'), true);
	assert.equal(startedOnRaceDay('2026-11-15T12:00:00Z', '2026-11-14'), false);
});

test('startedOnRaceDay: a malformed date or start is never on the day', () => {
	assert.equal(startedOnRaceDay(RACE_START, '14/11/2026'), false);
	assert.equal(startedOnRaceDay('not a time', '2026-11-14'), false);
});

test('a race on another date is excluded whatever else matches', () => {
	assert.equal(raceMatch(RICHMOND_RUN, TURKEY_TROT), null);
	assert.equal(raceMatch(RICHMOND_RUN, { ...RICHMOND, race_date: '2026-11-26' }), null);
	assert.equal(raceMatchScore(RICHMOND_RUN, TURKEY_TROT), 0);
});

test('a same-day race of a different distance is excluded', () => {
	assert.equal(raceMatch(RICHMOND_RUN, { ...TURKEY_TROT, race_date: '2026-11-14' }), null);
	assert.equal(raceMatch(RICHMOND_RUN, { ...RICHMOND, distance_m: 21_097 }), null);
});

test('the course distance stands in for a listing with none', () => {
	assert.notEqual(
		raceMatch(RICHMOND_RUN, { ...RICHMOND, distance_m: null, course_distance_m: 42_195 }),
		null
	);
	assert.equal(
		raceMatch(RICHMOND_RUN, { ...RICHMOND, distance_m: null, course_distance_m: 5_000 }),
		null
	);
});

test('a start more than 50 km from the race is excluded', () => {
	// Virginia Beach, about 150 km east.
	assert.equal(raceMatch(RICHMOND_RUN, { ...RICHMOND, location: { lat: 36.8529, lng: -75.978 } }), null);
});

test('runCrossesCourse: start line then finish line in order', () => {
	assert.equal(runCrossesCourse(RICHMOND_RUN.track, LINES), true);
	assert.equal(runCrossesCourse(walk([...COURSE].reverse()), LINES), false);
	assert.equal(runCrossesCourse(RICHMOND_RUN.track, null), null);
	assert.equal(runCrossesCourse([], LINES), null);
});

test('runCrossesCourse: a course with one usable line is judged on that line', () => {
	const noStart = { start: { ...START_LINE, halfWidthM: 0 }, finish: FINISH_LINE };
	assert.equal(runCrossesCourse(RICHMOND_RUN.track, noStart), true);
	assert.equal(runCrossesCourse(walk(COURSE.slice(0, 2)), noStart), false);
});

test('issue #1389: the Richmond Marathon is offered, not the Turkey Trot', () => {
	const sameDayUnknown: ListingMatchInput = {
		race_date: '2026-11-14',
		distance_m: null,
		location: { lat: 37.549, lng: -77.462 },
		lines: null
	};
	const listings = [
		{ name: 'TFC Turkey Trot', input: TURKEY_TROT },
		{ name: 'Saturday race, no distance', input: sameDayUnknown },
		{ name: 'Richmond Marathon', input: RICHMOND }
	];
	assert.equal(bestRaceMatch(RICHMOND_RUN, listings, (l) => l.input)?.name, 'Richmond Marathon');
});

test('a crossed course ranks above a higher score without lines', () => {
	const exact: ListingMatchInput = {
		race_date: '2026-11-14',
		distance_m: 42_600,
		location: { lat: 37.548, lng: -77.461 },
		lines: null
	};
	const exactScore = raceMatchScore(RICHMOND_RUN, exact);
	const richmondScore = raceMatchScore(RICHMOND_RUN, RICHMOND);
	assert.ok(exactScore > richmondScore, `${exactScore} vs ${richmondScore}`);
	const listings = [
		{ name: 'exact', input: exact },
		{ name: 'Richmond Marathon', input: RICHMOND }
	];
	assert.equal(bestRaceMatch(RICHMOND_RUN, listings, (l) => l.input)?.name, 'Richmond Marathon');
});

test('the score weighs day, proximity, distance and course', () => {
	// Location at the radius' midpoint from the first fix, distance 5 % long
	// (a third of the tolerance), course crossed:
	// (0.5 + 0.3 * 0.5 + 0.2 * (2 / 3) + 0.5) / (0.5 + 0.3 + 0.2 + 0.5).
	const first = RICHMOND_RUN.track![0];
	const north = (RACE_MATCH_RADIUS_M / 2) / 6_371_000 * (180 / Math.PI);
	const m = raceMatch(
		{ ...RICHMOND_RUN, distanceM: 42_195 * 1.05 },
		{ ...RICHMOND, location: { lat: first.lat + north, lng: first.lng } }
	);
	assert.ok(m != null);
	const expected = (0.5 + 0.15 + 0.2 * (2 / 3) + 0.5) / 1.5;
	assert.ok(Math.abs(m.score - expected) < 1e-6, `got ${m.score}, want ${expected}`);
	assert.equal(m.crossesCourse, true);
});

test('a run that misses the lines is still a candidate, ranked by score', () => {
	const late = walk(COURSE.slice(1));
	const m = raceMatch({ ...RICHMOND_RUN, track: late }, RICHMOND);
	assert.ok(m != null);
	assert.equal(m.crossesCourse, false);
	assert.ok(m.score >= RACE_MATCH_THRESHOLD, `got ${m.score}`);
	assert.ok(m.score < raceMatchScore(RICHMOND_RUN, RICHMOND));
});

test('raceMatchFixes keeps timed on-track fixes at their line position', () => {
	const fixes = raceMatchFixes([
		{ lat: 1, lng: 2, ts: '2026-11-14T12:00:00Z' },
		{ lat: 1.1, lng: 2.1 },
		{ lat: 1.2, lng: 2.2, ts: '2026-11-14T12:00:02Z', offTrack: true } as never,
		{ lat: 1.3, lng: 2.3, smoothedLat: 1.31, smoothedLng: 2.31, ts: '2026-11-14T12:00:03Z' },
		{ lat: 1.4, lng: 2.4, ts: 'garbage' }
	]);
	assert.deepEqual(fixes, [
		{ lat: 1, lng: 2, tMs: Date.parse('2026-11-14T12:00:00Z') },
		{ lat: 1.31, lng: 2.31, tMs: Date.parse('2026-11-14T12:00:03Z') }
	]);
	assert.deepEqual(raceMatchFixes(null), []);
});

test('isRaceMatchCandidate gates on the documented 0.5 threshold', () => {
	assert.equal(RACE_MATCH_THRESHOLD, 0.5);
	assert.equal(isRaceMatchCandidate(RICHMOND_RUN, RICHMOND), true);
	assert.equal(isRaceMatchCandidate(RICHMOND_RUN, TURKEY_TROT), false);
});

test('the date alone is never enough', () => {
	const unknown: ListingMatchInput = { race_date: '2026-11-14', distance_m: null, location: null };
	assert.equal(raceMatch(RICHMOND_RUN, unknown), null);
	assert.equal(raceMatch({ startedAt: RACE_START, distanceM: null }, unknown), null);
	assert.notEqual(raceMatch({ startedAt: RACE_START, distanceM: 42_100 }, { ...unknown, distance_m: 42_195 }), null);
});

test('bestRaceMatch is null when nothing passes', () => {
	assert.equal(bestRaceMatch(RICHMOND_RUN, [TURKEY_TROT], (l) => l), null);
	assert.equal(bestRaceMatch(RICHMOND_RUN, [], (l: ListingMatchInput) => l), null);
});
