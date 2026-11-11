#!/usr/bin/env node
// Guardrail: a pull request may not ADD a dependency with a known advisory at
// CVSS 7.0 or higher. Advisories already on the base are not its to fix.
//
// Why this exists: decisions.md § 2452 condition (e), issue #1366. osv-scanner
// in `supply-chain-scan.yml` is advisory and cannot be put in the code-scanning
// ruleset: its SARIF results carry no line region, GitHub files every one at
// line 1 of its lockfile, and merge protection counts only alerts on changed
// lines, so a PR adding a vulnerable package to an existing lockfile merges,
// while a missing upload would hold every PR. This script asks the question
// the ruleset cannot: what does merging this PR add?
//
// How (decisions.md § 2457):
//
//   1. Changed paths are `git diff --name-only <base> HEAD`. In CI, HEAD is the
//      PR's merge commit and <base> its first parent, the base branch tip, so
//      the diff is exactly what the merge would add to `main`.
//   2. If no changed path is a dependency input (`DEPENDENCY_INPUT`, or this
//      guard's own wiring), the PR cannot introduce an advisory against the
//      same database, and nothing is scanned: no scan means no exposure to an
//      OSV database outage on a PR that could not fail anyway.
//   3. Otherwise HEAD is scanned, then <base> in a detached worktree, both with
//      the same pinned binary, `--offline-vulnerabilities` and the same
//      database cache. Head goes first: the second download can only be newer,
//      so an advisory published between the two scans can appear at the base
//      only, never at the head only, and cannot read as introduced.
//   4. Findings are keyed by (ecosystem, package, version, advisory id). A
//      group of aliased advisories is new when none of its ids is at the base.
//      A new group at `THRESHOLD` or above fails the job.
//   5. Each tree's own `osv-scanner.toml` files apply to its own scan, so an
//      ignore the PR adds is visible in the diff and listed in the summary,
//      and an ignore the PR removes surfaces its advisory as new.
//
// Severity (`scoreGroup`): the highest CVSS base score available, where
// CVSS v3.x vectors are scored here (`cvss3BaseScore`, the spec's formula) and
// v4/v2 come from osv-scanner's own `max_severity` for the group (the v4 base
// score is a 270-row lookup, not a formula, and the pinned scanner already
// implements it: it is the same figure its SARIF `security-severity` carries).
// With no number, a GitHub advisory's `database_specific.severity` label is the
// fallback (CRITICAL 9.0, HIGH 7.0, MODERATE 4.0, LOW 0.1). With neither, the
// advisory is UNSCORED: listed in the summary and never fails, which is where a
// RustSec "unmaintained" notice lands.
//
// Expired ignores: osv-scanner stops applying an entry once `ignoreUntil` has
// passed, so its advisory reappears at both base and head and is not "new".
// The entry's contract is "re-read by this date", so a PR that changes a
// lockfile the expired entry covers fails until someone re-reads it; every
// other PR gets a warning. An entry with no `ignoreUntil` or no `reason` fails
// a PR that edits that file, since it is a waiver with no review date.
//
// Outages: an exit outside 0 (clean), 1 (vulnerabilities) and 128 (no
// packages) is retried once, then fails with an `::error::` that says re-run.
// osv-scanner 2.7.0 exits 127 when an offline database cannot be loaded and
// still writes `{"results": []}`, so the exit code, not the report, is read.
//
// Report mode (push to `main`): head only, every advisory listed, nothing
// fails on a finding; a scanner failure still fails, and so does a scanned
// file `DEPENDENCY_INPUT` does not match, since step 2 would skip a PR that
// changed only that file. ci.yml has no schedule; `supply-chain-scan.yml` is
// the weekly scan.
//
// Stdlib only, like every guard here.
//
// Run: `node scripts/check_dependency_advisories.mjs --scanner <osv-scanner>
//        --mode pr --base-ref HEAD^1` (or `--mode report`)
// CI:  the `dependency-advisories` job in .github/workflows/ci.yml, which is
//      in the `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_dependency_advisories.test.mjs`

import { spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, isAbsolute, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * @typedef {{ name: string, version: string, ecosystem: string }} Pkg
 * @typedef {{ type?: string, score?: string }} Severity
 * @typedef {{ id: string, aliases?: string[], severity?: Severity[], database_specific?: { severity?: unknown } }} Vuln
 * @typedef {{ ids: string[], aliases?: string[], max_severity?: string }} Group
 * @typedef {{ package: Pkg, vulnerabilities?: Vuln[], groups?: Group[] }} PackageResult
 * @typedef {{ source: { path: string, type?: string }, packages?: PackageResult[] }} SourceResult
 * @typedef {{ results?: SourceResult[] }} Report
 * @typedef {{ score: number | null, basis: string }} Scored
 * @typedef {{ ecosystem: string, name: string, version: string, ids: string[], aliases: string[],
 *             lockfiles: string[], score: number | null, basis: string }} Finding
 * @typedef {{ file: string, dir: string, line: number, id: string | null,
 *             ignoreUntil: string | null, hasReason: boolean }} IgnoreEntry
 */

export const THRESHOLD = 7.0;

/// The ruling exit codes of `osv-scanner scan source` 2.7.0. Anything else is
/// the scanner failing, never a verdict about the tree.
export const SCANNER_OK = new Set([0, 1, 128]);

export const RETRY_DELAY_MS = Number(process.env.DEPENDENCY_ADVISORIES_RETRY_DELAY_MS ?? 20000);

/// Basenames osv-scanner reads (or could), plus its own config. Over-wide on
/// purpose: a false match costs one scan, a missing one skips the gate, which
/// is why report mode fails on any scanned file this does not match.
export const DEPENDENCY_INPUT =
	/^(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|pnpm-workspace\.yaml|yarn\.lock|bun\.lockb?|package\.json|deno\.lock|deno\.jsonc?|pubspec\.(lock|yaml)|go\.(mod|sum)|Cargo\.(lock|toml)|Package\.(resolved|swift)|Podfile(\.lock)?|requirements[^/]*\.txt|poetry\.lock|Pipfile\.lock|pdm\.lock|uv\.lock|pylock\.toml|Gemfile\.lock|composer\.lock|gradle\.lockfile|pom\.xml|packages\.lock\.json|mix\.lock|renv\.lock|conan\.lock|[^/]+\.(cs|fs|vb)proj|packages\.config|Directory\.Packages\.props|osv-scanner\.toml)$/;

/// Changes to the gate itself run it, so a wiring change is exercised.
export const SELF_PATHS = new Set([
	'scripts/check_dependency_advisories.mjs',
	'scripts/check_dependency_advisories.test.mjs',
	'.github/workflows/ci.yml',
]);

/** @param {string} path */
export function isDependencyInput(path) {
	return SELF_PATHS.has(path) || DEPENDENCY_INPUT.test(basename(path));
}

// ---------------------------------------------------------------- severity

const V3_WEIGHTS = {
	AV: { N: 0.85, A: 0.62, L: 0.55, P: 0.2 },
	AC: { L: 0.77, H: 0.44 },
	UI: { N: 0.85, R: 0.62 },
	CIA: { H: 0.56, L: 0.22, N: 0 },
};

/// CVSS v3.1 `Roundup`: the smallest one-decimal number >= x, computed on
/// integers so 4.000000001 does not become 4.1.
/** @param {number} x */
export function roundUp(x) {
	const i = Math.round(x * 100000);
	return i % 10000 === 0 ? i / 100000 : (Math.floor(i / 10000) + 1) / 10;
}

/// The base score of a CVSS v3.0 / v3.1 vector, or null when the string is not
/// one (a v4 or v2 vector, a missing metric, an unknown value). v3.0 vectors
/// use the v3.1 rounding, which differs from v3.0's in the last decimal only.
/** @param {string} vector */
export function cvss3BaseScore(vector) {
	const parts = String(vector).trim().split('/');
	if (!/^CVSS:3\.[01]$/.test(parts[0] ?? '')) return null;
	/** @type {Record<string, string>} */
	const m = {};
	for (const p of parts.slice(1)) {
		const [k, v] = p.split(':');
		if (!k || !v || k in m) return null;
		m[k] = v;
	}
	const scope = m.S;
	if (scope !== 'U' && scope !== 'C') return null;
	/** @param {Record<string, number>} table @param {string | undefined} key */
	const w = (table, key) => (key !== undefined && key in table ? table[key] : undefined);
	const av = w(V3_WEIGHTS.AV, m.AV);
	const ac = w(V3_WEIGHTS.AC, m.AC);
	const ui = w(V3_WEIGHTS.UI, m.UI);
	const pr = w(scope === 'C' ? { N: 0.85, L: 0.68, H: 0.5 } : { N: 0.85, L: 0.62, H: 0.27 }, m.PR);
	const c = w(V3_WEIGHTS.CIA, m.C);
	const i = w(V3_WEIGHTS.CIA, m.I);
	const a = w(V3_WEIGHTS.CIA, m.A);
	if ([av, ac, ui, pr, c, i, a].some((x) => x === undefined)) return null;
	const iss = 1 - (1 - /** @type {number} */ (c)) * (1 - /** @type {number} */ (i)) * (1 - /** @type {number} */ (a));
	const impact = scope === 'U' ? 6.42 * iss : 7.52 * (iss - 0.029) - 3.25 * Math.pow(iss - 0.02, 15);
	const exploit =
		8.22 * /** @type {number} */ (av) * /** @type {number} */ (ac) * /** @type {number} */ (pr) * /** @type {number} */ (ui);
	if (impact <= 0) return 0;
	return roundUp(Math.min(scope === 'U' ? impact + exploit : 1.08 * (impact + exploit), 10));
}

export const GHSA_LABEL_SCORE = new Map([
	['CRITICAL', 9.0],
	['HIGH', 7.0],
	['MODERATE', 4.0],
	['MEDIUM', 4.0],
	['LOW', 0.1],
]);

/**
 * The rule stated in the header, for one group of aliased advisories.
 * @param {Group} group
 * @param {readonly Vuln[]} vulns the group's own advisory records
 * @returns {Scored}
 */
export function scoreGroup(group, vulns) {
	/** @type {number[]} */
	const v3 = [];
	for (const v of vulns) {
		for (const s of v.severity ?? []) {
			if (s.type !== 'CVSS_V3' || typeof s.score !== 'string') continue;
			const n = cvss3BaseScore(s.score);
			if (n !== null) v3.push(n);
		}
	}
	const raw = group.max_severity;
	const osv = typeof raw === 'string' && raw.trim() !== '' ? Number(raw) : NaN;
	const osvOk = Number.isFinite(osv) && osv >= 0 && osv <= 10;
	if (v3.length > 0 || osvOk) {
		const best = Math.max(...v3, osvOk ? osv : -1);
		const fromV3 = v3.length > 0 && Math.max(...v3) === best;
		return { score: best, basis: fromV3 ? 'CVSS v3' : 'CVSS (osv-scanner)' };
	}
	let label = -1;
	for (const v of vulns) {
		const s = v.database_specific?.severity;
		const n = typeof s === 'string' ? GHSA_LABEL_SCORE.get(s.toUpperCase()) : undefined;
		if (n !== undefined && n > label) label = n;
	}
	if (label >= 0) return { score: label, basis: 'GHSA label' };
	return { score: null, basis: 'unscored' };
}

// ---------------------------------------------------------------- findings

/**
 * Flatten an osv-scanner JSON report into one finding per (package, version,
 * advisory group), with the lockfiles it was seen in relative to `root`.
 * @param {Report} report
 * @param {string} root
 * @returns {Finding[]}
 */
export function findingsOf(report, root) {
	/** @type {Map<string, Finding>} */
	const out = new Map();
	for (const src of report.results ?? []) {
		const lockfile = relPath(root, src.source.path);
		for (const pkg of src.packages ?? []) {
			const vulns = pkg.vulnerabilities ?? [];
			if (vulns.length === 0) continue;
			const groups = pkg.groups?.length ? pkg.groups : vulns.map((v) => ({ ids: [v.id], aliases: v.aliases ?? [] }));
			for (const g of groups) {
				const ids = [...g.ids].sort();
				const own = vulns.filter((v) => g.ids.includes(v.id));
				const { ecosystem, name, version } = pkg.package;
				const key = [ecosystem, name, version, ids.join(',')].join('\u0000');
				const seen = out.get(key);
				if (seen) {
					if (!seen.lockfiles.includes(lockfile)) seen.lockfiles.push(lockfile);
					continue;
				}
				const aliases = [...new Set([...(g.aliases ?? []), ...own.flatMap((v) => v.aliases ?? []), ...ids])].sort();
				out.set(key, { ecosystem, name, version, ids, aliases, lockfiles: [lockfile], ...scoreGroup(g, own) });
			}
		}
	}
	return [...out.values()];
}

/** @param {Finding} f */
const advisoryKeys = (f) => f.ids.map((id) => [f.ecosystem, f.name, f.version, id].join('\u0000'));

/**
 * Head findings none of whose advisory ids is at the base for the same
 * package and version.
 * @param {readonly Finding[]} head
 * @param {readonly Finding[]} base
 */
export function introduced(head, base) {
	const known = new Set(base.flatMap(advisoryKeys));
	return head.filter((f) => !advisoryKeys(f).some((k) => known.has(k)));
}

/** @param {Finding} f */
export const blocks = (f) => f.score !== null && f.score >= THRESHOLD;

/** @param {string} root @param {string} p */
function relPath(root, p) {
	if (!isAbsolute(p)) return p.split(sep).join('/');
	let r = relative(root, p);
	if (r.startsWith('..')) {
		try {
			r = relative(realpathSync(root), p);
		} catch {
			/* keep the first answer */
		}
	}
	return r.split(sep).join('/');
}

/**
 * Scanned files `DEPENDENCY_INPUT` does not match: a PR changing only one of
 * them would skip the scan.
 * @param {Report} report
 * @param {string} root
 */
export function uncoveredSources(report, root) {
	return [...new Set((report.results ?? []).map((s) => relPath(root, s.source.path)))].filter((p) => !isDependencyInput(p)).sort();
}

// ---------------------------------------------------------------- ignores

/**
 * The `[[IgnoredVulns]]` entries of one osv-scanner.toml. Line-based: the
 * file holds tables of flat keys, a date literal and (multi-line) strings.
 * @param {string} text
 * @param {string} file repo-relative path
 * @returns {IgnoreEntry[]}
 */
export function parseIgnores(text, file) {
	/** @type {IgnoreEntry[]} */
	const out = [];
	/** @type {IgnoreEntry | null} */
	let cur = null;
	const lines = text.split(/\r?\n/);
	const dir = dirname(file) === '.' ? '' : dirname(file);
	for (let n = 0; n < lines.length; n++) {
		const line = lines[n].trim();
		if (line === '' || line.startsWith('#')) continue;
		if (line.startsWith('[')) {
			cur = null;
			if (/^\[\[\s*IgnoredVulns\s*\]\]/.test(line)) {
				cur = { file, dir, line: n + 1, id: null, ignoreUntil: null, hasReason: false };
				out.push(cur);
			}
			continue;
		}
		const kv = /^([A-Za-z_]+)\s*=\s*(.*)$/.exec(line);
		if (!kv || !cur) continue;
		const [, key, value] = kv;
		const delim = value.startsWith('"""') ? '"""' : value.startsWith("'''") ? "'''" : null;
		let body = value;
		if (delim) {
			body = value.slice(3);
			while (!body.includes(delim) && n + 1 < lines.length) body += '\n' + lines[++n];
			body = body.slice(0, body.indexOf(delim));
		} else {
			body = body.replace(/\s+#.*$/, '').replace(/^["']|["']$/g, '');
		}
		if (key === 'id') cur.id = body.trim() || null;
		else if (key === 'ignoreUntil') cur.ignoreUntil = /^(\d{4}-\d{2}-\d{2})/.exec(body.trim())?.[1] ?? null;
		else if (key === 'reason') cur.hasReason = body.replace(/\\\s*\n/g, '').trim() !== '';
	}
	return out;
}

/** osv-scanner stops ignoring from the start of the `ignoreUntil` day (UTC). */
/** @param {IgnoreEntry} e @param {string} today YYYY-MM-DD */
export const isExpired = (e, today) => e.ignoreUntil !== null && e.ignoreUntil <= today;

/** @param {string} a @param {string} b YYYY-MM-DD */
const daysBetween = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000);

/**
 * @param {readonly IgnoreEntry[]} entries head's entries
 * @param {readonly IgnoreEntry[]} baseEntries base's entries ([] in report mode)
 * @param {readonly Finding[]} headFindings
 * @param {ReadonlySet<string> | null} changed null in report mode
 * @param {string} today
 */
export function judgeIgnores(entries, baseEntries, headFindings, changed, today) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const warnings = [];
	/** @type {string[]} */
	const notes = [];
	const baseIds = new Set(baseEntries.map((e) => `${e.file}\u0000${e.id}`));
	for (const e of entries) {
		const where = `${e.file}:${e.line}`;
		const touchedFile = changed?.has(e.file) ?? false;
		if (!e.id || !e.ignoreUntil || !e.hasReason) {
			const missing = [!e.id && 'id', !e.ignoreUntil && 'ignoreUntil', !e.hasReason && 'reason'].filter(Boolean).join(', ');
			const msg = `${where}: the ignore for ${e.id ?? '(no id)'} has no ${missing}. Every waiver names one advisory, a reason and an ignoreUntil review date (decisions § 2422).`;
			(touchedFile ? errors : warnings).push(msg);
			continue;
		}
		if (changed && !baseIds.has(`${e.file}\u0000${e.id}`)) {
			notes.push(`${where}: this PR adds an ignore for ${e.id} until ${e.ignoreUntil}.`);
		}
		if (isExpired(e, today)) {
			const lockfiles = [
				...new Set(
					headFindings
						.filter((f) => f.aliases.includes(/** @type {string} */ (e.id)))
						.flatMap((f) => f.lockfiles)
						.filter((l) => (dirname(l) === '.' ? '' : dirname(l)) === e.dir),
				),
			].sort();
			if (lockfiles.length === 0) {
				warnings.push(`${where}: the ignore for ${e.id} expired on ${e.ignoreUntil} and matches nothing scanned; delete it.`);
				continue;
			}
			const touched = changed ? lockfiles.filter((l) => changed.has(l)) : [];
			const msg =
				`${where}: the ignore for ${e.id} expired on ${e.ignoreUntil}, so osv-scanner reports it again in ${lockfiles.join(', ')}. ` +
				'Re-read the advisory, then fix the dependency or renew ignoreUntil with a reason.';
			if (touched.length > 0) errors.push(`${msg} This PR changes ${touched.join(', ')}, so it fails until then.`);
			else warnings.push(msg);
			continue;
		}
		const left = daysBetween(today, e.ignoreUntil);
		if (left <= 30) warnings.push(`${where}: the ignore for ${e.id} expires in ${left} day(s), on ${e.ignoreUntil}.`);
	}
	return { errors, warnings, notes };
}

// ---------------------------------------------------------------- running

/** @param {number} ms */
function sleep(ms) {
	if (ms > 0) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

/**
 * Run the scanner over `root`, retrying a failing exit once.
 * @param {string} scanner
 * @param {string} root
 * @param {string} outFile
 * @param {(line: string) => void} log
 * @returns {{ ok: true, report: Report } | { ok: false, status: number | null, detail: string }}
 */
export function scan(scanner, root, outFile, log, delayMs = RETRY_DELAY_MS) {
	const args = [
		'scan',
		'source',
		'--recursive',
		'--offline-vulnerabilities',
		'--download-offline-databases',
		'--all-packages',
		'--format',
		'json',
		'--output-file',
		outFile,
		'.',
	];
	/** @type {number | null} */
	let status = null;
	let detail = '';
	for (let attempt = 1; attempt <= 2; attempt++) {
		rmSync(outFile, { force: true });
		const r = spawnSync(scanner, args, { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
		status = r.status;
		detail = (r.error?.message ?? '') + (r.stderr ?? '').split('\n').filter(Boolean).slice(-3).join(' | ');
		if (status !== null && SCANNER_OK.has(status)) {
			if (status === 128 && !existsSync(outFile)) return { ok: true, report: { results: [] } };
			try {
				const report = /** @type {Report} */ (JSON.parse(readFileSync(outFile, 'utf8')));
				if (Array.isArray(report.results)) return { ok: true, report };
				detail = 'the JSON report has no results array';
			} catch (err) {
				detail = `the JSON report could not be read: ${/** @type {Error} */ (err).message}`;
			}
		}
		if (attempt === 1) {
			log(`::warning::osv-scanner exited ${status} on ${root} (${detail}); retrying once.`);
			sleep(delayMs);
		}
	}
	return { ok: false, status, detail };
}

/** @param {string} cwd @param {string[]} args */
function git(cwd, args) {
	const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
	if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${(r.stderr ?? '').trim()}`);
	return r.stdout;
}

/** @param {string} root */
function readIgnores(root) {
	return git(root, ['ls-files', '-z', '--', 'osv-scanner.toml', ':(glob)**/osv-scanner.toml'])
		.split('\0')
		.filter(Boolean)
		.flatMap((f) => parseIgnores(readFileSync(join(root, f), 'utf8'), f));
}

/** @param {number | null} s */
const fmt = (s) => (s === null ? '-' : s.toFixed(1));

/** @param {readonly Finding[]} fs */
function table(fs) {
	if (fs.length === 0) return ['None.', ''];
	const rows = [...fs].sort((a, b) => (b.score ?? -1) - (a.score ?? -1) || a.name.localeCompare(b.name));
	return [
		'| Score | Basis | Package | Version | Ecosystem | Advisory | Lockfile |',
		'|---|---|---|---|---|---|---|',
		...rows.map((f) => `| ${fmt(f.score)} | ${f.basis} | ${f.name} | ${f.version} | ${f.ecosystem} | ${f.ids.join(', ')} | ${f.lockfiles.join(', ')} |`),
		'',
	];
}

/**
 * @param {{ scanner: string, mode: 'pr' | 'report', root: string, baseRef?: string,
 *           today?: string, delayMs?: number, log?: (l: string) => void, summary?: (l: string) => void }} opts
 * @returns {number} exit code: 0 pass, 1 a PR-introduced finding or waiver failure, 2 scanner or setup failure
 */
export function run(opts) {
	const log = opts.log ?? ((l) => console.log(l));
	/** @type {string[]} */
	const md = ['## Dependency advisories', ''];
	const flush = () => (opts.summary ?? ((t) => console.log(t)))(md.join('\n') + '\n');
	const today = opts.today ?? new Date().toISOString().slice(0, 10);
	const work = mkdtempSync(join(process.env.RUNNER_TEMP ?? tmpdir(), 'dep-advisories-'));
	/** @param {string} what @param {{ status: number | null, detail: string }} r */
	const outage = (what, r) => {
		log(
			`::error::osv-scanner failed twice while scanning the ${what} tree (exit ${r.status}; ${r.detail}). ` +
				'This is the scanner or the OSV database download failing, not a finding in this PR: re-run the job.',
		);
		md.push(`**Scanner failure on the ${what} tree** (exit ${r.status}). Not a finding: re-run the job.`, '');
		flush();
		return 2;
	};
	let baseDir = '';
	try {
		if (opts.mode === 'report') {
			md.push(`Report only (push to \`main\`): every advisory at HEAD, nothing fails on a finding. PRs fail on a new advisory at CVSS >= ${THRESHOLD.toFixed(1)}.`, '');
			const head = scan(opts.scanner, opts.root, join(work, 'head.json'), log, opts.delayMs);
			if (!head.ok) return outage('HEAD', head);
			const findings = findingsOf(head.report, opts.root);
			const ign = judgeIgnores(readIgnores(opts.root), [], findings, null, today);
			const uncovered = uncoveredSources(head.report, opts.root);
			md.push(`### At or above ${THRESHOLD.toFixed(1)}`, '', ...table(findings.filter(blocks)));
			md.push('### Below the threshold or unscored', '', ...table(findings.filter((f) => !blocks(f))));
			for (const w of ign.warnings) log(`::warning::${w}`);
			if (ign.warnings.length) md.push('### Waivers', '', ...ign.warnings.map((w) => `- ${w}`), '');
			for (const u of uncovered) {
				log(
					`::error::osv-scanner read ${u}, which DEPENDENCY_INPUT in scripts/check_dependency_advisories.mjs does not match, ` +
						'so a PR changing only that file would skip this gate. Add its basename there.',
				);
			}
			flush();
			return uncovered.length ? 1 : 0;
		}

		if (!opts.baseRef) throw new Error('--mode pr needs --base-ref');
		const changed = new Set(git(opts.root, ['diff', '--name-only', opts.baseRef, 'HEAD']).split('\n').filter(Boolean));
		const inputs = [...changed].filter(isDependencyInput).sort();
		md.push(`Fails on an advisory this PR introduces at CVSS >= ${THRESHOLD.toFixed(1)}: present at HEAD, absent at \`${opts.baseRef}\`.`, '');
		if (inputs.length === 0) {
			md.push('No dependency input changed, so this PR cannot introduce an advisory. Nothing was scanned.', '');
			flush();
			return 0;
		}
		md.push(`Dependency inputs changed: ${inputs.map((p) => `\`${p}\``).join(', ')}.`, '');

		const head = scan(opts.scanner, opts.root, join(work, 'head.json'), log, opts.delayMs);
		if (!head.ok) return outage('HEAD', head);
		baseDir = join(work, 'base');
		git(opts.root, ['worktree', 'add', '--quiet', '--detach', baseDir, opts.baseRef]);
		const base = scan(opts.scanner, baseDir, join(work, 'base.json'), log, opts.delayMs);
		if (!base.ok) return outage('base', base);

		const headFindings = findingsOf(head.report, opts.root);
		const baseFindings = findingsOf(base.report, baseDir);
		const added = introduced(headFindings, baseFindings);
		const failing = added.filter(blocks);
		const ign = judgeIgnores(readIgnores(opts.root), readIgnores(baseDir), headFindings, changed, today);
		const uncovered = uncoveredSources(head.report, opts.root);

		md.push(`HEAD: ${headFindings.length} advisory group(s). Base: ${baseFindings.length}. Introduced: ${added.length}.`, '');
		md.push(`### Introduced at or above ${THRESHOLD.toFixed(1)} (fails)`, '', ...table(failing));
		md.push('### Introduced below the threshold or unscored (does not fail)', '', ...table(added.filter((f) => !blocks(f))));
		const waivers = [...ign.errors.map((e) => `- **fails:** ${e}`), ...ign.warnings.map((w) => `- ${w}`), ...ign.notes.map((n) => `- ${n}`)];
		if (waivers.length) md.push('### Waivers (osv-scanner.toml)', '', ...waivers, '');

		for (const f of failing) {
			log(
				`::error::This PR introduces ${f.name}@${f.version} (${f.ecosystem}) with ${f.ids.join(' / ')} at ${fmt(f.score)} (${f.basis}) in ${f.lockfiles.join(', ')}. ` +
					'Upgrade past the advisory, or add an ignore by ID with a reason and ignoreUntil to the osv-scanner.toml beside the lockfile.',
			);
		}
		for (const f of added.filter((x) => x.score === null)) {
			log(`::warning::This PR introduces ${f.name}@${f.version} with ${f.ids.join(' / ')}, which carries no severity; read it.`);
		}
		for (const e of ign.errors) log(`::error::${e}`);
		for (const w of ign.warnings) log(`::warning::${w}`);
		for (const u of uncovered) {
			log(`::error::osv-scanner read ${u}, which DEPENDENCY_INPUT in scripts/check_dependency_advisories.mjs does not match. Add its basename there.`);
		}
		flush();
		return failing.length || ign.errors.length || uncovered.length ? 1 : 0;
	} catch (err) {
		log(`::error::dependency-advisories could not run: ${/** @type {Error} */ (err).message}`);
		md.push(`**Setup failure:** ${/** @type {Error} */ (err).message}`, '');
		flush();
		return 2;
	} finally {
		if (baseDir && existsSync(baseDir)) spawnSync('git', ['worktree', 'remove', '--force', baseDir], { cwd: opts.root });
		rmSync(work, { recursive: true, force: true });
	}
}

/** @param {string[]} argv */
export function parseArgs(argv) {
	/** @type {Record<string, string>} */
	const a = {};
	for (let i = 0; i < argv.length; i++) {
		const m = /^--([a-z-]+)$/.exec(argv[i]);
		if (!m || i + 1 >= argv.length) throw new Error(`unexpected argument ${argv[i]}`);
		a[m[1]] = argv[++i];
	}
	if (!a.scanner) throw new Error('--scanner is required');
	if (a.mode !== 'pr' && a.mode !== 'report') throw new Error('--mode must be pr or report');
	return { scanner: a.scanner, mode: /** @type {'pr' | 'report'} */ (a.mode), baseRef: a['base-ref'], root: a.root ?? process.cwd() };
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
	let code = 2;
	try {
		const opts = parseArgs(process.argv.slice(2));
		const summaryFile = process.env.GITHUB_STEP_SUMMARY;
		code = run({ ...opts, summary: summaryFile ? (t) => appendFileSync(summaryFile, t) : undefined });
	} catch (err) {
		console.log(`::error::dependency-advisories: ${/** @type {Error} */ (err).message}`);
	}
	process.exit(code);
}
