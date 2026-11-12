// Unit tests for scripts/check_conflict_markers.mjs.
//
// Run: `node --test scripts/check_conflict_markers.test.mjs`
//
// The markers are built with `repeat` rather than written out, so this file
// never trips the guard it tests. The tree-level cases plant files in a
// throwaway git repository under `os.tmpdir()`, never in a tree another guard
// walks.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { looksBinary, markersIn, run, scan } from './check_conflict_markers.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const OURS = '<'.repeat(7);
const BASE = '|'.repeat(7);
const SPLIT = '='.repeat(7);
const THEIRS = '>'.repeat(7);

test('all four markers git writes are found, with and without a label', () => {
	const text = [`${OURS} HEAD`, 'ours', `${BASE} 41a0ad7a7`, 'base', SPLIT, 'theirs', `${THEIRS} feature`].join('\n');
	assert.deepEqual(markersIn(text), [
		{ line: 1, marker: OURS },
		{ line: 3, marker: BASE },
		{ line: 5, marker: SPLIT },
		{ line: 7, marker: THEIRS },
	]);
});

test('the lone diff3 base marker is found on its own, which is the shape that reached main', () => {
	assert.deepEqual(markersIn(['prose', `${BASE} bd5e334c3`, '', '## 1614. Next'].join('\n')), [{ line: 2, marker: BASE }]);
});

test('CRLF line endings do not hide a bare marker', () => {
	assert.deepEqual(markersIn(`a\r\n${SPLIT}\r\nb`), [{ line: 2, marker: SPLIT }]);
});

test('look-alikes are not markers', () => {
	const text = [
		` ${OURS} indented`,
		`${OURS}< eight`,
		`${SPLIT}=`,
		`${THEIRS}x`,
		'| a | b |',
		'> quoted',
		'======',
		`text ${BASE} mid-line`,
	].join('\n');
	assert.deepEqual(markersIn(text), []);
});

test('a NUL in the first 8 KiB marks a file binary, and one after it does not', () => {
	assert.equal(looksBinary(Buffer.from([0x50, 0x4b, 0x00, 0x01])), true);
	assert.equal(looksBinary(Buffer.from('plain text')), false);
	assert.equal(looksBinary(Buffer.concat([Buffer.alloc(8000, 0x61), Buffer.from([0])])), false);
});

/** @param {(dir: string) => void} plant */
function withRepo(plant) {
	const dir = mkdtempSync(join(tmpdir(), 'conflict-marker-probe-'));
	try {
		execFileSync('git', ['init', '-q'], { cwd: dir });
		plant(dir);
		execFileSync('git', ['add', '-A'], { cwd: dir });
		return { dir, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
	} catch (err) {
		rmSync(dir, { recursive: true, force: true });
		throw err;
	}
}

test('a planted marker in a tracked file fails the run and is named by file and line', () => {
	const { dir, cleanup } = withRepo((d) => {
		writeFileSync(join(d, 'clean.md'), '# Fine\n');
		writeFileSync(join(d, 'decisions.md'), `## 1\n\nprose\n${BASE} 41a0ad7a7\n\n## 2\n`);
	});
	try {
		assert.deepEqual(scan(dir).findings, [{ file: 'decisions.md', line: 4, marker: BASE }]);
		/** @type {string[]} */
		const errors = [];
		const original = console.error;
		console.error = (/** @type {string} */ msg) => errors.push(msg);
		try {
			assert.equal(run(dir), 1);
		} finally {
			console.error = original;
		}
		assert.match(errors[0], /^decisions\.md:4: /);
	} finally {
		cleanup();
	}
});

test('an untracked file, a binary file and a symlink are not read', () => {
	const { dir, cleanup } = withRepo((d) => {
		writeFileSync(join(d, 'font.woff2'), Buffer.concat([Buffer.from([0]), Buffer.from(`\n${SPLIT}\n`)]));
		symlinkSync('/nonexistent-target', join(d, 'link'));
	});
	try {
		writeFileSync(join(dir, 'untracked.md'), `${THEIRS} theirs\n`);
		const { findings, scanned } = scan(dir);
		assert.deepEqual(findings, []);
		assert.equal(scanned, 0);
	} finally {
		cleanup();
	}
});

test('the committed tree carries no conflict-marker line', () => {
	assert.deepEqual(scan(REPO_ROOT).findings, []);
});
