// The heart-rate prescription gate, and whether the surfaces it gates are
// actually behind it. Invocation:
//   npx tsx --test src/lib/training/hr_prescription_flag.test.ts
//
// `hrPrescriptionEnabled` reads `$app/env/public`, so the module cannot be
// imported here; its parse is pinned in `core/env_flag.test.ts`. What this
// pins is the half the CISO / counsel review rests on (decisions § 2087,
// § 150): with the flag off, no bpm target, medication setting or HR-drift
// flag renders, and the workout editor never writes a bpm target.

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

test('the gate is fail-closed and routed through the canonical parse', () => {
	const source = read('src/lib/training/hr_prescription_flag.ts');
	assert.match(source, /isTruthyFlagValue\(PUBLIC_HR_PRESCRIPTION_ENABLED\)/);
	assert.doesNotMatch(source, /\?\?\s*(true|'1'|'true')/, 'the gate must not default to on');
	assert.match(read('src/env.ts'), /\bPUBLIC_HR_PRESCRIPTION_ENABLED:\s*\{\s*public:\s*true,\s*schema:\s*optional\s*\}/);
});

for (const spec of SURFACES) {
	test(`${spec.path}: every heart-rate affordance renders only under the gate`, () => {
		const page = read(spec.path);
		assert.match(page, /const hrPrescription = hrPrescriptionEnabled\(\);/, 'the surface must resolve the gate once');
		const template = page.slice(page.indexOf('</script>'));
		const guarded = insideIfBranch(template, 'hrPrescription');
		for (const needle of spec.affordances) {
			let at = template.indexOf(needle);
			assert.notEqual(at, -1, `${needle} is no longer rendered — the guard is stale`);
			while (at !== -1) {
				assert.ok(guarded(at), `${needle} at offset ${at} renders with PUBLIC_HR_PRESCRIPTION_ENABLED off`);
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
