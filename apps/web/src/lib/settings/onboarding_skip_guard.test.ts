// Source-level guard pinning the issue #921 fix. The wizard's per-step
// Skip and Continue used to be one action wearing two labels — `skipStep`
// was `next()` — so Skip carried the step's current value forward exactly
// as Continue did. Skip now means "leave this one unanswered" and clears
// the step's answer first, and the two steps that had nothing to unset no
// longer offer the button at all.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = readFileSync(resolve('src/routes/onboarding/+page.svelte'), 'utf-8');

const skipStep = (() => {
	const start = source.indexOf('\tfunction skipStep()');
	assert.notEqual(start, -1, 'skipStep missing from onboarding/+page.svelte');
	const end = source.indexOf('\n\t}', start);
	assert.notEqual(end, -1, 'skipStep body never closes');
	return source.slice(start, end);
})();

test('skipStep clears the goal step rather than carrying the selection forward', () => {
	assert.match(
		skipStep,
		/current === 'goal'[\s\S]*?primaryGoal = null/,
		'skipping the goal step must unset primaryGoal',
	);
});

test('skipStep clears every answer the about step collects', () => {
	const about = skipStep.slice(skipStep.indexOf("current === 'about'"));
	assert.notEqual(about, '', 'skipStep must handle the about step');
	for (const cleared of [
		/gender = ''/,
		/dateOfBirth = ''/,
		/bodyWeight = ''/,
		/healthDataConsent = false/,
	]) {
		assert.match(about, cleared, `skipping the about step must clear ${cleared}`);
	}
});

test('skipStep is not a bare next()', () => {
	// The whole regression: a skip that only advanced left the step's
	// default in place and persisted it as though it had been chosen.
	assert.doesNotMatch(
		skipStep,
		/skipStep\(\)\s*\{\s*next\(\);/,
		'skipStep must clear something before advancing',
	);
});

test('Skip is offered only on the steps that hold an unsettable answer', () => {
	const gate = source.match(/\{#if current === 'goal'[^}]*\}/);
	assert.notEqual(gate, null, 'the per-step Skip button must stay behind a step gate');
	assert.equal(
		gate![0],
		"{#if current === 'goal' || current === 'about'}",
		'units and privacy have no unset state, and the notifications step stores no answer — none may offer Skip',
	);
});

test('Skip stays enabled on an out-of-range body weight', () => {
	// Continue is disabled there (#677) because it would carry the value
	// forward; Skip discards it, so disabling both left the step with no
	// way on but editing the field.
	const button = source.slice(
		source.indexOf('class="skip-step"'),
		source.indexOf('</button>', source.indexOf('class="skip-step"')),
	);
	assert.match(button, /disabled=\{saving\}/, 'Skip must be gated on saving alone');
	assert.doesNotMatch(button, /weightOutOfRange/, 'Skip must not inherit the Continue guard');
});
