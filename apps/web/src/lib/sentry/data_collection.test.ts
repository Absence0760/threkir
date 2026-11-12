import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { SENTRY_DATA_COLLECTION } from './data_collection';

const SRC = join(import.meta.dirname, '..', '..');

function sources(dir: string): string[] {
	return readdirSync(dir).flatMap((name) => {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) return sources(path);
		return /\.(ts|svelte)$/.test(name) && !name.endsWith('.test.ts') ? [path] : [];
	});
}

test('SENTRY_DATA_COLLECTION turns every collection category off', () => {
	const c = SENTRY_DATA_COLLECTION;
	assert.equal(c.userInfo, false);
	assert.equal(c.cookies, false);
	assert.equal(c.httpHeaders, false);
	assert.deepEqual(c.httpBodies, []);
	assert.equal(c.urlQueryParams, false);
	assert.deepEqual(c.genAI, { inputs: false, outputs: false });
	assert.equal(c.databaseQueryData, false);
	assert.equal(c.queues, false);
	assert.deepEqual(c.graphQL, { document: false, variables: false });
	assert.equal(c.stackFrameVariables, false);
});

// Sentry 11's defaults collect all of the above, so an init that omits the
// option ships it silently — there is no type error to catch the omission.
test('every Sentry.init under src passes SENTRY_DATA_COLLECTION', () => {
	const inits = sources(SRC).filter((p) => /Sentry\.init\(\s*\{/.test(readFileSync(p, 'utf8')));
	assert.ok(inits.length >= 3, `expected the three known init sites, found ${inits.length}`);
	for (const path of inits) {
		const body = readFileSync(path, 'utf8');
		const calls = body.split(/Sentry\.init\(\s*\{/).slice(1);
		for (const call of calls) {
			assert.match(
				call.slice(0, call.indexOf('});')),
				/dataCollection:\s*SENTRY_DATA_COLLECTION\b/,
				`${relative(SRC, path)} calls Sentry.init without dataCollection: SENTRY_DATA_COLLECTION`,
			);
		}
		assert.doesNotMatch(body, /sendDefaultPii\s*:/, `${relative(SRC, path)} still sets sendDefaultPii, which Sentry 11 removed`);
	}
});
