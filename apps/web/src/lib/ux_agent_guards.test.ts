// The UI/UX toolchain — the ui-polisher and ux-critic agents and the four
// commands that drive them — fails GREEN when it rots. An agent that
// cites a deleted token, class, component or route reports confidently
// against a tree that no longer has it, and nothing in CI notices because
// markdown compiles fine.
//
// The 2026-09-17 revision found ui-polisher claiming a five-item sidebar
// that had grown to seven, a `.page` padding pair that had become its own
// tokens, a brand mark the layout had stopped rendering, and a `ui_kit`
// widget roster of which not one of the four named widgets still lived
// there. The fix was structural — the agent now reads the contract out of
// the tree instead of transcribing it — and this guard holds that line by
// asserting the two properties the rewrite depends on.
//
// Scope is the whole `.claude` fleet, and it is DERIVED rather than listed:
// every tracked markdown file under `.claude/` is checked, so a new agent or
// command is covered by existing the moment it lands. A list would have to be
// remembered, and the thing this guard exists to catch is precisely what
// nobody remembers.
//
// It started narrower — the five UI/UX toolchain files, where a cited path is
// a DIRECTIVE ("read this before you edit") — and deliberately excluded the
// persona and audit agents, where a citation is sometimes a HYPOTHESIS
// ("`apps/osrm/` if it exists"). Eleven dead fleet-wide citations were filed
// rather than fixed at the time. Ten of them turned out to be ordinary rot
// with a live path to point at; the eleventh is a genuine conditional, and it
// is exempted by name with a reason below rather than by leaving the whole
// fleet unchecked. The exemption is staleness-checked in both directions.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repo = resolve(__dirname, '../../../..');

// The five files whose SECOND premise this suite also holds (Step 1 survives,
// no colour literal comes back). The fleet check below does not need a list;
// this one does, because it is about these files specifically.
const UX_TOOLCHAIN = [
	'.claude/agents/ui-polisher.md',
	'.claude/agents/ux-critic.md',
	'.claude/commands/polish-ui.md',
	'.claude/commands/ux-critique.md',
	'.claude/commands/ux-hunt.md',
	'.claude/commands/a11y-hunt.md',
];

// A citation the author explicitly hedged. The path is absent from the tree,
// the sentence says so, and failing it would assert something never claimed.
// Each entry names the file that may cite it and why the hedge is honest;
// both halves are checked for staleness below, so an exemption cannot outlive
// its reason in either direction.
const CONDITIONAL: { path: string; file: string; why: string }[] = [
	{
		path: 'apps/osrm/',
		file: '.claude/commands/release-readiness.md',
		why: 'release-readiness accepts `osrm` as a release target and scopes it to "`apps/osrm/` if it exists". The sibling OSRM service is planned, not built — docs/backend/backend_scaling.md records `OSRM_URL` unset in fly.toml and map_match completing as a no-op "until the sibling osrm app deploys" — so the hedge is the honest sentence, not rot. Drop this entry when apps/osrm/ lands, or when the command stops offering the target.',
	},
];

// A citation is a repo path when it is rooted at a real top-level directory.
// Everything else in backticks is a command, a class name, a token, or prose.
const ROOTED = /^(apps|packages|docs|scripts|infra|bin|\.claude|\.github)\//;

// Placeholders (`apps/web/src/routes/<slug>/+page.svelte`), symbol anchors
// (`types.ts:TrackPoint`, `data.ts#fetchFollowingFeed`) and the throwaway
// specs these agents write themselves (`_polish_before.spec.ts`) are not
// claims that a file exists today.
function isClaim(p: string): boolean {
	if (!ROOTED.test(p)) return false;
	if (/[<>{}*?|\s]|\.\.\./.test(p)) return false;
	if (p.includes('#') || p.includes(':')) return false;
	if (basename(p).startsWith('_')) return false;
	return true;
}

function citations(file: string): string[] {
	const src = readFileSync(resolve(repo, file), 'utf-8');
	return [...src.matchAll(/`([^`\n]+)`/g)].map((m) => m[1].trim()).filter(isClaim);
}

// Liveness is decided against git, not the filesystem, so the answer is the
// same in a fresh clone as on a workstation that has run the suites. A path
// is live when it is TRACKED, or when it is IGNORED — an ignored path is one
// the repo deliberately does not carry but the flow still names, such as the
// Playwright storage states globalSetup writes into `tests-e2e/.auth/`.
// Checking `existsSync` instead would have passed those on a machine that had
// run the e2e suite and failed them everywhere else.
const tracked = new Set(
	execFileSync('git', ['ls-files'], { cwd: repo, encoding: 'utf-8', maxBuffer: 64 << 20 })
		.split('\n')
		.filter(Boolean),
);
const trackedDirs = new Set<string>();
for (const f of tracked) {
	const parts = f.split('/');
	for (let i = 1; i < parts.length; i++) trackedDirs.add(parts.slice(0, i).join('/'));
}

function isLive(p: string): boolean {
	const clean = p.replace(/\/$/, '');
	if (tracked.has(clean) || trackedDirs.has(clean)) return true;
	try {
		execFileSync('git', ['check-ignore', '-q', '--', clean], { cwd: repo });
		return true;
	} catch {
		return false;
	}
}

// Derived, not listed: the fleet is whatever `.claude` markdown git carries.
const fleet = [...tracked].filter((f) => f.startsWith('.claude/') && f.endsWith('.md')).sort();

test('every repo path the .claude agent and command fleet cites is still tracked (or deliberately ignored)', () => {
	const dead: string[] = [];
	let checked = 0;
	const exempted = new Set<string>();

	for (const file of fleet) {
		for (const p of citations(file)) {
			checked++;
			if (isLive(p)) continue;
			const waived = CONDITIONAL.find((c) => c.path === p && c.file === file);
			if (waived) {
				exempted.add(`${waived.file} -> ${waived.path}`);
				continue;
			}
			dead.push(`${file} -> ${p}`);
		}
	}

	// A floor, not a census. It catches the citation matcher silently ceasing
	// to match — which would turn this whole guard green against any tree.
	assert.ok(
		checked >= 600,
		`expected the fleet to cite the tree heavily, found only ${checked} paths across ` +
			`${fleet.length} files — the citation matcher has probably stopped matching`,
	);
	assert.deepEqual(
		dead,
		[],
		`these agent/command files point at paths git no longer tracks, so the agent ` +
			`will read nothing and proceed on memory: ${dead.join('; ')}. Update the ` +
			`citation to where the thing lives now — do not delete the pointer. If the ` +
			`citation is genuinely conditional ("if it exists"), add it to CONDITIONAL ` +
			`with the reason.`,
	);

	// An exemption that no longer applies is an assertion nobody is making.
	const stale = CONDITIONAL.filter((c) => !exempted.has(`${c.file} -> ${c.path}`)).map(
		(c) =>
			`${c.file} -> ${c.path}: ` +
			(isLive(c.path)
				? 'the path is live now, so the hedge is obsolete — drop the exemption and let the guard hold it'
				: `${c.file} no longer cites it (or no longer exists) — drop the exemption`),
	);
	assert.deepEqual(stale, [], `stale CONDITIONAL entries: ${stale.join('; ')}`);
});

test('the UI/UX toolchain files the second guard depends on are all still present', () => {
	for (const file of UX_TOOLCHAIN) {
		assert.ok(
			fleet.includes(file),
			`${file} is listed in UX_TOOLCHAIN but git does not track it — the toolchain ` +
				`was renamed or removed, so the citation and premise guards below are checking nothing.`,
		);
	}
});

// The rewrite's whole premise: ui-polisher carries judgment and looks the
// facts up. A regression here looks like someone helpfully pasting the token
// list back in, which reads as an improvement and rots within a month.
test('ui-polisher makes the agent read the contract rather than transcribing it', () => {
	const src = readFileSync(resolve(repo, '.claude/agents/ui-polisher.md'), 'utf-8');

	assert.match(
		src,
		/^## Step 1 — Load the contract/m,
		'ui-polisher must keep the Step 1 "Load the contract" section — it is the ' +
			'mechanism that replaced the transcribed inventory.',
	);

	for (const source of [
		'docs/architecture/conventions.md',
		'apps/web/src/app.css',
		'apps/web/src/routes/+layout.svelte',
		'packages/ui_kit/lib/src/theme',
		'apps/web/src/lib/i18n/locales',
	]) {
		assert.ok(
			src.includes(source),
			`ui-polisher must send the agent to ${source} rather than restating what it contains.`,
		);
	}

	// Hex literals are the tell. The palettes live in app.css, app_theme.dart
	// and the watch theme files; a hex in the agent is a copy that will drift
	// out of step with all three the next time a colour moves.
	const hexes = [...src.matchAll(/0x[0-9A-Fa-f]{8}|#[0-9A-Fa-f]{6}\b/g)].map((m) => m[0]);
	assert.deepEqual(
		hexes,
		[],
		`ui-polisher must not carry colour literals (${hexes.join(', ')}) — it reads the ` +
			`palette from the theme files, which is the only copy that can be correct.`,
	);
});
