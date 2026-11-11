import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GATE_EARTH_RADIUS_M, type Gate } from '../geo/gate_crossing';
import {
	RACE_FINISH_MIN_COVERAGE,
	RACE_FINISH_MIN_COVERAGE_WITH_START,
	RACE_FINISH_ZONE_M,
	RACE_LATE_START_AFTER_MS,
	RACE_LATE_START_FAR_M,
	RACE_START_COMMIT_M,
	RaceFinishDetector,
	ServerClockOffset,
	raceChipTimeS,
	raceCoverageMet,
	raceDistanceM,
	raceGunTimeS,
	raceInFinishZone,
	raceLineUsable,
	raceResultTiming,
	raceStartFlagged,
	raceStopOutcome,
	type RaceFinish,
	type RaceFinishMethod,
	type RaceFix,
	type RaceStart,
} from './race_finish';

// The TS reader of fixtures/race_finish_cases.json, the case table the
// race_finish pair shares with apps/mobile_android/test/race_finish_test.dart
// and Wear's RaceFinishTest.kt. The file's own `schema` block says what each
// section means.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const fixture = JSON.parse(
	readFileSync(join(REPO, 'fixtures', 'race_finish_cases.json'), 'utf-8'),
) as Record<string, unknown>;

const SECTIONS = [
	'distance',
	'zone',
	'coverage',
	'detector',
	'startFlag',
	'clockOffset',
	'gunTime',
	'chipTime',
	'stopOutcome',
	'resultTiming',
	'lines',
];
const META = new Set([
	'spec',
	'reference',
	'readers',
	'schema',
	'constants',
	't0EpochMs',
	'distanceToleranceM',
	'offsetToleranceMs',
	'origin',
]);

type Obj = Record<string, unknown>;

function num(v: unknown): number {
	if (v === 'NaN') return NaN;
	if (v === 'Infinity') return Infinity;
	if (v === '-Infinity') return -Infinity;
	if (typeof v === 'number') return v;
	throw new Error(`not a fixture number: ${String(v)}`);
}

function req(o: Obj, key: string): unknown {
	if (!(key in o)) throw new Error(`case ${String(o.name)} has no '${key}' (nullable fields are explicit)`);
	return o[key];
}

function numOrNull(o: Obj, key: string): number | null {
	const v = req(o, key);
	return v === null ? null : num(v);
}

const constants = fixture.constants as Obj;
const t0 = num(fixture.t0EpochMs);
const distTol = num(fixture.distanceToleranceM);
const offsetTol = num(fixture.offsetToleranceMs);
const origin = fixture.origin as Obj;
const finishLat = num(origin.finishLat);
const finishLng = num(origin.finishLng);
const mPerDegLat = (num(constants.EARTH_RADIUS_M) * Math.PI) / 180;
const gateK = (num(constants.GATE_EARTH_RADIUS_M) * Math.PI) / 180;

function section(name: string): Obj[] {
	return fixture[name] as Obj[];
}

function close(actual: number, expected: number, tol: number, what: string): void {
	assert.ok(Math.abs(actual - expected) <= tol, `${what}: ${actual} != ${expected} (tol ${tol})`);
}

function northFix(o: Obj): RaceFix {
	return {
		lat: finishLat + num(o.northM) / mPerDegLat,
		lng: finishLng,
		atMs: t0 + num(o.atS) * 1000,
		coveredM: num(o.coveredM),
	};
}

function plane(o: Obj): { lat: number; lng: number } {
	return {
		lat: finishLat + num(o.northM) / gateK,
		lng: finishLng + num(o.eastM) / (gateK * Math.cos((finishLat * Math.PI) / 180)),
	};
}

function gateOf(o: unknown): Gate | null {
	if (o === null) return null;
	const g = o as Obj;
	return { ...plane(g), bearingDeg: num(g.bearingDeg), halfWidthM: num(g.halfWidthM) };
}

function planeFix(o: Obj): RaceFix {
	return { ...plane(o), atMs: t0 + num(o.atS) * 1000, coveredM: num(o.coveredM) };
}

function assertStart(got: RaceStart | null, want: unknown, what: string): void {
	if (want === null) {
		assert.equal(got, null, what);
		return;
	}
	const w = want as Obj;
	assert.ok(got !== null, `${what}: expected a start`);
	assert.equal(got.atMs - t0, w.atMs, `${what} atMs`);
	close(got.coveredM, num(w.coveredM), distTol, `${what} coveredM`);
	assert.equal(got.kind, w.kind, `${what} kind`);
}

function assertFinish(got: RaceFinish | null, want: unknown, what: string): void {
	if (want === null) {
		assert.equal(got, null, what);
		return;
	}
	const w = want as Obj;
	assert.ok(got !== null, `${what}: expected a finish`);
	assert.equal(got.atMs - t0, w.atMs, `${what} atMs`);
	close(got.coveredM, num(w.coveredM), distTol, `${what} coveredM`);
	close(got.distanceToFinishM, num(w.distanceToFinishM), distTol, `${what} distanceToFinishM`);
	assert.equal(got.detection, w.detection, `${what} detection`);
	assert.equal(got.gapped, w.gapped, `${what} gapped`);
	assertStart(got.start, req(w, 'start'), `${what} start`);
}

test('every section in the file is one this reader runs', () => {
	const unknown = Object.keys(fixture).filter((k) => !META.has(k) && !SECTIONS.includes(k));
	assert.deepEqual(unknown, []);
	const schemaSections = Object.keys(fixture.schema as Obj).filter(
		(k) => !['general', 'constants', 'origin'].includes(k),
	);
	assert.deepEqual(new Set(schemaSections), new Set(SECTIONS));
	for (const s of SECTIONS) assert.ok(section(s).length > 0, `section ${s} is empty`);
	assert.ok(
		(fixture.readers as string[]).includes('apps/web/src/lib/races/race_finish.test.ts'),
		'this reader is listed in the file',
	);
});

test('the constants match the file', () => {
	assert.equal(RACE_FINISH_ZONE_M, num(constants.FINISH_ZONE_M));
	assert.equal(RACE_FINISH_MIN_COVERAGE, num(constants.MIN_COVERAGE));
	assert.equal(RACE_FINISH_MIN_COVERAGE_WITH_START, num(constants.MIN_COVERAGE_WITH_START));
	assert.equal(RACE_START_COMMIT_M, num(constants.START_COMMIT_M));
	assert.equal(RACE_LATE_START_AFTER_MS, num(constants.LATE_START_AFTER_MS));
	assert.equal(RACE_LATE_START_FAR_M, num(constants.LATE_START_FAR_M));
	assert.equal(GATE_EARTH_RADIUS_M, num(constants.GATE_EARTH_RADIUS_M));
});

for (const c of section('distance')) {
	test(`distance: ${String(c.name)}`, () => {
		const a = (c.a as unknown[]).map(num);
		const b = (c.b as unknown[]).map(num);
		close(raceDistanceM(a[0], a[1], b[0], b[1]), num(c.expectM), distTol, 'distance');
	});
}

for (const c of section('zone')) {
	test(`zone: ${String(c.name)}`, () => {
		assert.equal(raceInFinishZone(num(c.distanceM)), c.inZone);
	});
}

for (const c of section('coverage')) {
	test(`coverage: ${String(c.name)}`, () => {
		assert.equal(raceCoverageMet(num(c.coveredM), numOrNull(c, 'courseDistanceM')), c.met);
	});
}

for (const c of section('detector')) {
	test(`detector: ${String(c.name)}`, () => {
		const e = c.expect as Obj;
		const d = new RaceFinishDetector({ finishLat, finishLng, courseDistanceM: num(c.courseDistanceM) });
		let finalisedAt: number | null = null;
		let finish: RaceFinish | null = null;
		(c.fixes as Obj[]).forEach((f, i) => {
			const r = d.offer(northFix(f));
			if (r === null) return;
			assert.equal(finalisedAt, null, 'a detector finalises exactly once');
			finalisedAt = i;
			finish = r;
		});
		assert.equal(finalisedAt, req(e, 'finalisesAtFix'));
		const want = req(e, 'finish') as Obj | null;
		if (want === null) {
			assert.equal(finish, null);
		} else {
			const f = finish as RaceFinish | null;
			assert.ok(f !== null);
			assert.equal((f.atMs - t0) / 1000, want.atS);
			close(f.distanceToFinishM, num(want.distanceToFinishM), distTol, 'distanceToFinishM');
			assert.equal(f.coveredM, num(want.coveredM));
			assert.equal(f.detection, 'zone');
			assert.equal(d.result, f);
		}
		const candidateAtS = req(e, 'candidateAtS');
		assert.equal(d.candidate === null ? null : (d.candidate.atMs - t0) / 1000, candidateAtS);
		const settled = d.settle();
		const settleAtS = req(e, 'settleAtS');
		assert.equal(settled === null ? null : (settled.atMs - t0) / 1000, settleAtS);
		assert.equal(d.candidate, null, 'settle closes the approach');
		for (const f of (c.fixesAfterSettle as Obj[] | undefined) ?? []) {
			assert.equal(d.offer(northFix(f)), null);
			assert.equal(d.result, settled);
		}
	});
}

for (const c of section('startFlag')) {
	test(`startFlag: ${String(c.name)}`, () => {
		assert.equal(
			raceStartFlagged(
				t0 + num(c.gunMs),
				t0 + num(c.recordingStartedMs),
				numOrNull(c, 'firstFixFromStartM'),
			),
			c.flagged,
		);
	});
}

for (const c of section('clockOffset')) {
	test(`clockOffset: ${String(c.name)}`, () => {
		const o = new ServerClockOffset();
		for (const s of c.samples as Obj[]) {
			o.addSample(t0 + num(s.sentMs), t0 + num(s.receivedMs), t0 + num(s.serverMs));
		}
		const e = c.expect as Obj;
		assert.equal(o.known, e.known);
		close(o.offsetMs, num(e.offsetMs), offsetTol, 'offsetMs');
	});
}

test('toServer moves a device instant by the offset', () => {
	const o = new ServerClockOffset();
	o.addSample(t0, t0 + 400, t0 + 3200);
	assert.equal(o.toServer(t0), t0 + 3000);
});

for (const c of section('gunTime')) {
	test(`gunTime: ${String(c.name)}`, () => {
		assert.equal(raceGunTimeS(t0 + num(c.finishMs), t0 + num(c.gunMs), num(c.offsetMs)), req(c, 'gunTimeS'));
	});
}

for (const c of section('chipTime')) {
	test(`chipTime: ${String(c.name)}`, () => {
		assert.equal(raceChipTimeS(t0 + num(c.finishMs), t0 + num(c.startMs)), req(c, 'chipTimeS'));
	});
}

for (const c of section('stopOutcome')) {
	test(`stopOutcome: ${String(c.name)}`, () => {
		const cand = req(c, 'candidate') as Obj | null;
		const o = raceStopOutcome(
			cand === null
				? null
				: {
						atMs: t0 + num(cand.atMs),
						distanceToFinishM: num(cand.distanceToFinishM),
						coveredM: num(cand.coveredM),
						detection: 'zone',
						start: null,
						gapped: false,
					},
			num(c.coveredM),
			numOrNull(c, 'courseDistanceM'),
			t0 + num(c.nowMs),
			req(c, 'lapsMet') as boolean | null,
		);
		const e = c.expect as Obj;
		assert.equal(o.finisherStatus, e.finisherStatus);
		assert.equal(o.method, req(e, 'method'));
		const at = numOrNull(e, 'finishAtMs');
		assert.equal(o.finishAtMs, at === null ? null : t0 + at);
	});
}

for (const c of section('resultTiming')) {
	test(`resultTiming: ${String(c.name)}`, () => {
		const outcome = c.outcome as Obj;
		const at = numOrNull(outcome, 'finishAtMs');
		const gun = numOrNull(c, 'gunMs');
		const started = numOrNull(c, 'recordingStartedMs');
		const start = numOrNull(c, 'startMs');
		const t = raceResultTiming({
			outcome: {
				finisherStatus: outcome.finisherStatus as 'finished' | 'dnf',
				method: req(outcome, 'method') as RaceFinishMethod | null,
				finishAtMs: at === null ? null : t0 + at,
			},
			gunAtMs: gun === null ? null : t0 + gun,
			clockOffsetMs: num(c.offsetMs),
			recordingStartedAtMs: started === null ? null : t0 + started,
			startAtMs: start === null ? null : t0 + start,
			elapsedS: num(c.elapsedS),
		});
		const e = c.expect as Obj;
		assert.equal(t.durationS, e.durationS);
		assert.equal(t.gunTimeS, req(e, 'gunTimeS'));
		assert.equal(t.chipTimeS, req(e, 'chipTimeS'));
	});
}

for (const c of section('lines')) {
	test(`lines: ${String(c.name)}`, () => {
		const e = c.expect as Obj;
		const goS = numOrNull(c, 'goS');
		const goAfter = numOrNull(c, 'goSetAfterFix');
		const d = new RaceFinishDetector({
			finishLat,
			finishLng,
			courseDistanceM: num(c.courseDistanceM),
			startGate: gateOf(req(c, 'startGate')),
			finishGate: gateOf(req(c, 'finishGate')),
			mode: c.mode === 'selfTimed' ? 'selfTimed' : 'gun',
			goAtMs: goS !== null && goAfter === null ? t0 + goS * 1000 : null,
			lapCount: numOrNull(c, 'lapCount'),
		});
		let finalisedAt: number | null = null;
		let finish: RaceFinish | null = null;
		(c.fixes as Obj[]).forEach((f, i) => {
			let r = d.offer(planeFix(f));
			if (goAfter === i && goS !== null) r ??= d.setGo(t0 + goS * 1000);
			if (r === null || finalisedAt !== null) return;
			finalisedAt = i;
			finish = r;
		});
		assert.equal(finalisedAt, req(e, 'finalisesAtFix'));
		assertFinish(finish, req(e, 'finish'), 'finish');
		assertStart(d.start, req(e, 'start'), 'start');
		const fixes = c.fixes as Obj[];
		assert.equal(d.lapsMet(num(fixes[fixes.length - 1].coveredM)), req(e, 'lapsMet'), 'lapsMet');
		const candidateAtS = req(e, 'candidateAtS');
		assert.equal(d.candidate === null ? null : (d.candidate.atMs - t0) / 1000, candidateAtS);

		const settled = d.settle();
		assertFinish(settled, req(e, 'settle'), 'settle');

		const timing = req(e, 'timing') as Obj | null;
		if (settled === null) {
			assert.equal(timing, null);
			return;
		}
		assert.ok(timing !== null);
		const pressS = numOrNull(c, 'pressS');
		const t = raceResultTiming({
			outcome: { finisherStatus: 'finished', method: 'auto', finishAtMs: settled.atMs },
			gunAtMs: goS === null ? null : t0 + goS * 1000,
			recordingStartedAtMs: pressS === null ? null : t0 + pressS * 1000,
			startAtMs: settled.start?.atMs ?? null,
			elapsedS: 0,
		});
		assert.equal(t.gunTimeS, req(timing, 'gunTimeS'));
		assert.equal(t.chipTimeS, req(timing, 'chipTimeS'));
		assert.equal(t.durationS, timing.durationS);
	});
}

test('an unusable line is no line', () => {
	const ok: Gate = { lat: 51.5, lng: -0.1, bearingDeg: 0, halfWidthM: 15 };
	assert.equal(raceLineUsable(ok), true);
	assert.equal(raceLineUsable(null), false);
	assert.equal(raceLineUsable({ ...ok, halfWidthM: 0 }), false);
	assert.equal(raceLineUsable({ ...ok, bearingDeg: NaN }), false);
});

test('GO is fixed once set', () => {
	const d = new RaceFinishDetector({
		finishLat,
		finishLng,
		courseDistanceM: 1000,
		startGate: { lat: finishLat, lng: finishLng, bearingDeg: 0, halfWidthM: 15 },
		goAtMs: t0,
	});
	assert.equal(d.setGo(t0 + 100_000), null);
	d.offer({ lat: finishLat + 10 / gateK, lng: finishLng, atMs: t0 + 1000, coveredM: 0 });
	assert.equal(d.start?.atMs, t0, 'past the line at the first GO');
});

test('a fix with a non-finite time is ignored once lines are in play', () => {
	const d = new RaceFinishDetector({
		finishLat,
		finishLng,
		courseDistanceM: 1000,
		finishGate: { lat: finishLat, lng: finishLng, bearingDeg: 0, halfWidthM: 15 },
	});
	assert.equal(d.offer({ lat: finishLat - 20 / gateK, lng: finishLng, atMs: NaN, coveredM: 990 }), null);
	assert.equal(d.candidate, null);
});

test('a fix with a non-finite time never becomes a v1 finish', () => {
	const d = new RaceFinishDetector({ finishLat, finishLng, courseDistanceM: 1000 });
	assert.equal(d.offer({ lat: finishLat, lng: finishLng, atMs: NaN, coveredM: 995 }), null);
	assert.equal(d.candidate, null);
	assert.equal(d.settle(), null);
});

test('a non-finite instant gives no gun or chip time', () => {
	assert.equal(raceGunTimeS(NaN, t0), null);
	assert.equal(raceChipTimeS(t0, NaN), null);
	const t = raceResultTiming({
		outcome: { finisherStatus: 'finished', method: 'auto', finishAtMs: NaN },
		gunAtMs: t0,
		recordingStartedAtMs: t0,
		elapsedS: 42,
	});
	assert.deepEqual(t, { durationS: 42, gunTimeS: null, chipTimeS: null });
});
