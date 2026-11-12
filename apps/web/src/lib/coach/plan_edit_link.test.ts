import { test } from 'node:test';
import assert from 'node:assert/strict';

import { planEditHandoff } from './plan_edit_link';
import { MAX_PLAN_EDIT_REQUEST_CHARS } from '../training/plan_edit/ops';

const ID = '0f8fad5b-d9cb-469f-a165-70867728950e';

test('reads the plan id and the decoded request from the adjust link', () => {
	const out = planEditHandoff(
		`Sure. [Adjust my plan](/plans/${ID}?adjust=make%20next%20week%20easier) shows the change before anything is saved.`,
	);
	assert.deepEqual(out, { planId: ID, request: 'make next week easier' });
});

test('takes the first adjust link and ignores other app links', () => {
	const out = planEditHandoff(
		`[Your plan](/plans/${ID}) and [Adjust my plan](/plans/${ID}?adjust=skip%20Friday) and ` +
			`[another](/plans/${ID.replace('0f8f', '1f8f')}?adjust=other)`,
	);
	assert.deepEqual(out, { planId: ID, request: 'skip Friday' });
});

test('refuses anything but a root-relative /plans/<uuid> path with a request', () => {
	for (const content of [
		'no link at all',
		`[x](/plans/not-a-uuid?adjust=easier)`,
		`[x](https://evil.example/plans/${ID}?adjust=easier)`,
		`[x](//evil.example/plans/${ID}?adjust=easier)`,
		`[x](/plans/${ID}/edit?adjust=easier)`,
		`[x](/plans/${ID}?adjust=%20%20)`,
		`[x](/plans/${ID})`,
		`[x](/runs/${ID}?adjust=easier)`,
	]) {
		assert.equal(planEditHandoff(content), null, content);
	}
});

test('caps the request at the length the endpoint accepts', () => {
	const long = 'a'.repeat(MAX_PLAN_EDIT_REQUEST_CHARS + 50);
	const out = planEditHandoff(`[Adjust my plan](/plans/${ID}?adjust=${long})`);
	assert.equal(out?.request.length, MAX_PLAN_EDIT_REQUEST_CHARS);
});

test('normalises the id to lower case', () => {
	assert.equal(planEditHandoff(`[x](/plans/${ID.toUpperCase()}?adjust=easier)`)?.planId, ID);
});
