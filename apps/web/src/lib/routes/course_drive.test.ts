import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	DRIVE_LEAD_MAX_M,
	DRIVE_LEAD_MIN_M,
	DRIVE_MAX_JOIN_M,
	DriveCueAnnouncer,
	appleMapsUrl,
	buildDriveNotes,
	climbFrom,
	cumulativeM,
	driveAtM,
	driveLeadM,
	googleMapsLegUrl,
	mapsLegUrl,
	mapsStartUrl,
	placeOnLine,
	planDriveLegs,
	pointAtAlong,
	snapWithinAlong,
	undrivableStretches,
	wazeUrl,
	type DriveCue,
	type DriveNote,
	type DrivePoint
} from './course_drive';

// A straight line due north from 37.5,-77.45: one point every 0.001° of
// latitude, about 111.2 m apart.
const STEP_M = 111.19;
function north(n: number, from = 37.5, lng = -77.45): DrivePoint[] {
	return Array.from({ length: n }, (_, i) => ({ lat: from + i * 0.001, lng }));
}
const LINE = north(41); // ~4.45 km

// Out 2 km and back on the same road, the return pass 20 m to the east.
const OUT_AND_BACK: DrivePoint[] = [
	...north(19),
	...north(19)
		.reverse()
		.map((p) => ({ lat: p.lat, lng: p.lng + 0.00023 }))
];

function note(alongM: number, label = `n${alongM}`): DriveNote {
	return { alongM, kind: 'note', label, services: [], cutoff: null, climb: null };
}

const near = (a: number, b: number, tol: number) =>
	assert.ok(Math.abs(a - b) <= tol, `${a} is not within ${tol} of ${b}`);

test('cumulativeM measures each point from the start', () => {
	assert.deepEqual(cumulativeM([]), []);
	assert.deepEqual(cumulativeM([{ lat: 1, lng: 1 }]), [0]);
	const cum = cumulativeM(LINE);
	assert.equal(cum[0], 0);
	near(cum[40], 40 * STEP_M, 2);
});

test('snapWithinAlong answers null for a degenerate line or an inverted window', () => {
	assert.equal(snapWithinAlong({ lat: 37.5, lng: -77.45 }, [LINE[0]], [0], 0, 100), null);
	const cum = cumulativeM(LINE);
	assert.equal(snapWithinAlong({ lat: 37.5, lng: -77.45 }, LINE, cum, 500, 100), null);
	assert.equal(snapWithinAlong({ lat: NaN, lng: -77.45 }, LINE, cum, 0, 100), null);
});

test('snapWithinAlong follows the pass of an out-and-back the window names', () => {
	const cum = cumulativeM(OUT_AND_BACK);
	const p = { lat: 37.505, lng: -77.45 };
	const out = snapWithinAlong(p, OUT_AND_BACK, cum, 0, 1500)!;
	near(out.alongM, 5 * STEP_M, 3);
	const back = snapWithinAlong(p, OUT_AND_BACK, cum, 2500, 4500)!;
	assert.ok(back.alongM > 2500, `${back.alongM}`);
	near(back.offsetM, 20, 3);
});

test('placeOnLine puts a marker on the pass its position hint names', () => {
	const cum = cumulativeM(OUT_AND_BACK);
	const p = { lat: 37.505, lng: -77.4499 };
	const first = placeOnLine(p, OUT_AND_BACK, cum, 600)!;
	near(first.alongM, 5 * STEP_M, 3);
	const second = placeOnLine(p, OUT_AND_BACK, cum, 3400)!;
	assert.ok(second.alongM > 3000, `${second.alongM}`);
});

test('placeOnLine without a hint takes the nearest pass, and refuses a far marker', () => {
	const cum = cumulativeM(OUT_AND_BACK);
	const nearest = placeOnLine({ lat: 37.505, lng: -77.44995 }, OUT_AND_BACK, cum, null)!;
	assert.ok(nearest.alongM < 2000, `${nearest.alongM}`);
	assert.equal(placeOnLine({ lat: 37.505, lng: -77.45 + 0.01 }, OUT_AND_BACK, cum, null), null);
});

test('pointAtAlong clamps to the ends and interpolates between points', () => {
	const cum = cumulativeM(LINE);
	assert.deepEqual(pointAtAlong(LINE, cum, -5), { lat: 37.5, lng: -77.45 });
	assert.deepEqual(pointAtAlong(LINE, cum, 1e9), { lat: LINE[40].lat, lng: -77.45 });
	const mid = pointAtAlong(LINE, cum, cum[1] / 2)!;
	near(mid.lat, 37.5005, 1e-9);
	assert.equal(pointAtAlong([], [], 10), null);
});

test('buildDriveNotes orders markers along the line and drops the ones off it', () => {
	const notes = buildDriveNotes(
		[
			{ kind: 'hazard', label: ' Pothole ', lat: 37.52, lng: -77.45, position_m: 2224, meta: null },
			{
				kind: 'aid_station',
				label: 'Aid 1',
				lat: 37.505,
				lng: -77.45,
				position_m: 556,
				meta: { services: ['water', 'water', 'food', 7] }
			},
			{ kind: 'mystery', label: 'Odd', lat: 37.51, lng: -77.45, position_m: null, meta: {} },
			{ kind: 'note', label: 'Far away', lat: 37.51, lng: -77.4, position_m: 1112, meta: {} },
			{
				kind: 'cutoff',
				label: 'Cut',
				lat: 37.53,
				lng: -77.45,
				position_m: 3336,
				meta: { cutoff_clock: '10:30', services: ['water'] }
			}
		],
		LINE
	);
	assert.deepEqual(
		notes.map((n) => [n.kind, n.label]),
		[
			['aid_station', 'Aid 1'],
			['custom', 'Odd'],
			['hazard', 'Pothole'],
			['cutoff', 'Cut']
		]
	);
	assert.deepEqual(notes[0].services, ['water', 'food']);
	assert.deepEqual(notes[3].services, []);
	assert.deepEqual(notes[3].cutoff, { clock: '10:30' });
	assert.equal(notes[0].cutoff, null);
	near(notes[2].alongM, 20 * STEP_M, 3);
});

test('climbFrom measures a climb from its marker to the crest', () => {
	// Flat for 1 km, then up 3 m every point for 6 points, then down.
	const line = north(20).map((p, i) => ({
		...p,
		ele: i < 9 ? 100 : i <= 15 ? 100 + (i - 9) * 3 : 118 - (i - 15) * 6
	}));
	const cum = cumulativeM(line);
	const climb = climbFrom(line, cum, cum[9])!;
	near(climb.lengthM, 6 * STEP_M, 2);
	assert.equal(climb.gradePct, 2.7);
	assert.equal(climbFrom(LINE, cumulativeM(LINE), 500), null);
	const gentle = north(20).map((p, i) => ({ ...p, ele: 100 + i * 0.4 }));
	assert.equal(climbFrom(gentle, cumulativeM(gentle), 0), null);
});

test('driveLeadM is about 15 s ahead, held between its floor and ceiling', () => {
	assert.equal(driveLeadM(0), DRIVE_LEAD_MIN_M);
	assert.equal(driveLeadM(Number.NaN), DRIVE_LEAD_MIN_M);
	assert.equal(driveLeadM(-3), DRIVE_LEAD_MIN_M);
	assert.equal(driveLeadM(14), 210);
	assert.equal(driveLeadM(25), 375);
	assert.equal(driveLeadM(200), DRIVE_LEAD_MAX_M);
});

test('driveAtM widens with speed above its 30 m floor', () => {
	assert.equal(driveAtM(0), 30);
	assert.equal(driveAtM(5), 30);
	assert.equal(driveAtM(20), 60);
});

test('the announcer speaks a note ahead, then at it, then never again', () => {
	const a = new DriveCueAnnouncer([note(1000)]);
	assert.equal(a.next(0, 14), null);
	const ahead = a.next(800, 14)!;
	assert.equal(ahead.band, 'ahead');
	assert.equal(ahead.aheadM, 200);
	assert.equal(a.next(850, 14), null);
	assert.equal(a.next(980, 14)!.band, 'at');
	assert.equal(a.next(1000, 14), null);
	assert.equal(a.next(1100, 14), null);
	assert.equal(a.remaining, 0);
});

test('a fix inside both bands at once speaks only the at cue', () => {
	const a = new DriveCueAnnouncer([note(1000)]);
	const cue = a.next(990, 14)!;
	assert.equal(cue.band, 'at');
	assert.equal(a.next(995, 14), null);
});

test('a note passed between fixes with nothing said is reported once', () => {
	const a = new DriveCueAnnouncer([note(1000), note(3000)]);
	assert.equal(a.next(700, 14), null);
	const passed = a.next(1300, 14)!;
	assert.equal(passed.band, 'passed');
	assert.equal(passed.aheadM, -300);
	assert.equal(a.next(1310, 14), null);
	// Far past the second (a GPS gap): retired without a word.
	assert.equal(a.next(4000, 14), null);
	assert.equal(a.remaining, 0);
});

test('joining mid-course retires the notes behind the join silently', () => {
	const a = new DriveCueAnnouncer([note(500), note(1000), note(4000)], 2000);
	assert.equal(a.remaining, 1);
	assert.equal(a.next(2000, 14), null);
	assert.equal(a.next(3800, 14)!.note.alongM, 4000);
});

test('the second of two close notes waits for the first to be reached', () => {
	const a = new DriveCueAnnouncer([note(1000, 'a'), note(1100, 'b')]);
	assert.equal(a.next(800, 14)!.note.label, 'a');
	assert.equal(a.next(820, 14), null);
	const at = a.next(970, 14)!;
	assert.deepEqual([at.note.label, at.band], ['a', 'at']);
	const next = a.next(975, 14)!;
	assert.deepEqual([next.note.label, next.band], ['b', 'ahead']);
});

test('at 90 km/h with a fix every two seconds every note is still heard', () => {
	const notes = [300, 900, 960, 2000, 2050, 3500].map((d) => note(d));
	const a = new DriveCueAnnouncer(notes);
	const heard = new Set<number>();
	const cues: DriveCue[] = [];
	for (let along = 0; along <= 4000; along += 50) {
		for (let c = a.next(along, 25); c !== null; c = a.next(along, 25)) {
			heard.add(c.index);
			cues.push(c);
		}
	}
	assert.equal(heard.size, notes.length);
	assert.ok(cues.every((c) => c.aheadM <= driveLeadM(25)));
});

test('planDriveLegs pins each Google leg every 1.5 km with nine stops', () => {
	const line = north(271); // ~30 km
	const total = cumulativeM(line)[270];
	const legs = planDriveLegs(line, 9);
	assert.equal(legs.length, 3);
	for (const leg of legs) assert.equal(leg.via.length, 8);
	assert.equal(legs[0].start.alongM, 0);
	near(legs[2].end.alongM, total, 1e-6);
	near(legs[1].start.alongM, legs[0].end.alongM, 1e-6);
	near(legs[0].via[0].alongM - legs[0].start.alongM, total / 3 / 9, 1e-6);
	assert.deepEqual(
		legs.map((l) => l.index),
		[0, 1, 2]
	);
});

test('planDriveLegs gives a single-destination app one leg every 3 km', () => {
	const legs = planDriveLegs(north(271), 0);
	assert.equal(legs.length, 11); // 30.02 km
	assert.ok(legs.every((l) => l.via.length === 0));
	const mobileWeb = planDriveLegs(north(271), 3);
	assert.equal(mobileWeb.length, 7);
	assert.ok(mobileWeb.every((l) => l.via.length === 2));
});

test('planDriveLegs never drives across a gap in the served line', () => {
	const line = [...north(10), ...north(10, 37.53)];
	const cum = cumulativeM(line);
	assert.ok(cum[10] - cum[9] > DRIVE_MAX_JOIN_M);
	const legs = planDriveLegs(line, 9);
	assert.equal(legs.length, 2);
	near(legs[0].end.alongM, cum[9], 1e-6);
	near(legs[1].start.alongM, cum[10], 1e-6);
});

test('planDriveLegs has nothing to plan on a point or a stub', () => {
	assert.deepEqual(planDriveLegs([], 9), []);
	assert.deepEqual(planDriveLegs([LINE[0]], 9), []);
	assert.deepEqual(planDriveLegs([{ lat: 37.5, lng: -77.45 }, { lat: 37.5001, lng: -77.45 }], 9), []);
});

test('googleMapsLegUrl drives from here through the leg, inside the URL cap', () => {
	const leg = {
		index: 0,
		start: { lat: 37.5, lng: -77.45, alongM: 0 },
		via: [{ lat: 37.51234567, lng: -77.4, alongM: 1 }],
		end: { lat: 37.52, lng: -77.35, alongM: 2 }
	};
	assert.equal(
		googleMapsLegUrl(leg),
		'https://www.google.com/maps/dir/?api=1&destination=37.52000%2C-77.35000' +
			'&waypoints=37.50000%2C-77.45000%7C37.51235%2C-77.40000&travelmode=driving'
	);
	assert.equal(mapsLegUrl('google', leg), googleMapsLegUrl(leg));
	for (const l of planDriveLegs(north(271), 9)) assert.ok(googleMapsLegUrl(l).length < 2048);
});

test('Apple Maps, Waze and the drive-to-start links each name one destination', () => {
	const p = { lat: 37.5, lng: -77.45 };
	assert.equal(appleMapsUrl(p), 'https://maps.apple.com/?daddr=37.50000%2C-77.45000&dirflg=d');
	assert.equal(wazeUrl(p), 'https://waze.com/ul?ll=37.50000%2C-77.45000&navigate=yes');
	const leg = { index: 0, start: { ...p, alongM: 0 }, via: [], end: { lat: 37.6, lng: -77.45, alongM: 1 } };
	assert.equal(mapsLegUrl('apple', leg), appleMapsUrl(leg.end));
	assert.equal(mapsLegUrl('waze', leg), wazeUrl(leg.end));
	assert.equal(
		mapsStartUrl('google', p),
		'https://www.google.com/maps/dir/?api=1&destination=37.50000%2C-77.45000&travelmode=driving'
	);
	assert.equal(mapsStartUrl('apple', p), appleMapsUrl(p));
	assert.equal(mapsStartUrl('waze', p), wazeUrl(p));
});

test('undrivableStretches finds where the router leaves the course', () => {
	assert.deepEqual(undrivableStretches(LINE, LINE), []);
	// The router swings 300 m east between 1.5 km and 2.5 km.
	const routed = LINE.map((p, i) => (i >= 14 && i <= 22 ? { lat: p.lat, lng: p.lng + 0.0034 } : p));
	const stretches = undrivableStretches(LINE, routed);
	assert.equal(stretches.length, 1);
	near(stretches[0].startM, 13.5 * STEP_M, 60);
	near(stretches[0].endM, 22.5 * STEP_M, 60);
});

test('undrivableStretches ignores a short wobble and reports all of an unrouted course', () => {
	const wobble = LINE.map((p, i) => (i === 20 ? { lat: p.lat, lng: p.lng + 0.0034 } : p));
	assert.deepEqual(undrivableStretches(LINE, wobble), []);
	const total = cumulativeM(LINE)[40];
	assert.deepEqual(undrivableStretches(LINE, []), [{ startM: 0, endM: total }]);
	assert.deepEqual(undrivableStretches([LINE[0]], LINE), []);
});
