import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

/**
 * How far past a sleep the scan looks for the read it was guarding. Both sites
 * this replaced put the read on the very next statement.
 */
const WINDOW_LINES = 4;

/** 1-based lines of each sleep followed within the window by a computed-style read. */
function sleepGuardedReads(source: string): number[] {
	const lines = stripComments(source).split('\n');
	return lines.flatMap((line, i) => {
		if (!/\bwaitForTimeout\s*\(/.test(line)) return [];
		const after = lines.slice(i + 1, i + 1 + WINDOW_LINES).join('\n');
		return /\bgetComputedStyle\s*\(/.test(after) ? [i + 1] : [];
	});
}

function sourceFiles(dir: string): string[] {
	return readdirSync(dir).flatMap((name) => {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) return sourceFiles(path);
		return /\.(?:ts|mjs|js)$/.test(name) && !name.endsWith('.test.ts') ? [path] : [];
	});
}

/**
 * A fixed sleep in front of a computed-style read is a guess at how long a CSS
 * transition takes, and a loaded runner makes the guess wrong: that is how the
 * route builder's hover-fade read raced its 180ms transition behind a 250ms
 * sleep, and the same unguarded shape is how the public header's glass read
 * 0.176 instead of 0.8 (run 37709672474). `settleTransitions` waits on the
 * transitions themselves.
 */
test('no spec sleeps in front of a computed-style read instead of settling transitions', () => {
	const offenders = sourceFiles(E2E_ROOT).flatMap((file) =>
		sleepGuardedReads(readFileSync(file, 'utf8')).map(
			(line) => `${relative(E2E_ROOT, file)}:${line}`
		)
	);
	assert.deepEqual(
		offenders,
		[],
		`A sleep guards a getComputedStyle read — use settleTransitions from fixtures/transitions.ts:\n  ${offenders.join('\n  ')}`
	);
});

test('the scan still sees the shape it exists to catch', () => {
	const sample = [
		"await page.locator('.map-area').hover();",
		'await page.waitForTimeout(250);',
		'const hovered = await card.evaluate((el) => getComputedStyle(el).opacity);'
	].join('\n');
	assert.deepEqual(sleepGuardedReads(sample), [2]);
	assert.deepEqual(
		sleepGuardedReads(sample.replace('waitForTimeout(250)', "locator('x').click()")),
		[]
	);
});
