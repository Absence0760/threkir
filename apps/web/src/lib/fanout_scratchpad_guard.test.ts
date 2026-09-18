// A fan-out command's lanes all inherit ONE scratchpad path. The harness keys
// it on the session, and a subagent inherits the spawning session's path
// unchanged — measured 2026-09-18, a plain subagent and one running with
// `isolation: "worktree"` both reported the parent's exact path. So the repo's
// standing answer to parallel safety, "give the lane its own worktree", buys a
// private tree and index and nothing else: ten lanes still write into one
// directory. In round 46 that directory held `data.ts.bak`, `run_narrow.ts.bak`
// and twenty more files from lanes that never spoke to each other, and a lane's
// mutation-test restore copied a SIBLING lane's `data.ts` into its worktree.
//
// The durable fix is a per-lane subdirectory plus a restore idiom that needs no
// save file at all, and prose alone would drift back: the bug is a class, so a
// sibling command written next month repeats it. This guard derives the fan-out
// set from the command bodies rather than listing it, so a new fan-out command
// is covered the day it is written and cannot be forgotten in a registry.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const repo = resolve(import.meta.dirname, '../../../..');

function tracked(pathspec: string): string[] {
	return execFileSync('git', ['ls-files', '--', pathspec], { cwd: repo, encoding: 'utf-8' })
		.split('\n')
		.filter(Boolean);
}

function read(file: string): string {
	return readFileSync(resolve(repo, file), 'utf-8');
}

// A command fans lanes out when one of its own lines both instructs a spawn and
// says the spawned things run at the same time. Both halves must land on the
// SAME line: "spawn the code-reviewer" (one agent) and "read the code yourself
// in parallel" (no agent) each appear in commands that fan nothing out.
const SPAWN = /\b(spawn|spawns|fan out|fans out|fan-out|dispatch|dispatches)\b/i;
const CONCURRENT = /\b(in parallel|concurrently|in a single message|in one message|in a single dispatch)\b/i;

function fansOutLanes(file: string): boolean {
	// README.md indexes the commands, it is not one — it describes other files'
	// fan-outs and instructs nobody.
	if (file.endsWith('/README.md')) return false;
	return read(file)
		.split('\n')
		.some((line) => SPAWN.test(line) && CONCURRENT.test(line));
}

const commands = tracked('.claude/commands').filter((f) => f.endsWith('.md'));
const fanOut = commands.filter(fansOutLanes);

test('the fan-out set is derived from the commands, and the derivation still finds them', () => {
	assert.ok(commands.length >= 20, `expected the command tree, found ${commands.length} files`);
	assert.ok(
		fanOut.length >= 5,
		`the fan-out derivation matched only ${fanOut.length} commands (${fanOut.join(', ')}). ` +
			`Either the commands stopped fanning out, or they reworded the spawn instruction past ` +
			`SPAWN/CONCURRENT — widen the patterns, do not lower this floor.`,
	);
});

test('every fan-out command gives its lanes a private scratchpad subdirectory', () => {
	const missing: string[] = [];
	for (const file of fanOut) {
		const src = read(file);
		if (!/scratchpad/i.test(src) || !src.includes('<scratchpad>/<lane-slug>/')) {
			missing.push(`${file} (no per-lane <scratchpad>/<lane-slug>/ instruction)`);
		}
	}
	assert.deepEqual(
		missing,
		[],
		`these commands spawn lanes that share one scratchpad without telling each lane where ` +
			`its own files go: ${missing.join('; ')}. Lanes then collide on bare filenames. Add the ` +
			`per-lane scratchpad paragraph the sibling fan-out commands carry.`,
	);
});

test('every fan-out command prescribes the restore that needs no save file', () => {
	const missing = fanOut.filter((f) => !read(f).includes('git checkout HEAD -- '));
	assert.deepEqual(
		missing,
		[],
		`these commands fan out lanes without naming the safe restore idiom: ${missing.join('; ')}. ` +
			`A \`cp x x.bak\` save/restore collides across lanes and \`cp -i\` declines silently, so the ` +
			`restore returns a sibling's file; \`git checkout HEAD -- <path>\` removes the save file ` +
			`entirely.`,
	);
});

test('no agent or command instruction writes to a fixed path in the shared /tmp', () => {
	// A named path under /tmp is shared by every session on the machine, not
	// merely every lane of one round, so a fixed filename there is the same
	// defect one scope wider. `/tmp` with no filename after it is prose (the
	// prohibition itself), not a write target.
	const offenders: string[] = [];
	for (const file of tracked('.claude').filter((f) => f.endsWith('.md'))) {
		for (const m of read(file).matchAll(/\/tmp\/[A-Za-z0-9_.-]+/g)) {
			offenders.push(`${file} -> ${m[0]}`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`these instructions hand an agent a fixed path in the machine-wide /tmp: ` +
			`${offenders.join('; ')}. Two sessions running the same flow overwrite each other's ` +
			`file and neither is told. Write under <scratchpad>/<lane-slug>/ instead.`,
	);
});

test('CLAUDE.md still carries the rule the commands point at', () => {
	const src = read('CLAUDE.md');
	const section = src.slice(src.indexOf('## Working alongside other Claude sessions'));
	assert.ok(section.length > 0, 'CLAUDE.md lost its cross-session section');

	assert.match(
		section.slice(0, section.indexOf('\n## ', 1)),
		/<scratchpad>\/<lane-slug>\//,
		'CLAUDE.md § Working alongside other Claude sessions must keep the per-lane scratchpad ' +
			'rule — every fan-out command links here for it.',
	);
	assert.match(
		section.slice(0, section.indexOf('\n## ', 1)),
		/git checkout HEAD -- /,
		'CLAUDE.md § Working alongside other Claude sessions must keep the `.bak`-free restore ' +
			'idiom — it is the half that removes the failure mode rather than isolating it.',
	);
	assert.match(
		section.slice(0, section.indexOf('\n## ', 1)),
		/Never `git stash`/,
		'the stash prohibition is load-bearing and predates this rule — do not drop it while ' +
			'editing the section.',
	);
});
