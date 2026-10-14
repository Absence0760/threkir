import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gradePhases, parsePacingStrategy, type PhaseReview } from './race_phases';
import type { TrackPoint } from '../types';

// Replays fixtures/race_phase_vectors.json, the `gradePhases` vectors shared
// with the Dart twin (apps/mobile_android/test/race_phase_vectors_test.dart).
// This file is also the generator:
//
//   RACE_PHASE_VECTORS_WRITE=1 npx tsx --test src/lib/runs/race_phase_vectors.test.ts
//
// builds each case's track from its hand-written `spec`, refuses to write when
// the computed verdict is not the hand-written `expect_verdict`, and rewrites
// `track` + `expected`. Never hand-edit those two.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const FIXTURE = join(REPO, 'fixtures', 'race_phase_vectors.json');
const T0_MS = Date.UTC(2026, 3, 12, 7, 0, 0);
const M_PER_DEG_LAT = 111_320;

type Leg = { m: number; pace: number } | { pause_s: number };
interface Spec {
	step_m: number;
	timed: boolean;
	legs: Leg[];
}
type Point = [number, number, number | null];
interface Case {
	name: string;
	strategy: unknown;
	spec: Spec | null;
	expect_verdict: string;
	track?: Point[] | null;
	expected?: PhaseReview;
}
interface ParseCase {
	name: string;
	raw: unknown;
	expected: unknown;
}
interface Fixture {
	_about: string;
	parse_cases: ParseCase[];
	cases: Case[];
}

function build(spec: Spec): Point[] {
	let cumM = 0;
	let tMs = T0_MS;
	const out: Point[] = [[40, -105, spec.timed ? tMs : null]];
	for (const leg of spec.legs) {
		if ('pause_s' in leg) {
			tMs += leg.pause_s * 1000;
			out.push([40 + cumM / M_PER_DEG_LAT, -105, spec.timed ? tMs : null]);
			continue;
		}
		const n = Math.max(1, Math.round(leg.m / spec.step_m));
		const stepM = leg.m / n;
		for (let i = 0; i < n; i++) {
			cumM += stepM;
			tMs += Math.round(stepM * leg.pace);
			out.push([40 + cumM / M_PER_DEG_LAT, -105, spec.timed ? tMs : null]);
		}
	}
	return out;
}

function toTrack(points: Point[] | null | undefined): TrackPoint[] | null {
	if (points == null) return null;
	return points.map(([lat, lng, ms]) =>
		ms == null ? { lat, lng } : { lat, lng, ts: new Date(ms).toISOString() }
	);
}

function review(c: Case): PhaseReview {
	const strategy = parsePacingStrategy(c.strategy);
	assert.ok(strategy, `${c.name}: the fixture strategy must parse`);
	return gradePhases(toTrack(c.track), strategy);
}

function assertClose(got: unknown, want: unknown, path: string) {
	if (typeof want === 'number' && typeof got === 'number') {
		assert.ok(Math.abs(got - want) <= 1e-6 * Math.max(1, Math.abs(want)), `${path}: ${got} != ${want}`);
		return;
	}
	if (want !== null && typeof want === 'object') {
		assert.ok(got !== null && typeof got === 'object', `${path}: expected an object`);
		const w = want as Record<string, unknown>;
		const g = got as Record<string, unknown>;
		assert.deepEqual(Object.keys(g).sort(), Object.keys(w).sort(), `${path}: keys`);
		for (const k of Object.keys(w)) assertClose(g[k], w[k], `${path}.${k}`);
		return;
	}
	assert.equal(got, want, path);
}

const fixture = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

if (process.env.RACE_PHASE_VECTORS_WRITE === '1') {
	for (const c of fixture.cases) {
		c.track = c.spec == null ? null : build(c.spec);
		const r = review(c);
		assert.equal(r.verdict, c.expect_verdict, `${c.name}: computed verdict`);
		c.expected = r;
	}
	const lines = [
		'{',
		` "_about": ${JSON.stringify(fixture._about)},`,
		` "parse_cases": [`,
		fixture.parse_cases.map((p) => `  ${JSON.stringify(p)}`).join(',\n'),
		' ],',
		' "cases": [',
		fixture.cases
			.map((c) =>
				[
					'  {',
					`   "name": ${JSON.stringify(c.name)},`,
					`   "strategy": ${JSON.stringify(c.strategy)},`,
					`   "spec": ${JSON.stringify(c.spec)},`,
					`   "expect_verdict": ${JSON.stringify(c.expect_verdict)},`,
					`   "expected": ${JSON.stringify(c.expected)},`,
					`   "track": ${JSON.stringify(c.track)}`,
					'  }',
				].join('\n')
			)
			.join(',\n'),
		' ]',
		'}',
		'',
	];
	writeFileSync(FIXTURE, lines.join('\n'));
}

test('race phase vectors: parsePacingStrategy reads every fixture bag as recorded', () => {
	assert.ok(fixture.parse_cases.length >= 5);
	for (const p of fixture.parse_cases) {
		assert.deepEqual(parsePacingStrategy(p.raw), p.expected, p.name);
	}
});

test('race phase vectors: gradePhases reproduces every fixture review', () => {
	assert.ok(fixture.cases.length >= 8);
	for (const c of fixture.cases) {
		assert.ok(c.expected, `${c.name}: fixture carries no expected review — regenerate`);
		const r = review(c);
		assert.equal(r.verdict, c.expect_verdict, `${c.name}: verdict`);
		assertClose(r, c.expected, c.name);
	}
});

test('race phase vectors: every verdict and ungraded reason is exercised', () => {
	const verdicts = new Set(fixture.cases.map((c) => c.expected?.verdict));
	for (const v of [
		'on_plan',
		'went_out_too_fast',
		'faded',
		'negative_split',
		'faster_than_plan',
		'slower_than_plan',
		'ungraded',
	]) {
		assert.ok(verdicts.has(v as PhaseReview['verdict']), `no case reaches ${v}`);
	}
	const reasons = new Set(fixture.cases.map((c) => c.expected?.ungradedReason));
	assert.ok(reasons.has('no_track') && reasons.has('no_goal'));
});
