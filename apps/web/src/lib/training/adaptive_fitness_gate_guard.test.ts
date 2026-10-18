// Source-level guards on the plan-generator-v2 P2 fitness direction gate
// (decisions §144, §150). P2 reads health-derived load (CTL/ATL/TSB) into a
// training prescription, and its sign-off rests on two properties that a
// future edit could quietly break:
//
//   1. the gate is FAIL-CLOSED — unset / empty / "false" reads as off, and with
//      it off the engine is passed no fitness at all (exactly shipped P1); and
//   2. the snapshot is NEVER logged or persisted — it flows into one in-memory
//      decision as a call argument and dies there.
//
// The engine half is pinned in plan_adaptive_replan.test.ts; this pins the web
// call site. Its Dart mirror is adaptive_fitness_gate_guard_test.dart.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { stripComments } from '../core/strip_comments';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

/// The body of `adaptiveFitnessInput()` on the plan-detail page.
function fitnessInputBody(page: string): string {
	const start = page.indexOf('function adaptiveFitnessInput(');
	assert.ok(start >= 0, 'could not locate adaptiveFitnessInput — rename?');
	const end = page.indexOf('function proposeAdaptiveReplan(', start);
	assert.ok(end > start, 'could not locate proposeAdaptiveReplan after it');
	return page.slice(start, end);
}

test('the P2 fitness gate is fail-closed and reads PUBLIC_ADAPTIVE_FITNESS_GATE', () => {
	const flag = read('src/lib/training/adaptive_fitness_flag.ts');
	assert.match(flag, /PUBLIC_ADAPTIVE_FITNESS_GATE/,
		'the flag must read PUBLIC_ADAPTIVE_FITNESS_GATE');
	assert.match(flag, /from\s+'\$app\/env\/public'/,
		'the flag must read the deploy-time public env, not a build-time constant');
	// `$app/env/public` serves both kinds of variable; whether one is baked in
	// at build is declared in src/env.ts, so that is where "deploy-time" lives.
	const envDecl = read('src/env.ts');
	assert.match(envDecl, /\bPUBLIC_ADAPTIVE_FITNESS_GATE:\s*\{\s*public:\s*true/, 'PUBLIC_ADAPTIVE_FITNESS_GATE must be declared public in src/env.ts');
	assert.doesNotMatch(
		envDecl,
		/\bPUBLIC_ADAPTIVE_FITNESS_GATE:[^}]*\bstatic:\s*true/,
		'PUBLIC_ADAPTIVE_FITNESS_GATE must not be declared `static: true` in src/env.ts — that bakes it in at build',
	);
	// Delegating to the parity-pair parser is what keeps web and mobile from
	// accepting different values for the same documented flag.
	assert.match(flag, /adaptiveFitnessGateEnabled\(/,
		'the flag must delegate to the shared adaptiveFitnessGateEnabled parser');
});

test('the plan page passes no fitness at all while the gate is off', () => {
	const body = fitnessInputBody(read('src/routes/plans/[id]/+page.svelte'));
	assert.match(body, /if\s*\(!isAdaptiveFitnessGateEnabled\(\)\)\s*return null;/,
		'adaptiveFitnessInput must return null before touching the load series when the gate is off');
	// The early return must be the FIRST statement, so a gated-off build never
	// even computes the series.
	const guardIdx = body.indexOf('isAdaptiveFitnessGateEnabled()');
	const seriesIdx = body.indexOf('computeTrainingLoadSeries');
	assert.ok(seriesIdx > guardIdx,
		'the load series must only be computed after the gate check');
});

test('the fitness snapshot is never stored, logged, or persisted by the plan page', () => {
	const page = read('src/routes/plans/[id]/+page.svelte');

	// It exists only as a call argument — never bound to a variable or to
	// component state, so there is nothing for a later write to pick up.
	const calls = (page.match(/(?<!function\s)adaptiveFitnessInput\(\)/g) ?? []).length;
	assert.equal(calls, 1, 'adaptiveFitnessInput() must be called exactly once');
	assert.match(page, /fitness:\s*adaptiveFitnessInput\(\)/,
		'the snapshot must be passed straight into adaptiveReplanRemaining');
	assert.equal(/(?:let|const|var)\s+\w+\s*=\s*adaptiveFitnessInput\(\)/.test(page), false,
		'the snapshot must not be bound to a variable');
	assert.equal(/=\s*adaptiveFitnessInput\(\)/.test(page), false,
		'the snapshot must not be assigned to state');

	assert.equal(/console\s*\./.test(fitnessInputBody(page)), false,
		'the snapshot must never be logged');

	// The only thing an applied re-plan writes is the workout distance the
	// shipped engine proposed — no load column, no new field.
	const applyStart = page.indexOf('async function applyReplan(');
	assert.ok(applyStart >= 0, 'could not locate applyReplan — rename?');
	const applyBody = page.slice(applyStart, page.indexOf('/// Human label for a proposed change row', applyStart));
	assert.ok(applyBody.length > 0, 'could not slice applyReplan');
	assert.match(applyBody, /\(\{\s*id:\s*c\.workoutId,\s*target_distance_m:\s*c\.toMetres\s*\}\)/,
		'applying a re-plan must write only target_distance_m');
	assert.equal(/updatePlanWorkout\(/.test(applyBody), false,
		'a re-plan is applied in one apply_workout_adjustments call, not per workout');
	assert.equal(/tsb|atl|ctl/.test(applyBody), false,
		'the apply path must not carry a load value');
});

test('the plan page is the only caller that can pass fitness, so no second call site escapes these guards', () => {
	// Every property above is pinned on ONE call site. A second caller (a
	// dashboard card, the coach, a notification) would pass whatever it liked
	// and none of this would see it (decisions § 1977). Home's plan card is the
	// one admitted second caller, and only because the next test pins that it
	// passes no fitness at all (decisions § 2125).
	const callers: string[] = [];
	const walk = (dir: string): void => {
		for (const e of readdirSync(resolve(dir), { withFileTypes: true })) {
			const p = `${dir}/${e.name}`;
			if (e.isDirectory()) {
				if (e.name !== 'node_modules') walk(p);
			} else if (/\.(ts|svelte)$/.test(e.name) && !/\.test\.ts$/.test(e.name)) {
				if (/\badaptiveReplanRemaining\(/.test(read(p)) && !p.endsWith('training/plan_adaptive_replan.ts')) {
					callers.push(p);
				}
			}
		}
	};
	walk('src');
	assert.deepEqual(callers.sort(), ['src/lib/training/plan_nudges.ts', 'src/routes/plans/[id]/+page.svelte']);
});

test("Home's plan card calls the engine with no fitness and holds no load value", () => {
	const code = stripComments(read('src/lib/training/plan_nudges.ts'));
	const calls = code.match(/\badaptiveReplanRemaining\(([^)]*)\)/g) ?? [];
	assert.equal(calls.length, 1, 'plan_nudges.ts must call adaptiveReplanRemaining exactly once');
	assert.equal(calls[0], 'adaptiveReplanRemaining({ weeks, today: input.today })',
		'the Home card must pass only the weeks and today, never a fitness snapshot');
	assert.equal(/\b(fitness|tsb|atl|ctl|AdaptiveFitness)\b/i.test(code), false,
		'a load value or fitness input appears in plan_nudges.ts');
});

test('the plan page reads the gate only through the flag module and holds no load value', () => {
	const page = read('src/routes/plans/[id]/+page.svelte');
	assert.equal(page.includes('PUBLIC_ADAPTIVE_FITNESS_GATE'), false,
		'the page must call isAdaptiveFitnessGateEnabled(), not re-read the env key');
	// tsb / atl / ctl may appear only inside adaptiveFitnessInput(), where the
	// snapshot is built and returned; anywhere else is a handle a write could reach.
	const outside = page.replace(fitnessInputBody(page), '');
	assert.equal(/\b(tsb|atl|ctl)\b/.test(outside), false,
		'a load value appears on the plan page outside adaptiveFitnessInput()');
});

test('the comeback ramp is reached only through the gate (decisions § 2090)', () => {
	const callers: string[] = [];
	const walk = (dir: string): void => {
		for (const e of readdirSync(resolve(dir), { withFileTypes: true })) {
			const p = `${dir}/${e.name}`;
			if (e.isDirectory()) {
				if (e.name !== 'node_modules') walk(p);
			} else if (/\.(ts|svelte)$/.test(e.name) && !/\.test\.ts$/.test(e.name)) {
				if (/\banchorToActualVolume\(/.test(stripComments(read(p))) && !p.endsWith('training/plan_volume_anchor.ts')) {
					callers.push(p);
				}
			}
		}
	};
	walk('src');
	assert.deepEqual(callers.sort(), ['src/lib/training/plan_nudges.ts', 'src/routes/plans/[id]/+page.svelte']);

	const page = read('src/routes/plans/[id]/+page.svelte');
	assert.equal((page.match(/\banchorToActualVolume\(/g) ?? []).length, 1,
		'the plan page must call anchorToActualVolume only inside volumeAnchor()');
	assert.match(page,
		/function volumeAnchor\([^)]*\)[^{]*\{\s*if \(!isAdaptiveFitnessGateEnabled\(\)\) return null;\s*return anchorToActualVolume\(/,
		'volumeAnchor() must return null before anchoring while the gate is off');

	const nudges = stripComments(read('src/lib/training/plan_nudges.ts'));
	assert.match(nudges, /input\.anchorVolume === true \? anchorToActualVolume\(\{ weeks \}\) : null/,
		'planNudge must anchor only when the caller passes anchorVolume: true');
	const card = read('src/lib/components/PlanNudgeCard.svelte');
	assert.match(card, /anchorVolume:\s*isAdaptiveFitnessGateEnabled\(\)/,
		'Home passes the gate itself as anchorVolume');
});
