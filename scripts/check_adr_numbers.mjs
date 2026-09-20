#!/usr/bin/env node
// Guardrail: every `docs/architecture/decisions.md` section number is unique,
// and every `§ N` reference in the tree points at a section that exists.
//
// Why this exists: the numbers are hand-assigned and the file is append-only,
// so two branches cut from the same base both take "the next one". They land
// at the end of the same file, git reports a conflict, and the session that
// resolves it renumbers one side — which is the moment a number goes missing
// or a reference is left pointing at the other branch's entry. In a single
// 2026-09-20 merge queue of four PRs that renumber happened FIVE times
// (decisions § 1685).
//
// The duplicate case cannot be caught on a branch, because neither branch has
// a duplicate — each has one `## 1678.` and is internally consistent. It only
// exists in the merge. This guard works because `pull_request` runs against
// the MERGE REF, so what CI reads is the state that has both. That is also
// why it is wasted effort to run it as a pre-commit hook.
//
// Two rules:
//
//   1. No section number appears twice. This is the defect: two entries
//      answering to one number, where every `§ N` link to either resolves to
//      whichever renders first and the other becomes unreachable prose.
//   2. Every `§ N` reference resolves. A renumber that misses a reference is
//      silent — `§ 1678` is valid markdown pointing at nothing in particular,
//      and in a repo with 13,000 of them nobody re-reads the set.
//
// What this deliberately does NOT check:
//
//   - GAPS. 164 numbers below the maximum are unused on `main`, the residue
//     of years of exactly the renumbering described above. Demanding a dense
//     sequence would mean renumbering 1,500 entries that ~13,000 references
//     point at, to fix nothing a reader can see. A gap is invisible; a
//     duplicate is a silently unreachable entry.
//   - ORDER. 17 entries sit out of numeric order for the same reason. The
//     number is an identifier, not a position.
//
// Run: `node scripts/check_adr_numbers.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml — ungated on
//      `needs.changes.outputs.code`, because the diff that renumbers an ADR
//      is usually docs-only and every code-gated job skips it.
// Unit tests: `node --test scripts/check_adr_numbers.test.mjs`

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const ADR_DOC = join('docs', 'architecture', 'decisions.md');

/**
 * References whose target cannot be recovered by reading, so they are recorded
 * rather than guessed at. Each is a number no section has ever carried on this
 * branch's history, cited as though it were one. Fixing them needs whoever
 * wrote the sentence, not this guard — and inventing a plausible target would
 * be worse than leaving the dangle visible.
 *
 * The guard fails when one of these becomes resolvable, so an entry cannot sit
 * here after the number it names comes into existence.
 *
 * @type {Record<number, string>}
 */
export const UNRESOLVED = {
	1810: 'cited twice in the exercise_catalogue_picker Dart twins beside a live § 1574; above the maximum, so it is either a typo or a reference to an entry that never landed',
	1958: 'cited twice in exercise_catalogue_picker.test.ts as having "asked for a Playwright" test and "raised an objection"; above the maximum',
	4704: "cited in decisions.md itself for a glyph's `+` packing; four digits, so more likely a codepoint or a line number than a section",
	8703: 'cited in followups.md as a "§ 8703 region" for the Trivy exit-code posture; four digits, same shape as 4704',
};

/** Files a `§ N` reference can appear in. Binary and lockfiles are skipped. */
const REF_EXTENSIONS = /\.(md|mjs|ts|dart|swift|kt|yml|yaml|sh|rs|go|py)$/;

/**
 * A reference is `§` or `§§`, an optional space, and a number — plus, for a
 * `§§ A-B` range, its second endpoint. Comma lists are deliberately NOT
 * followed: `§ 1254, 2026-09-18` is a section and a date, and treating the
 * tail as a reference reports the year as a missing section.
 */
const REF = /§§?\s?(\d+)(?:\s*[-–]\s*(\d+))?/g;

/**
 * Every `## N.` heading in the ADR log, in document order.
 * @param {string} doc
 */
export function sectionNumbers(doc) {
	return [...doc.matchAll(/^## (\d+)\./gm)].map((m) => ({
		number: Number(m[1]),
		line: doc.slice(0, m.index).split('\n').length,
	}));
}

/**
 * Every `§ N` reference in one file's text, with its line.
 * @param {string} text
 */
export function references(text) {
	const out = [];
	for (const m of text.matchAll(REF)) {
		const line = text.slice(0, m.index).split('\n').length;
		for (const g of [m[1], m[2]]) {
			if (g !== undefined) out.push({ number: Number(g), line });
		}
	}
	return out;
}

/**
 * @param {string} [root] repo root to read.
 * @param {Record<number, string>} [unresolved] the dangle register. Injectable so a synthetic fixture can
 *   pass `{}` — the staleness rules below are claims about THIS repo's tree,
 *   and firing them against a three-file temp dir tests nothing.
 */
export function check(root = REPO_ROOT, unresolved = UNRESOLVED) {
	/** @type {string[]} */ const errors = [];
	/** @type {string[]} */ const ok = [];

	const doc = readFileSync(join(root, ADR_DOC), 'utf8');
	const sections = sectionNumbers(doc);
	if (sections.length === 0) {
		return {
			errors: [
				`Parsed no \`## N.\` heading out of ${ADR_DOC}. Both rules would pass vacuously on a file whose heading shape changed, which is the state where a duplicate is most likely to be sitting unread.`,
			],
			ok,
		};
	}

	// (1) Uniqueness.
	/** @type {Map<number, number[]>} */ const byNumber = new Map();
	for (const s of sections) byNumber.set(s.number, [...(byNumber.get(s.number) ?? []), s.line]);
	for (const [number, lines] of [...byNumber].sort((a, b) => a[0] - b[0])) {
		if (lines.length > 1) {
			errors.push(
				`${ADR_DOC}: section ${number} is claimed by ${lines.length} entries, at lines ${lines.join(' and ')}. Every \`§ ${number}\` in the tree resolves to whichever renders first, so the other is unreachable prose. Renumber the later one to the next free number and move its references with it.`,
			);
		}
	}
	if (errors.length === 0) ok.push(`${sections.length} section numbers, none claimed twice`);

	// (2) Every reference resolves.
	const known = new Set(sections.map((s) => s.number));
	const files = execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8' })
		.split('\n')
		.filter((f) => f && REF_EXTENSIONS.test(f));
	let refCount = 0;
	/** @type {Set<number>} */ const seenUnresolved = new Set();
	const before = errors.length;
	for (const rel of files) {
		let text;
		try {
			text = readFileSync(join(root, rel), 'utf8');
		} catch {
			continue;
		}
		for (const { number, line } of references(text)) {
			refCount += 1;
			if (known.has(number)) continue;
			if (number in unresolved) {
				seenUnresolved.add(number);
				continue;
			}
			errors.push(
				`${rel}:${line}: \`§ ${number}\` names no section in ${ADR_DOC}. A renumber that misses a reference leaves valid markdown pointing at nothing. Either fix the number, or — if the target genuinely cannot be recovered — add it to UNRESOLVED in ${join('scripts', 'check_adr_numbers.mjs')} with what it was cited for.`,
			);
		}
	}
	if (refCount === 0) {
		errors.push(
			`Parsed no \`§ N\` reference out of ${files.length} tracked file(s). Rule 2 would pass vacuously.`,
		);
	}
	for (const number of Object.keys(unresolved).map(Number)) {
		if (known.has(number)) {
			errors.push(
				`Section ${number} now exists, but it is still listed in UNRESOLVED as unrecoverable. Delete that entry — the references to it resolve now.`,
			);
		} else if (!seenUnresolved.has(number)) {
			errors.push(
				`UNRESOLVED lists ${number}, but nothing in the tree cites it any more. Delete that entry rather than leaving a reason for a dangle nobody has.`,
			);
		}
	}
	if (errors.length === before) {
		ok.push(
			`${refCount} \`§ N\` references resolve (${seenUnresolved.size} recorded as unrecoverable)`,
		);
	}

	return { errors, ok };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	const { errors, ok } = check();
	for (const line of ok) console.log(`  ok: ${line}`);
	if (errors.length > 0) {
		console.error(`\nFAIL: ${errors.length} problem(s) in ${ADR_DOC}:`);
		for (const e of errors) console.error(`  - ${e}`);
		process.exit(1);
	}
	console.log(`\nOK: ${ADR_DOC} numbering is consistent.`);
}
