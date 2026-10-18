// The heart-rate prescription gate, and whether the surfaces it gates are
// actually behind it. Invocation:
//   npx tsx --test src/lib/training/hr_prescription_gate.test.ts
//
// `hrPrescriptionEnabled` reads the server's gate through Supabase, so the
// module is pinned from its source here. What this pins is the half the CISO /
// counsel review rests on (decisions § 2092, § 2108, § 150): with the server
// gate shut, no bpm target, medication setting or HR-drift flag renders, the
// workout editor never writes a bpm target, and no build flag of the client's
// own can turn any of it on.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { insideIfBranch } from '../core/svelte_if_guard';

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

const SURFACES = [
	{ path: 'src/lib/components/WorkoutEditor.svelte', affordances: ['data-testid="workout-hr-target"'] },
	{ path: 'src/routes/plans/[id]/workouts/[wid]/+page.svelte', affordances: ['data-testid="workout-hr-target"'] },
	{ path: 'src/routes/coaching/athletes/[id]/+page.svelte', affordances: ['data-testid="coach-workout-hr"'] },
	{ path: 'src/routes/coaching/+page.svelte', affordances: ['data-testid="roster-hr-drift-flag"'] },
	{ path: 'src/routes/settings/training/+page.svelte', affordances: ['data-testid="hr-medication"'] },
] as const;

test('the gate is the server row, read fail-closed, and no client build flag exists', () => {
	const source = read('src/lib/training/hr_prescription_gate.ts');
	assert.match(source, /rpc\('hr_prescription_enabled', undefined, \{ get: true \}\)/);
	assert.match(source, /return data === true;/, 'only a literal true opens the gate');
	assert.equal((source.match(/return false;/g) ?? []).length, 2, 'an error and a throw both read off');
	assert.doesNotMatch(read('src/env.ts'), /HR_PRESCRIPTION/);
	assert.doesNotMatch(read('.env.example'), /HR_PRESCRIPTION/);
	assert.doesNotMatch(read('.env.development'), /HR_PRESCRIPTION/);
});

for (const spec of SURFACES) {
	test(`${spec.path}: every heart-rate affordance renders only under the gate`, () => {
		const page = read(spec.path);
		assert.match(page, /let hrPrescription = \$state\(false\);/, 'the surface must start with the gate shut');
		assert.match(page, /hrPrescriptionEnabled\(\)/, 'the surface must ask the server gate');
		const template = page.slice(page.indexOf('</script>'));
		const guarded = insideIfBranch(template, 'hrPrescription');
		for (const needle of spec.affordances) {
			let at = template.indexOf(needle);
			assert.notEqual(at, -1, `${needle} is no longer rendered — the guard is stale`);
			while (at !== -1) {
				assert.ok(guarded(at), `${needle} at offset ${at} renders with the server gate shut`);
				at = template.indexOf(needle, at + needle.length);
			}
		}
	});
}

test('the workout editor writes a bpm target only under the gate, and clears it on a rest day', () => {
	const src = read('src/lib/components/WorkoutEditor.svelte');
	assert.match(src, /\.\.\.\(hrPrescription && hr\.ok\s*\?\s*\{ target_hr_min_bpm: hr\.min, target_hr_max_bpm: hr\.max \}/);
	const writes = src.match(/target_hr_(min|max)_bpm:/g) ?? [];
	assert.equal(writes.length, 4, 'one gated write pair and one rest-day clear pair, nothing else');
});

test('the training settings read the consent stamp only under the gate', () => {
	const src = read('src/routes/settings/training/+page.svelte');
	const script = src.slice(0, src.indexOf('</script>'));
	const gateAt = script.indexOf('if (hrPrescription) {');
	assert.ok(gateAt > 0, 'the profile read must sit behind `if (hrPrescription)`');
	assert.equal(script.split("rpc('get_my_profile'").length - 1, 1);
	assert.ok(script.indexOf("rpc('get_my_profile'") > gateAt);
});

test('the dashboard marks the load low-confidence only under the gate', () => {
	assert.match(
		read('src/routes/dashboard/+page.svelte'),
		/hrPrescription && isTrimpLowConfidence\(trainingLoadHasHr, hrMedicationAffected\)/
	);
});
