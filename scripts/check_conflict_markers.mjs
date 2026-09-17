#!/usr/bin/env node
// Guardrail: no tracked file carries a merge-conflict marker line.
//
// Why this exists: `docs/architecture/decisions.md` reached `main` carrying
// three `|||||||` lines — the merge-BASE marker diff3 conflict style writes
// between "ours" and the common ancestor. Two squash merges resolved their
// conflicts by keeping both sides and deleting `<<<<<<<`, `=======` and
// `>>>>>>>`, but not the fourth marker, which only appears under
// `merge.conflictStyle = diff3` / `zdiff3` and which nobody was looking for.
// Every later session appending to that file resolved its own conflict around
// them. In markdown the line renders as a stray paragraph of pipes, so no
// reader and no link guard noticed.
//
// `git diff --check` would catch the new ones a diff introduces, but it also
// reports every trailing-whitespace line in the diff and so cannot gate on its
// own. This reads the whole tracked tree instead: a marker already on `main`
// is found the first time the guard runs, not merely prevented from growing.
//
// A marker is one of the four seven-character runs git writes — `<<<<<<<`,
// `|||||||`, `=======`, `>>>>>>>` — at the very start of a line, followed by a
// space or the end of the line. That is git's own `is_conflict_marker` rule.
// A `=======` setext underline of exactly that length would match too; write
// the heading in ATX form (`# Title`) or with a different underline length.
//
// Binary files (a NUL in the first 8 KiB, git's own heuristic) and anything
// that is not a regular file — a symlink, a submodule gitlink — are skipped.
//
// Run: `node scripts/check_conflict_markers.mjs` (or `npm run check:conflict-markers`)
// CI:  the `parity-matrix` job in .github/workflows/ci.yml — ungated on
//      `needs.changes.outputs.code`, because a docs-only diff is the diff most
//      likely to carry one and every code-gated job skips it.
// Unit tests: `node --test scripts/check_conflict_markers.test.mjs`

import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const MARKER = /^(<{7}|\|{7}|={7}|>{7})(?: |$)/;

const BINARY_SNIFF_BYTES = 8000;

/**
 * @typedef {{ file: string, line: number, marker: string }} Finding
 */

/**
 * Every conflict-marker line in one file's text, 1-based.
 * @param {string} text
 * @returns {Array<{ line: number, marker: string }>}
 */
export function markersIn(text) {
	/** @type {Array<{ line: number, marker: string }>} */
	const found = [];
	const lines = text.split(/\r?\n/);
	for (let i = 0; i < lines.length; i++) {
		const m = lines[i].match(MARKER);
		if (m) found.push({ line: i + 1, marker: m[1] });
	}
	return found;
}

/**
 * @param {Buffer} bytes
 * @returns {boolean}
 */
export function looksBinary(bytes) {
	return bytes.subarray(0, BINARY_SNIFF_BYTES).includes(0);
}

/**
 * @param {string} root a git work tree
 * @returns {string[]}
 */
export function trackedFiles(root) {
	return execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
		.split('\0')
		.filter(Boolean);
}

/**
 * @param {string} root a git work tree
 * @returns {{ findings: Finding[], scanned: number }}
 */
export function scan(root) {
	/** @type {Finding[]} */
	const findings = [];
	let scanned = 0;
	for (const file of trackedFiles(root)) {
		const abs = join(root, file);
		let stat;
		try {
			stat = lstatSync(abs);
		} catch {
			continue;
		}
		if (!stat.isFile()) continue;
		const bytes = readFileSync(abs);
		if (looksBinary(bytes)) continue;
		scanned++;
		for (const hit of markersIn(bytes.toString('utf8'))) findings.push({ file, ...hit });
	}
	return { findings, scanned };
}

/**
 * @param {string} root
 * @returns {number} the process exit code
 */
export function run(root) {
	const { findings, scanned } = scan(root);
	if (findings.length === 0) {
		console.log(`check_conflict_markers: OK — ${scanned} tracked text files, no conflict-marker lines.`);
		return 0;
	}
	for (const f of findings) {
		console.error(`${f.file}:${f.line}: a line starting \`${f.marker}\` is a merge-conflict marker left behind by a resolved merge. Delete the line, and check the text either side of it reads as one resolution rather than two.`);
	}
	console.error(`check_conflict_markers: ${findings.length} conflict-marker line(s) across ${new Set(findings.map((f) => f.file)).size} file(s).`);
	return 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	process.exit(run(process.env.CONFLICT_MARKER_ROOT ?? REPO_ROOT));
}
