// Unit tests for scripts/check_dependency_advisories.mjs.
//
// Run: `node --test scripts/check_dependency_advisories.test.mjs`
//
// The end-to-end cases run `run()` in a throwaway git repository under
// `os.tmpdir()` against a fake scanner that copies the scanned tree's
// `fake-report.json` to its `--output-file`, so the base and head reports come
// from the two commits exactly as osv-scanner's would.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	THRESHOLD,
	blocks,
	cvss3BaseScore,
	findingsOf,
	introduced,
	isDependencyInput,
	isExpired,
	judgeIgnores,
	parseIgnores,
	roundUp,
	run,
	scan,
	scoreGroup,
	uncoveredSources,
} from './check_dependency_advisories.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// ------------------------------------------------------------ CVSS v3

test('CVSS v3.1 base scores match the published calculator', () => {
	const cases = [
		['CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H', 9.8],
		['CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N', 7.5],
		['CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N', 5.9],
		['CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N', 6.1],
		['CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H', 7.8],
		['CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H', 7.2],
		['CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H', 10.0],
		['CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H', 9.9],
		['CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L', 5.3],
		['CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H', 9.8],
	];
	for (const [vector, want] of cases) assert.equal(cvss3BaseScore(String(vector)), want, String(vector));
});

test('temporal metrics are ignored, no impact scores 0, and anything not a v3 vector is null', () => {
	assert.equal(cvss3BaseScore('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H/E:U/RL:O'), 9.8);
	assert.equal(cvss3BaseScore('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N'), 0);
	assert.equal(cvss3BaseScore('CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N'), null);
	assert.equal(cvss3BaseScore('AV:N/AC:L/Au:N/C:P/I:P/A:P'), null);
	assert.equal(cvss3BaseScore('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/C:H/I:H/A:H'), null, 'no scope');
	assert.equal(cvss3BaseScore('CVSS:3.1/AV:X/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'), null, 'unknown value');
	assert.equal(cvss3BaseScore('CVSS:3.1/AV:N/AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'), null, 'duplicate metric');
});

test('Roundup is the spec function, not Math.ceil on a float', () => {
	assert.equal(roundUp(4.0), 4.0);
	assert.equal(roundUp(4.02), 4.1);
	assert.equal(roundUp(4.000000001), 4.0);
});

// ------------------------------------------------------------ severity rule

/** @param {string} id @param {string} vector @param {object} [extra] */
const v3 = (id, vector, extra = {}) => ({ id, severity: [{ type: 'CVSS_V3', score: vector }], ...extra });

test('a CVSS v3 vector is scored here', () => {
	const s = scoreGroup({ ids: ['A'], max_severity: '' }, [v3('A', 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N')]);
	assert.deepEqual(s, { score: 7.5, basis: 'CVSS v3' });
});

test('a v4-only advisory takes osv-scanner max_severity, and the higher of the two wins', () => {
	const v4 = { id: 'A', severity: [{ type: 'CVSS_V4', score: 'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N' }] };
	assert.deepEqual(scoreGroup({ ids: ['A'], max_severity: '9.3' }, [v4]), { score: 9.3, basis: 'CVSS (osv-scanner)' });
	const mixed = scoreGroup({ ids: ['A', 'B'], max_severity: '9.1' }, [v3('A', 'CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N'), v4]);
	assert.deepEqual(mixed, { score: 9.1, basis: 'CVSS (osv-scanner)' });
});

test('with no number, the GitHub advisory label is the fallback', () => {
	const g = { ids: ['GHSA-x'], max_severity: '' };
	assert.deepEqual(scoreGroup(g, [{ id: 'GHSA-x', database_specific: { severity: 'HIGH' } }]), { score: 7.0, basis: 'GHSA label' });
	assert.deepEqual(scoreGroup(g, [{ id: 'GHSA-x', database_specific: { severity: 'CRITICAL' } }]), { score: 9.0, basis: 'GHSA label' });
	assert.deepEqual(scoreGroup(g, [{ id: 'GHSA-x', database_specific: { severity: 'MODERATE' } }]), { score: 4.0, basis: 'GHSA label' });
});

test('an advisory with no score and no label is unscored and never blocks', () => {
	const s = scoreGroup({ ids: ['RUSTSEC-2026-0110'], max_severity: '' }, [{ id: 'RUSTSEC-2026-0110', database_specific: /** @type {any} */ ({ license: 'CC0-1.0' }) }]);
	assert.deepEqual(s, { score: null, basis: 'unscored' });
	assert.equal(blocks(/** @type {any} */ ({ score: null })), false);
});

test('the gate is CVSS 7.0 inclusive', () => {
	assert.equal(THRESHOLD, 7.0);
	assert.equal(blocks(/** @type {any} */ ({ score: 7.0 })), true);
	assert.equal(blocks(/** @type {any} */ ({ score: 6.9 })), false);
});

// ------------------------------------------------------------ findings and the diff

/** @param {string} name @param {string} version @param {any[]} vulns @param {any[]} [groups] */
const pkg = (name, version, vulns, groups) => ({ package: { name, version, ecosystem: 'npm' }, vulnerabilities: vulns, groups });
/** @param {string} root @param {Array<[string, any[]]>} sources */
const report = (root, sources) => ({ results: sources.map(([path, packages]) => ({ source: { path: join(root, path), type: 'lockfile' }, packages })) });

test('findings are one per package, version and advisory group, with repo-relative lockfiles', () => {
	const r = report('/w', [
		[
			'pnpm-lock.yaml',
			[
				pkg('a', '1.0.0', [v3('GHSA-1', 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H', { aliases: ['CVE-1'] }), v3('CVE-1', 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H')], [
					{ ids: ['GHSA-1', 'CVE-1'], aliases: ['CVE-1', 'GHSA-1'], max_severity: '9.8' },
				]),
				{ package: { name: 'clean', version: '1.0.0', ecosystem: 'npm' } },
			],
		],
		['apps/x/package-lock.json', [pkg('a', '1.0.0', [v3('GHSA-1', 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H')], [{ ids: ['GHSA-1', 'CVE-1'], max_severity: '9.8' }])]],
	]);
	const f = findingsOf(r, '/w');
	assert.equal(f.length, 1);
	assert.deepEqual(f[0].ids, ['CVE-1', 'GHSA-1']);
	assert.deepEqual(f[0].lockfiles, ['pnpm-lock.yaml', 'apps/x/package-lock.json']);
	assert.equal(f[0].score, 9.8);
});

test('a package with advisories but no groups gets one group per advisory', () => {
	const f = findingsOf(report('/w', [['Cargo.lock', [pkg('c', '0.1.0', [{ id: 'RUSTSEC-1' }, { id: 'RUSTSEC-2' }])]]]), '/w');
	assert.deepEqual(f.map((x) => x.ids[0]).sort(), ['RUSTSEC-1', 'RUSTSEC-2']);
});

/** @param {string} name @param {string} version @param {string[]} ids @param {string} [ecosystem] */
const F = (name, version, ids, ecosystem = 'npm') => ({ ecosystem, name, version, ids, aliases: ids, lockfiles: ['l'], score: 9, basis: 'x' });
/** @param {readonly import('./check_dependency_advisories.mjs').Finding[]} fs */
const named = (fs) => fs.map((f) => `${f.ecosystem}:${f.name}@${f.version}:${f.ids.join(',')}`);

test('introduced keeps only head groups none of whose ids is on that package at the base', () => {
	const base = [F('a', '1.0.0', ['GHSA-1']), F('b', '2.0.0', ['GHSA-2'])];
	const head = [F('a', '1.0.0', ['CVE-1', 'GHSA-1']), F('c', '1.0.0', ['GHSA-3']), F('a', '1.0.0', ['GHSA-9'])];
	assert.deepEqual(named(introduced(head, base)), ['npm:c@1.0.0:GHSA-3', 'npm:a@1.0.0:GHSA-9']);
});

test('bumping an advised package to a release the same advisory still covers introduces nothing', () => {
	const base = [F('b', '2.0.0', ['GHSA-2'])];
	assert.deepEqual(named(introduced([F('b', '2.0.1', ['GHSA-2'])], base)), []);
	assert.deepEqual(named(introduced([F('b', '2.0.1', ['CVE-2', 'GHSA-2'])], base)), []);
});

test('a package clean at the base and advised at the head is introduced, whatever the version', () => {
	const base = [F('a', '1.0.0', ['GHSA-1'])];
	assert.deepEqual(named(introduced([F('b', '2.0.1', ['GHSA-2'])], base)), ['npm:b@2.0.1:GHSA-2']);
	// Same advisory id on another package, or the same name in another ecosystem, is not "known".
	assert.deepEqual(named(introduced([F('z', '1.0.0', ['GHSA-1'])], base)), ['npm:z@1.0.0:GHSA-1']);
	assert.deepEqual(named(introduced([F('a', '1.0.0', ['GHSA-1'], 'PyPI')], base)), ['PyPI:a@1.0.0:GHSA-1']);
});

// ------------------------------------------------------------ dependency inputs

test('every lockfile the tree holds today is a dependency input, and docs are not', () => {
	for (const p of [
		'apps/custom_watch/Cargo.lock',
		'apps/graph_cycle/go.mod',
		'apps/job_worker/go.sum',
		'apps/mobile_ios/ios/Podfile.lock',
		'apps/mobile_ios/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
		'apps/custom_watch/sim/shell_harness/shell_harness.csproj',
		'deno.lock',
		'package-lock.json',
		'pnpm-lock.yaml',
		'pubspec.lock',
		'apps/web/package.json',
		'apps/custom_watch/osv-scanner.toml',
		'scripts/check_dependency_advisories.mjs',
		'.github/workflows/ci.yml',
	]) {
		assert.equal(isDependencyInput(p), true, p);
	}
	for (const p of ['README.md', 'docs/ops/deployment.md', 'apps/web/src/app.ts', '.github/workflows/security.yml']) {
		assert.equal(isDependencyInput(p), false, p);
	}
});

test('a scanned file the input pattern misses is reported', () => {
	const r = report('/w', [['pnpm-lock.yaml', []], ['tools/thing.lockx', []]]);
	assert.deepEqual(uncoveredSources(r, '/w'), ['tools/thing.lockx']);
});

// ------------------------------------------------------------ ignores

test('both committed osv-scanner.toml files parse to dated, reasoned entries', () => {
	for (const file of ['osv-scanner.toml', 'apps/custom_watch/osv-scanner.toml']) {
		const entries = parseIgnores(readFileSync(join(REPO_ROOT, file), 'utf8'), file);
		assert.ok(entries.length >= 1, file);
		for (const e of entries) {
			assert.match(String(e.id), /^(GHSA|RUSTSEC|CVE)-/, file);
			assert.match(String(e.ignoreUntil), /^\d{4}-\d{2}-\d{2}$/, file);
			assert.equal(e.hasReason, true, file);
		}
	}
});

test('the parser reads single-line strings, quoted dates, and leaves other tables alone', () => {
	const text = [
		'[[PackageOverrides]]',
		'name = "x"',
		'ignore = true',
		'',
		'[[IgnoredVulns]]',
		"id = 'GHSA-a' # trailing comment",
		'ignoreUntil = "2027-01-02T00:00:00Z"',
		'reason = "short"',
		'',
		'[[IgnoredVulns]]',
		'id = "GHSA-b"',
		'reason = """',
		'"""',
	].join('\n');
	const entries = parseIgnores(text, 'apps/y/osv-scanner.toml');
	assert.deepEqual(
		entries.map(({ id, ignoreUntil, hasReason, dir, line }) => ({ id, ignoreUntil, hasReason, dir, line })),
		[
			{ id: 'GHSA-a', ignoreUntil: '2027-01-02', hasReason: true, dir: 'apps/y', line: 5 },
			{ id: 'GHSA-b', ignoreUntil: null, hasReason: false, dir: 'apps/y', line: 10 },
		],
	);
});

test('an ignore expires at the start of its ignoreUntil day, as osv-scanner applies it', () => {
	const e = /** @type {any} */ ({ ignoreUntil: '2027-05-09' });
	assert.equal(isExpired(e, '2027-05-08'), false);
	assert.equal(isExpired(e, '2027-05-09'), true);
});

/** @param {Partial<import('./check_dependency_advisories.mjs').IgnoreEntry>} over */
const entry = (over) => ({ file: 'osv-scanner.toml', dir: '', line: 6, id: 'GHSA-1', ignoreUntil: '2027-05-09', hasReason: true, ...over });
const finding = { ecosystem: 'npm', name: 'a', version: '1.0.0', ids: ['GHSA-1'], aliases: ['CVE-1', 'GHSA-1'], lockfiles: ['pnpm-lock.yaml'], score: 9.8, basis: 'CVSS v3' };

test('an expired ignore fails a PR that changes its lockfile, and only warns otherwise', () => {
	const today = '2027-06-01';
	const hit = judgeIgnores([entry({})], [entry({})], [finding], new Set(['pnpm-lock.yaml']), today);
	assert.equal(hit.errors.length, 1);
	assert.match(hit.errors[0], /expired on 2027-05-09.*This PR changes pnpm-lock\.yaml/);
	const miss = judgeIgnores([entry({})], [entry({})], [finding], new Set(['apps/web/src/x.ts']), today);
	assert.deepEqual(miss.errors, []);
	assert.equal(miss.warnings.length, 1);
	const report = judgeIgnores([entry({})], [], [finding], null, today);
	assert.deepEqual(report.errors, []);
	assert.equal(report.warnings.length, 1);
});

test('an expired ignore counts only lockfiles in its own directory, and matches by alias', () => {
	const nested = { ...finding, lockfiles: ['apps/z/package-lock.json'] };
	const r = judgeIgnores([entry({ id: 'CVE-1' })], [], [nested], new Set(['apps/z/package-lock.json']), '2027-06-01');
	assert.deepEqual(r.errors, []);
	assert.match(r.warnings[0], /matches nothing scanned; delete it/);
});

test('a waiver missing its date or reason fails the PR that edits the file, and warns otherwise', () => {
	const bad = [entry({ ignoreUntil: null }), entry({ id: 'GHSA-2', hasReason: false })];
	const edited = judgeIgnores(bad, [], [], new Set(['osv-scanner.toml']), '2026-11-10');
	assert.equal(edited.errors.length, 2);
	assert.match(edited.errors[0], /no ignoreUntil/);
	assert.match(edited.errors[1], /no reason/);
	const untouched = judgeIgnores(bad, bad, [], new Set(['pnpm-lock.yaml']), '2026-11-10');
	assert.deepEqual(untouched.errors, []);
	assert.equal(untouched.warnings.length, 2);
});

test('a waiver the PR adds is listed, and one expiring within 30 days warns', () => {
	const r = judgeIgnores([entry({ ignoreUntil: '2026-11-20' })], [], [], new Set(['osv-scanner.toml']), '2026-11-10');
	assert.deepEqual(r.errors, []);
	assert.match(r.notes[0], /adds an ignore for GHSA-1 until 2026-11-20/);
	assert.match(r.warnings[0], /expires in 10 day/);
});

// ------------------------------------------------------------ the scanner wrapper

const FAKE = `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
const out = args[args.indexOf('--output-file') + 1];
if (process.env.FAKE_ARGS) fs.writeFileSync(process.env.FAKE_ARGS, JSON.stringify(args));
const counter = process.env.FAKE_COUNTER;
let n = 0;
if (counter) { n = fs.existsSync(counter) ? Number(fs.readFileSync(counter, 'utf8')) : 0; fs.writeFileSync(counter, String(n + 1)); }
const fail = Number(process.env.FAKE_FAIL_TIMES || 0);
const failOn = process.env.FAKE_FAIL_ON;
if ((n < fail && (!failOn || process.cwd().includes(failOn)))) {
  fs.writeFileSync(out, '{"results": []}');
  console.error('unable to fetch OSV database: no offline version of the OSV database is available');
  process.exit(127);
}
if (process.env.FAKE_GARBAGE) { fs.writeFileSync(out, 'not json'); process.exit(0); }
const src = path.join(process.cwd(), 'fake-report.json');
if (!fs.existsSync(src)) process.exit(128);
fs.writeFileSync(out, fs.readFileSync(src, 'utf8').split('__ROOT__').join(process.cwd()));
process.exit(JSON.parse(fs.readFileSync(out, 'utf8')).results.some((r) => r.packages.some((p) => (p.vulnerabilities || []).length)) ? 1 : 0);
`;

function sandbox() {
	const dir = mkdtempSync(join(tmpdir(), 'dep-adv-test-'));
	const scanner = join(dir, 'fake-osv');
	writeFileSync(scanner, FAKE);
	chmodSync(scanner, 0o755);
	return { dir, scanner };
}

/** @param {Record<string, string | undefined>} env @param {() => void} fn */
function withEnv(env, fn) {
	const saved = Object.fromEntries(Object.keys(env).map((k) => [k, process.env[k]]));
	Object.assign(process.env, env);
	try {
		fn();
	} finally {
		for (const [k, v] of Object.entries(saved)) {
			if (v === undefined) delete process.env[k];
			else process.env[k] = v;
		}
	}
}

test('an outage exit is retried once and then succeeds', () => {
	const { dir, scanner } = sandbox();
	try {
		writeFileSync(join(dir, 'fake-report.json'), '{"results": []}');
		/** @type {string[]} */
		const log = [];
		withEnv({ FAKE_COUNTER: join(dir, 'n'), FAKE_FAIL_TIMES: '1', FAKE_ARGS: join(dir, 'args.json') }, () => {
			const r = scan(scanner, dir, join(dir, 'out.json'), (l) => log.push(l), 0);
			assert.equal(r.ok, true);
		});
		assert.match(log[0], /^::warning::osv-scanner exited 127 .*unable to fetch OSV database.*retrying once/);
		const args = JSON.parse(readFileSync(join(dir, 'args.json'), 'utf8'));
		for (const flag of ['--offline-vulnerabilities', '--download-offline-databases', '--no-call-analysis=all', '--all-packages']) {
			assert.ok(args.includes(flag), flag);
		}
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('two outage exits fail even though the report reads clean, and unreadable JSON fails too', () => {
	const { dir, scanner } = sandbox();
	try {
		withEnv({ FAKE_COUNTER: join(dir, 'n'), FAKE_FAIL_TIMES: '2' }, () => {
			const r = scan(scanner, dir, join(dir, 'out.json'), () => {}, 0);
			assert.equal(r.ok, false);
			assert.equal(/** @type {any} */ (r).status, 127);
		});
		withEnv({ FAKE_GARBAGE: '1' }, () => {
			assert.equal(scan(scanner, dir, join(dir, 'out.json'), () => {}, 0).ok, false);
		});
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('exit 128 with no report is an empty tree, not a failure', () => {
	const { dir, scanner } = sandbox();
	try {
		const r = scan(scanner, dir, join(dir, 'out.json'), () => {}, 0);
		assert.deepEqual(r, { ok: true, report: { results: [] } });
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

// ------------------------------------------------------------ run(), end to end

const VULN = { id: 'GHSA-new', severity: [{ type: 'CVSS_V3', score: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H' }] };
const LOW = { id: 'GHSA-low', severity: [{ type: 'CVSS_V3', score: 'CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N' }] };
/** @param {Array<[string, string, object[]]>} pkgs */
const fakeReport = (pkgs, lockfile = 'Cargo.lock') =>
	JSON.stringify({
		results: [
			{
				source: { path: `__ROOT__/${lockfile}`, type: 'lockfile' },
				packages: pkgs.map(([name, version, vulns]) => ({
					package: { name, version, ecosystem: 'crates.io' },
					vulnerabilities: vulns,
					groups: vulns.map((v) => ({ ids: [/** @type {any} */ (v).id], max_severity: '' })),
				})),
			},
		],
	});

/**
 * A repo whose first commit is the base and second the head.
 * @param {Record<string, string>} baseFiles
 * @param {Record<string, string>} headFiles
 */
function repo(baseFiles, headFiles) {
	const box = sandbox();
	const root = join(box.dir, 'repo');
	const g = (/** @type {string[]} */ ...a) => execFileSync('git', ['-c', 'user.email=t@example.invalid', '-c', 'user.name=t', ...a], { cwd: root, stdio: 'pipe' });
	execFileSync('git', ['init', '--quiet', root]);
	for (const [files, msg] of /** @type {const} */ ([[baseFiles, 'base'], [headFiles, 'head']])) {
		for (const [p, text] of Object.entries(files)) writeFileSync(join(root, p), text);
		g('add', '-A');
		g('commit', '--quiet', '--allow-empty', '-m', msg);
	}
	return { ...box, root };
}

/** @param {ReturnType<typeof repo>} r @param {Partial<Parameters<typeof run>[0]>} over */
function go(r, over = {}) {
	/** @type {string[]} */
	const log = [];
	let summary = '';
	const code = run({ scanner: r.scanner, mode: 'pr', root: r.root, baseRef: 'HEAD^1', today: '2026-11-10', delayMs: 0, log: (l) => log.push(l), summary: (t) => (summary += t), ...over });
	return { code, log, summary };
}

const LOCK0 = 'version = 3\n';
const LOCK1 = 'version = 3\n# bumped\n';

test('a PR that adds a CVSS 9.8 advisory fails, naming the package', () => {
	const r = repo(
		{ 'Cargo.lock': LOCK0, 'fake-report.json': fakeReport([['ok', '1.0.0', []]]) },
		{ 'Cargo.lock': LOCK1, 'fake-report.json': fakeReport([['ok', '1.0.0', []], ['bad', '0.1.0', [VULN]]]) },
	);
	try {
		const out = go(r);
		assert.equal(out.code, 1);
		assert.match(out.log.join('\n'), /::error::This PR introduces bad@0\.1\.0 \(crates\.io\) with GHSA-new at 9\.8 \(CVSS v3\) in Cargo\.lock/);
		assert.match(out.summary, /Introduced: 1\./);
		const trees = execFileSync('git', ['worktree', 'list'], { cwd: r.root, encoding: 'utf8' }).trim().split('\n');
		assert.equal(trees.length, 1, 'the base worktree is removed');
	} finally {
		rmSync(r.dir, { recursive: true, force: true });
	}
});

test('an advisory already at the base, or one below 7.0, does not fail the PR', () => {
	const r = repo(
		{ 'Cargo.lock': LOCK0, 'fake-report.json': fakeReport([['old', '1.0.0', [VULN]]]) },
		{ 'Cargo.lock': LOCK1, 'fake-report.json': fakeReport([['old', '1.0.0', [VULN]], ['meh', '2.0.0', [LOW]]]) },
	);
	try {
		const out = go(r);
		assert.equal(out.code, 0, out.log.join('\n'));
		assert.match(out.summary, /Introduced: 1\./);
		assert.match(out.summary, /\| 5\.9 \| CVSS v3 \| meh \|/);
	} finally {
		rmSync(r.dir, { recursive: true, force: true });
	}
});

test('a PR that changes no dependency input scans nothing and passes, even during an outage', () => {
	const r = repo({ 'Cargo.lock': LOCK0, 'README.md': 'a' }, { 'README.md': 'b' });
	try {
		withEnv({ FAKE_COUNTER: join(r.dir, 'n'), FAKE_FAIL_TIMES: '9' }, () => {
			const out = go(r);
			assert.equal(out.code, 0);
			assert.match(out.summary, /Nothing was scanned/);
		});
		assert.equal(existsSync(join(r.dir, 'n')), false, 'the scanner was never invoked');
	} finally {
		rmSync(r.dir, { recursive: true, force: true });
	}
});

test('a base-tree outage is exit 2 with an error that says re-run', () => {
	const r = repo({ 'Cargo.lock': LOCK0, 'fake-report.json': fakeReport([]) }, { 'Cargo.lock': LOCK1 });
	try {
		withEnv({ FAKE_COUNTER: join(r.dir, 'n'), FAKE_FAIL_TIMES: '9', FAKE_FAIL_ON: 'dep-advisories-' }, () => {
			const out = go(r);
			assert.equal(out.code, 2);
			assert.match(out.log.join('\n'), /::error::osv-scanner failed twice while scanning the base tree \(exit 127.*re-run the job/);
		});
	} finally {
		rmSync(r.dir, { recursive: true, force: true });
	}
});

test('report mode lists every advisory, fails on none, and fails on a scanned file the pattern misses', () => {
	const r = repo({ 'Cargo.lock': LOCK0 }, { 'fake-report.json': fakeReport([['old', '1.0.0', [VULN]]]) });
	try {
		const out = go(r, { mode: 'report', baseRef: undefined });
		assert.equal(out.code, 0, out.log.join('\n'));
		assert.match(out.summary, /Report only/);
		assert.match(out.summary, /\| 9\.8 \| CVSS v3 \| old \|/);
	} finally {
		rmSync(r.dir, { recursive: true, force: true });
	}
	const odd = repo({ 'x.lockx': 'a' }, { 'fake-report.json': fakeReport([['old', '1.0.0', []]], 'x.lockx') });
	try {
		const out = go(odd, { mode: 'report', baseRef: undefined });
		assert.equal(out.code, 1);
		assert.match(out.log.join('\n'), /::error::osv-scanner read x\.lockx, which DEPENDENCY_INPUT/);
	} finally {
		rmSync(odd.dir, { recursive: true, force: true });
	}
});

test('an expired ignore beside a lockfile the PR changes fails it', () => {
	const toml = '[[IgnoredVulns]]\nid = "GHSA-new"\nignoreUntil = 2026-11-01\nreason = "r"\n';
	const rep = fakeReport([['bad', '0.1.0', [VULN]]]);
	const r = repo({ 'Cargo.lock': LOCK0, 'osv-scanner.toml': toml, 'fake-report.json': rep }, { 'Cargo.lock': LOCK1 });
	try {
		const out = go(r);
		assert.equal(out.code, 1);
		assert.match(out.log.join('\n'), /::error::osv-scanner\.toml:1: the ignore for GHSA-new expired on 2026-11-01.*This PR changes Cargo\.lock/);
	} finally {
		rmSync(r.dir, { recursive: true, force: true });
	}
});

test('the gate and the advisory scan pin the same osv-scanner release and sha256', () => {
	/** @param {string} file */
	const pins = (file) => {
		const text = readFileSync(join(REPO_ROOT, '.github/workflows', file), 'utf8');
		const version = [...text.matchAll(/^\s*OSV_SCANNER_VERSION:\s*(\S+)\s*$/gm)].map((m) => m[1]);
		const sha = [...text.matchAll(/^\s*OSV_SCANNER_SHA256:\s*([0-9a-f]{64})\s*$/gm)].map((m) => m[1]);
		assert.equal(version.length, 1, `${file} declares OSV_SCANNER_VERSION once`);
		assert.equal(sha.length, 1, `${file} declares OSV_SCANNER_SHA256 once`);
		return { version: version[0], sha: sha[0] };
	};
	assert.deepEqual(pins('ci.yml'), pins('supply-chain-scan.yml'));
});

test('a waiver a PR adds or changes may run at most 180 days past the run date', () => {
	const today = '2026-11-10';
	const lock = new Set(['osv-scanner.toml']);
	const at = judgeIgnores([entry({ ignoreUntil: '2027-05-09' })], [], [], lock, today);
	assert.deepEqual(at.errors, []);
	const over = judgeIgnores([entry({ ignoreUntil: '2027-05-10' })], [], [], lock, today);
	assert.equal(over.errors.length, 1);
	assert.match(over.errors[0], /181 days out.*at most 180 days.*on or before 2027-05-09.*renew it closer to expiry, with a reason/);
	const changedDate = judgeIgnores([entry({ ignoreUntil: '2099-01-01' })], [entry({})], [], lock, today);
	assert.equal(changedDate.errors.length, 1);
});

test('an unchanged far-out waiver and a removed one do not fail the cap', () => {
	const today = '2026-11-10';
	const lock = new Set(['osv-scanner.toml']);
	const far = entry({ ignoreUntil: '2099-01-01' });
	assert.deepEqual(judgeIgnores([far], [far], [], lock, today).errors, []);
	assert.deepEqual(judgeIgnores([], [far], [], lock, today).errors, []);
	assert.deepEqual(judgeIgnores([far], [], [], null, today).errors, []);
});

test('both committed waivers sit inside the 180-day cap as of 2026-11-10', () => {
	const entries = ['osv-scanner.toml', 'apps/custom_watch/osv-scanner.toml'].flatMap((f) =>
		parseIgnores(readFileSync(new URL(`../${f}`, import.meta.url), 'utf8'), f),
	);
	assert.equal(entries.length, 2);
	assert.deepEqual(judgeIgnores(entries, [], [], new Set(entries.map((e) => e.file)), '2026-11-10').errors, []);
});
