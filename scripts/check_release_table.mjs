#!/usr/bin/env node
// Guardrail: `docs/ops/releasing.md`'s release table describes the release
// workflows, and every column of it that is a mechanical fact is read out of the
// workflow rather than trusted.
//
// Why this exists: decisions.md § 1673 + § 1674. The `mobile_ios@*` row claimed
// the Release carries an `.ipa`, and the workflow's own `--no-codesign` build
// cannot produce one — `flutter build ipa --no-codesign` stops at the
// `.xcarchive`. The attach step then globbed a path that matched nothing and
// `softprops/action-gh-release` reported success, so the row was wrong for as
// long as nobody cut an iOS tag, which is the entire life of the file. The
// neighbouring prose claimed a watchOS target `Runner.xcodeproj` does not
// reference. Both were transcriptions nothing compared.
//
// Two of the five columns are mechanical and are checked here:
//
//   1. **Runs** — the row's runner must be the workflow's `runs-on:`.
//   2. **Attaches back to the Release** — whether the row promises an artifact
//      must match whether the workflow has a LIVE (uncommented) upload step, and
//      when it promises one, the extension it names must appear in that step's
//      `files:` glob.
//
// A third rule has no column of its own because it is what makes column 2
// trustworthy: an upload step carrying a `files:` glob must set
// `fail_on_unmatched_files: true`. The input defaults to FALSE, so a glob that
// matches nothing attaches nothing and still reports success — the exact shape
// that hid § 1673. Three live workflows were missing it (§ 1674).
//
// **What this does NOT check, stated so the guard is not read as complete.** The
// `Signs` and `Publishes to` columns are prose — "release keystore from secrets",
// "Play Internal track", "AWS S3 + CloudFront + Lambda (`prod` env at
// `threkir.com`)" — and a matcher over them would either drown in false positives
// or be narrowed until it read as complete while checking nothing, which is the
// failure `check_watch_doc_counts.mjs`'s header argues against at length. They
// stay a human's job. Nor does this know whether a build step's output path is
// real; that is what rule 3 makes loud at release time instead of silent.
//
// Both directions, because one alone is a guard that reads as complete: every
// table row must resolve to a workflow, and every workflow named in the
// tag-to-workflow list must have a row. A table that parses to zero rows is a
// hard error, not a pass — a dead matcher is a vacuous check.

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/**
 * The doc is the subject; both inputs are read from disk so nothing is transcribed.
 * @param {string} [root]
 * @returns {{ doc: string, workflowOf: (file: string) => string | null }}
 */
export function readInputs(root = repoRoot) {
	return {
		doc: readFileSync(resolve(root, 'docs/ops/releasing.md'), 'utf8'),
		workflowOf: (/** @type {string} */ file) => {
			const p = resolve(root, file);
			return existsSync(p) ? readFileSync(p, 'utf8') : null;
		},
	};
}

/**
 * The fenced `<tag>@1.2.3 → .github/workflows/<file>` block, which is the doc's
 * own statement of which workflow a tag runs. Parsing it rather than hardcoding
 * the mapping is what lets a new app appear without editing this file.
 * @param {string} doc
 * @returns {Map<string, string>}
 */
export function parseTagMap(doc) {
	const out = new Map();
	for (const line of doc.split('\n')) {
		const m = /^([a-z0-9_-]+)@1\.2\.3\s+→\s+(\.github\/workflows\/[a-z0-9-]+\.yml)\s*$/i.exec(line.trim());
		if (m) out.set(m[1], m[2]);
	}
	return out;
}

/**
 * The release table's rows, keyed by the app the `<app>@*` cell names.
 * @param {string} doc
 * @returns {Map<string, { runs: string, signs: string, publishes: string, attaches: string }>}
 */
export function parseTable(doc) {
	/** @type {Map<string, { runs: string, signs: string, publishes: string, attaches: string }>} */
	const rows = new Map();
	let inTable = false;
	for (const line of doc.split('\n')) {
		if (line.startsWith('| Release tag | Runs |')) { inTable = true; continue; }
		if (inTable) {
			if (!line.startsWith('|')) { inTable = false; continue; }
			if (line.startsWith('|---')) continue;
			const cells = line.replace(/^\||\|$/g, '').split('|').map((/** @type {string} */ c) => c.trim());
			if (cells.length < 5) continue;
			const app = /^`([a-z0-9_-]+)@\*`$/i.exec(cells[0]);
			if (app) rows.set(app[1], { runs: cells[1], signs: cells[2], publishes: cells[3], attaches: cells[4] });
		}
	}
	return rows;
}

/**
 * Strip comment lines so a commented-out step is never read as a live one.
 * @param {string} yaml
 * @returns {string[]}
 */
function liveLines(yaml) {
	return yaml.split('\n').filter((/** @type {string} */ l) => !/^\s*#/.test(l));
}

/**
 * @param {string} yaml
 * @returns {{ runsOn: string, attaches: boolean, files: string | null, failsOnUnmatched: boolean }}
 */
export function inspectWorkflow(yaml) {
	const live = liveLines(yaml);
	const runsOn = (live.find((/** @type {string} */ l) => /^\s*runs-on:/.test(l)) ?? '').replace(/.*runs-on:\s*/, '').trim();
	// Both `uses:` and `- uses:` occur in this tree; anchoring on the former alone
	// silently reads a real upload step as absent.
	const uploadIdx = live.findIndex((/** @type {string} */ l) => /^\s*(-\s*)?uses:\s*softprops\/action-gh-release@/.test(l));
	if (uploadIdx === -1) return { runsOn, attaches: false, files: null, failsOnUnmatched: false };
	const after = live.slice(uploadIdx, uploadIdx + 12);
	const filesLine = after.find((/** @type {string} */ l) => /^\s*files:/.test(l));
	return {
		runsOn,
		attaches: true,
		files: filesLine ? filesLine.replace(/.*files:\s*/, '').trim() : null,
		failsOnUnmatched: after.some((/** @type {string} */ l) => /^\s*fail_on_unmatched_files:\s*true\s*$/.test(l)),
	};
}

/**
 * `— (build smoke-check only; ...)` and friends all mean "nothing is attached".
 * @param {string} cell
 * @returns {boolean}
 */
function promisesArtifact(cell) {
	return !/^—/.test(cell.trim());
}

/**
 * The extension a cell names, e.g. `` `.ipa` `` → `.ipa`, "build zip" → `.zip`.
 * @param {string} cell
 * @returns {string | null}
 */
function extensionOf(cell) {
	const tick = /`\.([a-z0-9]+)`/i.exec(cell);
	if (tick) return `.${tick[1].toLowerCase()}`;
	const bare = /\b(zip|aab|ipa|apk)\b/i.exec(cell);
	return bare ? `.${bare[1].toLowerCase()}` : null;
}

/**
 * @param {{ doc: string, workflowOf: (file: string) => string | null }} inputs
 * @returns {{ problems: string[], ok: string[] }}
 */
export function check({ doc, workflowOf }) {
	/** @type {string[]} */
	const problems = [];
	/** @type {string[]} */
	const ok = [];
	const tagMap = parseTagMap(doc);
	const table = parseTable(doc);

	if (tagMap.size === 0) problems.push('the tag-to-workflow list in docs/ops/releasing.md parsed to zero entries, so this guard checked nothing. Fix the parser, do not delete the check.');
	if (table.size === 0) problems.push('the release table in docs/ops/releasing.md parsed to zero rows, so this guard checked nothing. Fix the parser, do not delete the check.');

	for (const [app, row] of table) {
		const file = tagMap.get(app);
		if (!file) { problems.push(`the release table has a \`${app}@*\` row that the tag-to-workflow list above it does not name. One of the two is wrong.`); continue; }
		const yaml = workflowOf(file);
		if (yaml === null) { problems.push(`docs/ops/releasing.md maps \`${app}@*\` to ${file}, which does not exist.`); continue; }

		const wf = inspectWorkflow(yaml);

		if (row.runs !== wf.runsOn) {
			problems.push(`the \`${app}@*\` row says it runs on \`${row.runs}\` where ${file} declares \`runs-on: ${wf.runsOn}\`.`);
		} else ok.push(`${app}: runs-on ${wf.runsOn}`);

		const promised = promisesArtifact(row.attaches);
		if (promised && !wf.attaches) {
			problems.push(`the \`${app}@*\` row promises the Release carries ${row.attaches}, but ${file} has no live \`softprops/action-gh-release\` step — the Release would carry nothing. This is the § 1673 shape: an artifact claimed in the docs that the workflow cannot produce.`);
		} else if (!promised && wf.attaches) {
			problems.push(`the \`${app}@*\` row says nothing is attached, but ${file} has a live upload step. The docs understate what a release publishes.`);
		} else if (promised && wf.attaches) {
			const ext = extensionOf(row.attaches);
			if (ext && wf.files && !wf.files.toLowerCase().includes(ext)) {
				problems.push(`the \`${app}@*\` row says the Release carries ${row.attaches}, but ${file} uploads \`${wf.files}\`, which is not a ${ext}.`);
			} else ok.push(`${app}: attaches ${ext ?? 'an artifact'}`);
		} else ok.push(`${app}: attaches nothing, and the row says so`);

		if (wf.attaches && wf.files && !wf.failsOnUnmatched) {
			problems.push(`${file} uploads \`${wf.files}\` without \`fail_on_unmatched_files: true\`. The input defaults to false, so if that path ever moves the Release attaches nothing and the workflow still reports success — the silent half of § 1673.`);
		}
	}

	for (const [app, file] of tagMap) {
		if (!table.has(app)) problems.push(`${file} is listed for \`${app}@*\` but has no row in the release table, so nothing describes what it publishes.`);
	}

	return { problems, ok };
}

function main() {
	const { problems, ok } = check(readInputs());
	for (const o of ok) console.log(`[OK] ${o}`);
	if (problems.length === 0) {
		console.log(`\nThe release table agrees with the workflows it describes (${ok.length} derived claim(s) across ${new Set(ok.map((/** @type {string} */ o) => o.split(':')[0])).size} app(s)). Signs / Publishes-to are prose and are not checked.`);
		return 0;
	}
	for (const p of problems) console.error(`[FAIL] ${p}`);
	console.error(`\n${problems.length} release-table problem(s). The workflow is the fact; the table is the transcription.`);
	return 1;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
