// The weight-based fluid gate, and whether the surfaces it gates are actually
// behind it. Invocation:
//   npx tsx --test src/lib/nutrition/weight_fluid_flag.test.ts
//
// `weightFluidEnabled` reads `$app/env/public`, so the module cannot be
// imported here; its parse is pinned in `core/env_flag.test.ts`. What this
// pins is the half the CISO / counsel review rests on (decisions § 1976,
// § 150): with the flag off, neither page READS a body weight, the toggle
// never renders, and a `?bw=1` link cannot switch the rate on.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { insideIfBranch } from '../core/svelte_if_guard';

const FLAG = 'src/lib/nutrition/weight_fluid_flag.ts';
const PAGES = {
	fuel: {
		path: 'src/routes/nutrition/fuel/+page.svelte',
		useWeight: /useWeight:\s*weightFluid\s*&&\s*handoff\.useWeight/,
		affordances: ['data-testid="fuel-weight"', 'data-testid="fuel-weight-hint"', "m('fuelPlan.weightToggle')"],
	},
	roadbook: {
		path: 'src/routes/routes/[id]/roadbook/+page.svelte',
		useWeight: /let weightOn = \$derived\(weightFluid\s*&&\s*params\.get\('bw'\) === '1'\)/,
		affordances: ['data-testid="roadbook-fuel-weight"', 'data-testid="roadbook-weight-hint"', "m('fuelPlan.weightToggle')"],
	},
} as const;

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

test('the gate is fail-closed and routed through the canonical parse', () => {
	const source = read(FLAG);
	assert.match(source, /isTruthyFlagValue\(PUBLIC_WEIGHT_FLUID_ENABLED\)/);
	assert.doesNotMatch(source, /\?\?\s*(true|'1'|'true')/, 'the gate must not default to on');
	const envDecl = read('src/env.ts');
	assert.match(envDecl, /\bPUBLIC_WEIGHT_FLUID_ENABLED:\s*\{\s*public:\s*true,\s*schema:\s*optional\s*\}/);
});

test('the branch scanner sees a nested guard and refuses an unguarded sibling or else branch', () => {
	assert.equal(insideIfBranch('{#if a && weightFluid}{#if b}<X/>{/if}{/if}', 'weightFluid')(30), true);
	assert.equal(insideIfBranch('{#if weightFluid}<A/>{/if}<B/>', 'weightFluid')(30), false);
	assert.equal(insideIfBranch('{#if weightFluid}<A/>{:else}<B/>{/if}', 'weightFluid')(33), false);
	assert.equal(insideIfBranch('{#if other}<A/>{/if}', 'weightFluid')(13), false);
});

for (const [name, spec] of Object.entries(PAGES)) {
	test(`${name}: no body weight or consent stamp is read while the gate is off`, () => {
		const page = read(spec.path);
		assert.match(page, /const weightFluid = weightFluidEnabled\(\);/, 'the page must resolve the gate once');
		const script = page.slice(0, page.indexOf('</script>'));
		const gateAt = script.indexOf('if (weightFluid) {');
		assert.ok(gateAt > 0, 'the weight read must sit behind `if (weightFluid)`');
		const gated = script.slice(gateAt, script.indexOf('\n\t\t\t}', gateAt));
		for (const read of ['fetchLatestWeightKg()', "rpc('get_my_profile'", 'healthUseWeightKg(']) {
			const all = script.split(read).length - 1;
			assert.equal(all, 1, `${read} must be called exactly once`);
			assert.ok(gated.includes(read), `${read} must only run under the gate`);
		}
	});

	test(`${name}: a ?bw=1 link cannot turn the weight rate on while the gate is off`, () => {
		assert.match(read(spec.path), spec.useWeight);
	});

	test(`${name}: every weight affordance renders only under the gate`, () => {
		const page = read(spec.path);
		const template = page.slice(page.indexOf('</script>'));
		const guarded = insideIfBranch(template, 'weightFluid');
		for (const needle of spec.affordances) {
			let at = template.indexOf(needle);
			assert.notEqual(at, -1, `${needle} is no longer rendered — the guard is stale`);
			while (at !== -1) {
				assert.ok(guarded(at), `${needle} at offset ${at} renders with PUBLIC_WEIGHT_FLUID_ENABLED off`);
				at = template.indexOf(needle, at + needle.length);
			}
		}
	});
}
