// Unit tests for scripts/check_adr_numbers.mjs.
//
// The pure parsers are exercised directly. The whole-tree `check()` is not
// re-run per case — it reads every tracked file — so the cases that need a
// tree build a small one and point the guard at it.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import { ADR_DOC, UNRESOLVED, check, references, sectionNumbers } from './check_adr_numbers.mjs';

/** A throwaway git repo holding `files`, since the guard reads `git ls-files`. */
/**
 * @param {Record<string, string>} files
 * @param {(dir: string) => {errors: string[], ok: string[]}} fn
 */
function withTree(files, fn) {
	const dir = mkdtempSync(join(tmpdir(), 'adr-numbers-'));
	try {
		execFileSync('git', ['init', '-q'], { cwd: dir });
		for (const [rel, body] of Object.entries(files)) {
			mkdirSync(join(dir, dirname(rel)), { recursive: true });
			writeFileSync(join(dir, rel), body);
		}
		execFileSync('git', ['add', '-A'], { cwd: dir });
		return fn(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

const DOC = (/** @type {number[]} */ ...entries) => entries.map((n) => `## ${n}. Entry ${n}\n\nProse.\n`).join('\n');

// --- rule 1: uniqueness ----------------------------------------------------

test('a duplicated section number fails, naming both lines', () => {
	// The real shape: two branches each wrote `## 1678.`, neither is
	// internally wrong, and the duplicate exists only in the merge.
	const { errors } = withTree({ [ADR_DOC]: DOC(1677, 1678, 1678), 'docs/o.md': 'see § 1677\n' }, (/** @type {string} */ d) => check(d, {}));
	const hit = errors.find((e) => e.includes('section 1678 is claimed by 2 entries'));
	assert.ok(hit, errors.join('\n'));
	assert.match(hit, /at lines \d+ and \d+/);
});

test('a clean sequence passes', () => {
	const { errors } = withTree({ [ADR_DOC]: DOC(1677, 1678, 1679), 'docs/o.md': 'see § 1678\n' }, (/** @type {string} */ d) => check(d, {}));
	assert.deepEqual(errors, []);
});

test('gaps and out-of-order numbers pass, because neither is a defect', () => {
	// 164 gaps and 17 inversions exist on `main`; failing them would mean
	// renumbering 1,500 entries to fix nothing a reader can see.
	const { errors } = withTree({ [ADR_DOC]: DOC(1, 900, 40, 1684), 'docs/o.md': 'see § 900\n' }, (/** @type {string} */ d) => check(d, {}));
	assert.deepEqual(errors, []);
});

// --- rule 2: references resolve --------------------------------------------

test('a reference to a section that does not exist fails, with its file and line', () => {
	const { errors } = withTree(
		{ [ADR_DOC]: DOC(10), 'docs/other.md': 'first\nsee § 11 for why\n' },
		(/** @type {string} */ d) => check(d, {}),
	);
	const hit = errors.find((e) => e.includes('`§ 11` names no section'));
	assert.ok(hit, errors.join('\n'));
	assert.ok(hit.startsWith('docs/other.md:2:'), hit);
});

test('both endpoints of a §§ A-B range are checked', () => {
	const { errors } = withTree(
		{ [ADR_DOC]: DOC(10, 11), 'docs/other.md': 'see §§ 10-12\n' },
		(/** @type {string} */ d) => check(d, {}),
	);
	assert.ok(
		errors.some((/** @type {string} */ e) => e.includes('`§ 12` names no section')),
		errors.join('\n'),
	);
});

test('a comma tail is not followed, so a trailing date is not read as a section', () => {
	// `§ 1254, 2026-09-18` is a section and a date. Following the comma
	// reported the YEAR as a missing section, which is how this rule was set.
	const { errors } = withTree(
		{ [ADR_DOC]: DOC(10), 'docs/other.md': 'recorded in § 10, 2026-09-18.\n' },
		(/** @type {string} */ d) => check(d, {}),
	);
	assert.deepEqual(errors, []);
});

test('§N with no space resolves the same as § N', () => {
	const { errors } = withTree({ [ADR_DOC]: DOC(10), 'docs/o.md': 'see §10\n' }, (/** @type {string} */ d) => check(d, {}));
	assert.deepEqual(errors, []);
});

// --- the UNRESOLVED register -----------------------------------------------

test('an UNRESOLVED number is tolerated where it is cited', () => {
	const { errors } = withTree(
		{ [ADR_DOC]: DOC(10), 'docs/o.md': 'see § 1810\n' },
		(/** @type {string} */ d) => check(d, { 1810: 'a reason long enough to be a reason, recorded rather than guessed at' }),
	);
	assert.deepEqual(errors, []);
});

test('an UNRESOLVED entry whose number now exists fails as stale', () => {
	const { errors } = withTree(
		{ [ADR_DOC]: DOC(10, 1810), 'docs/o.md': 'see § 1810\n' },
		(/** @type {string} */ d) => check(d, { 1810: 'a reason long enough to be a reason, recorded rather than guessed at' }),
	);
	assert.ok(
		errors.some((/** @type {string} */ e) => e.includes('Section 1810 now exists')),
		errors.join('\n'),
	);
});

test('an UNRESOLVED entry nothing cites any more fails as stale', () => {
	const { errors } = withTree({ [ADR_DOC]: DOC(10), 'docs/o.md': 'see § 10\n' }, (/** @type {string} */ d) =>
		check(d, { 1810: 'a reason long enough to be a reason, recorded rather than guessed at' }),
	);
	assert.ok(
		errors.some((/** @type {string} */ e) => e.includes('UNRESOLVED lists 1810')),
		errors.join('\n'),
	);
});

test('every UNRESOLVED entry states what the number was cited for', () => {
	for (const [number, reason] of Object.entries(UNRESOLVED)) {
		assert.ok(reason.length > 40, `${number}: reason is too short to be a reason`);
	}
});

// --- vacuity ---------------------------------------------------------------

test('a doc whose heading shape stopped parsing fails rather than passing', () => {
	const { errors } = withTree({ [ADR_DOC]: '# 1677 Entry\n\nProse.\n' }, (/** @type {string} */ d) => check(d, {}));
	assert.ok(
		errors.some((/** @type {string} */ e) => e.includes('Parsed no `## N.` heading')),
		errors.join('\n'),
	);
});

test('a tree with no § reference at all fails rather than passing', () => {
	const { errors } = withTree({ [ADR_DOC]: DOC(10) }, (/** @type {string} */ d) => check(d, {}));
	assert.ok(
		errors.some((/** @type {string} */ e) => e.includes('Parsed no `§ N` reference')),
		errors.join('\n'),
	);
});

// --- parsers ---------------------------------------------------------------

test('sectionNumbers reads the number and its line, and ignores deeper headings', () => {
	assert.deepEqual(sectionNumbers('## 7. A\n\n### 8. B\n\n## 9. C\n'), [
		{ number: 7, line: 1 },
		{ number: 9, line: 5 },
	]);
});

test('references does not treat a bare number as one', () => {
	assert.deepEqual(references('issue 1678 and § 24'), [{ number: 24, line: 1 }]);
});
