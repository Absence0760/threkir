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
// Scope is deliberate. It covers the files where a cited path is a
// DIRECTIVE ("read this before you edit"), not the persona and audit agents
// where a citation is often a HYPOTHESIS ("`apps/web/src/lib/sentry.ts` if
// present", "`apps/osrm/` if it exists"). A guard that failed on a
// conditional citation would be asserting something the author never
// claimed. Fleet-wide dead citations are tracked in
// docs/product/followups.md instead.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repo = resolve(__dirname, '../../../..');

const UX_TOOLCHAIN = [
	'.claude/agents/ui-polisher.md',
	'.claude/agents/ux-critic.md',
	'.claude/commands/polish-ui.md',
	'.claude/commands/ux-critique.md',
	'.claude/commands/ux-hunt.md',
	'.claude/commands/a11y-hunt.md',
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

test('every repo path the UX toolchain cites is still tracked (or deliberately ignored)', () => {
	const dead: string[] = [];
	let checked = 0;

	for (const file of UX_TOOLCHAIN) {
		assert.ok(existsSync(resolve(repo, file)), `${file} is listed in UX_TOOLCHAIN but missing.`);
		for (const p of citations(file)) {
			checked++;
			if (!isLive(p)) dead.push(`${file} -> ${p}`);
		}
	}

	assert.ok(checked >= 40, `expected the toolchain to cite the tree, found only ${checked} paths`);
	assert.deepEqual(
		dead,
		[],
		`these agent/command files point at paths git no longer tracks, so the agent ` +
			`will read nothing and proceed on memory: ${dead.join('; ')}. Update the ` +
			`citation to where the thing lives now — do not delete the pointer.`,
	);
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
