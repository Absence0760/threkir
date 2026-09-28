#!/usr/bin/env node
// Guardrail: a cache one runner OS saves can never be restored on another.
//
// An `actions/cache` entry is matched by its key and by a "version" hashed
// from the step's `path` list, and the runner OS is in neither — so a Linux
// job and a macOS job caching the same `path` share one namespace, and a
// restore key is a PREFIX match across all of it. `build-mobile-ios` keyed its
// `~/.pub-cache` entry `pub-cache-macos-<hash>` to stay apart from
// `build-mobile-android`'s `pub-cache-<hash>`, but the Linux restore key was a
// bare `pub-cache-`, which matches both. Run 35642229273 restored the macOS
// cache onto the Linux runner, and because `~/.pub-cache/global_packages`
// records absolute host paths, `melos bootstrap` died with "Could not find
// bin/melos.dart in package melos". Keying one side apart is not enough; the
// OS has to be in every key and restore key that could reach the other side.
//
// The rule: when a cache `path` is saved by jobs on more than one runner OS —
// or by a composite action, which runs on whatever OS calls it — every key and
// every restore key for that path names `${{ runner.os }}`. A path cached on a
// single OS is left alone: CocoaPods only ever runs on macOS, and a key there
// needs no OS in it. decisions.md § 1702.
//
// A second rule, about what a key is computed FROM: every pattern handed to
// `hashFiles()` matches at least one tracked file. `hashFiles` hashes whatever
// its patterns do match and says nothing about the ones that match nothing, so
// a dead pattern leaves the key stable and the miss silent. `build-mobile-
// android`'s Gradle key hashed `apps/mobile_android/pubspec.lock`, which has
// never existed — the Flutter side is one pub workspace whose lockfile is at
// the root (decisions § 1661) — so a plugin bump never invalidated that cache.
// Matching follows `@actions/glob` as the runner uses it: dotfiles match, no
// brace or extglob expansion, and a pattern naming a directory covers the
// files under it. It reads `git ls-files`, so an untracked build output on a
// workstation cannot make a pattern look alive.
//
// Reads: `.github/workflows/*.yml` and `.github/actions/*/action.yml`.
// CI:  the `workflow-lint` job in .github/workflows/ci.yml.
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	ACTION_DIR,
	WORKFLOW_DIR,
	parseActionSteps,
	parseJobBlock,
	parseSteps,
	readActions,
	readWorkflows,
} from './check_ci_diagnostics.mjs';

/**
 * @typedef {{ name: string, text: string }} WorkflowFile
 * @typedef {{ file: string, line: number, owner: string, os: string, paths: string[], key: string | null, restoreKeys: string[] }} CacheStep
 */

/** An OS a composite action can run on: all of them. */
export const ANY_OS = '*';

const CACHE_USES = /^\s*(?:-\s+)?uses:\s*actions\/cache(?:\/restore|\/save)?@/m;
const RUNNER_OS = /\$\{\{\s*runner\.os\s*\}\}/;

/**
 * The runner OS a `runs-on` value selects, spelled as `runner.os` spells it.
 * An expression or an unknown label cannot be resolved, so it is treated as
 * possibly any OS — the conservative answer for a cache.
 * @param {string | null} runsOn
 */
export function osOf(runsOn) {
	if (runsOn === null) return ANY_OS;
	if (/\$\{\{/.test(runsOn)) return ANY_OS;
	if (/ubuntu/i.test(runsOn)) return 'Linux';
	if (/macos/i.test(runsOn)) return 'macOS';
	if (/windows/i.test(runsOn)) return 'Windows';
	return ANY_OS;
}

/**
 * A `with:` input's value: the inline scalar, or the lines of a `|` / `>`
 * block, each unquoted and with comments and blanks dropped.
 * @param {string} body the step's text
 * @param {string} input e.g. `path`, `key`, `restore-keys`
 * @returns {string[]}
 */
export function withInput(body, input) {
	const lines = body.split('\n');
	const at = lines.findIndex((l) => new RegExp(`^\\s*${input}:`).test(l));
	if (at === -1) return [];
	const head = lines[at];
	const indent = head.length - head.trimStart().length;
	const inline = head.slice(head.indexOf(':') + 1).replace(/\s+#.*$/, '').trim();
	const clean = (/** @type {string} */ v) => v.trim().replace(/^(['"])(.*)\1$/, '$2');
	if (inline && !/^[|>][+-]?$/.test(inline)) return [clean(inline)];
	/** @type {string[]} */
	const out = [];
	for (const line of lines.slice(at + 1)) {
		if (!line.trim()) continue;
		if (line.length - line.trimStart().length <= indent) break;
		if (line.trim().startsWith('#')) continue;
		out.push(clean(line));
	}
	return out;
}

/**
 * The runner OS each job of a workflow selects.
 * @param {string} text
 * @param {string} job
 */
function jobOs(text, job) {
	const block = parseJobBlock(text, job);
	const runsOn = block === null ? null : /^ {4}runs-on:\s*(.+?)\s*$/m.exec(block);
	return osOf(runsOn === null ? null : runsOn[1].replace(/\s+#.*$/, ''));
}

/**
 * Every `actions/cache` step in the workflows and composite actions.
 * @param {WorkflowFile[]} workflows
 * @param {WorkflowFile[]} actions
 * @returns {CacheStep[]}
 */
export function cacheSteps(workflows, actions) {
	/** @type {CacheStep[]} */
	const out = [];
	/**
	 * @param {string} file
	 * @param {import('./check_ci_diagnostics.mjs').Step} step
	 * @param {string} os
	 */
	const add = (file, step, os) => {
		if (!CACHE_USES.test(step.body)) return;
		const key = withInput(step.body, 'key');
		out.push({
			file,
			line: step.line,
			owner: step.job,
			os,
			paths: withInput(step.body, 'path').sort(),
			key: key.length === 0 ? null : key.join(' '),
			restoreKeys: withInput(step.body, 'restore-keys'),
		});
	};
	for (const wf of workflows) {
		for (const step of parseSteps(wf.text)) add(wf.name, step, jobOs(wf.text, step.job));
	}
	for (const action of actions) {
		for (const step of parseActionSteps(action.text, action.name)) add(action.name, step, ANY_OS);
	}
	return out;
}

/**
 * @param {CacheStep[]} steps
 * @returns {{ errors: string[], shared: number }}
 */
export function checkCacheKeys(steps) {
	/** @type {Map<string, CacheStep[]>} */
	const byPath = new Map();
	for (const s of steps) {
		const path = s.paths.join('\n');
		byPath.set(path, [...(byPath.get(path) ?? []), s]);
	}
	/** @type {string[]} */
	const errors = [];
	let shared = 0;
	for (const [path, group] of byPath) {
		const oses = new Set(group.map((s) => s.os));
		if (oses.size < 2 && !oses.has(ANY_OS)) continue;
		shared += 1;
		const where = [...oses].sort().join(', ');
		for (const s of group) {
			const at = `${s.file}:${s.line} (${s.owner})`;
			if (s.key === null || !RUNNER_OS.test(s.key)) {
				errors.push(
					`${at}: the key \`${s.key ?? '(none)'}\` for \`${path.replace(/\n/g, ', ')}\` does not name \${{ runner.os }}, ` +
						`and that path is cached on ${where}, so this entry is restorable on the other OS.`,
				);
			}
			for (const rk of s.restoreKeys) {
				if (RUNNER_OS.test(rk)) continue;
				errors.push(
					`${at}: the restore key \`${rk}\` for \`${path.replace(/\n/g, ', ')}\` does not name \${{ runner.os }}, ` +
						`and that path is cached on ${where}, so it can prefix-match the other OS's entry — ` +
						'the shape that restored a macOS ~/.pub-cache onto Linux in run 35642229273.',
				);
			}
		}
	}
	return { errors, shared };
}

/**
 * A `hashFiles()` glob as an anchored regex over a repo-relative path.
 * @param {string} glob
 */
export function globToRegExp(glob) {
	const segments = glob.replace(/^\.\//, '').split('/');
	let out = '';
	segments.forEach((seg, i) => {
		const last = i === segments.length - 1;
		if (seg === '**') {
			out += last ? '.*' : '(?:[^/]+/)*';
			return;
		}
		for (let j = 0; j < seg.length; j++) {
			const c = seg[j];
			const close = c === '[' ? seg.indexOf(']', j + 2) : -1;
			if (c === '*') out += '[^/]*';
			else if (c === '?') out += '[^/]';
			else if (close !== -1) {
				out += `[${seg.slice(j + 1, close).replace(/^!/, '^').replace(/\\/g, '\\\\')}]`;
				j = close;
			} else out += c.replace(/[.+^${}()|\\\]\[]/g, '\\$&');
		}
		if (!last) out += '/';
	});
	return new RegExp(`^${out}$`);
}

/**
 * @typedef {{ file: string, line: number, pattern: string | null, raw: string }} HashFilesPattern
 */

/**
 * Every `hashFiles()` argument in the workflows and composite actions, with
 * the line it is on. An argument that is not a string literal cannot be
 * checked and comes back as `pattern: null`.
 * @param {WorkflowFile[]} files
 * @returns {HashFilesPattern[]}
 */
export function hashFilesPatterns(files) {
	/** @type {HashFilesPattern[]} */
	const out = [];
	for (const { name, text } of files) {
		text.split('\n').forEach((line, i) => {
			if (line.trimStart().startsWith('#')) return;
			for (const call of line.matchAll(/hashFiles\(/g)) {
				let at = (call.index ?? 0) + call[0].length;
				for (;;) {
					while (line[at] === ' ' || line[at] === ',') at++;
					if (at >= line.length || line[at] === ')') break;
					const lit = /^'((?:[^']|'')*)'/.exec(line.slice(at));
					if (lit === null) {
						const raw = /^[^,)]*/.exec(line.slice(at))?.[0] ?? '';
						out.push({ file: name, line: i + 1, pattern: null, raw });
						at += Math.max(raw.length, 1);
						continue;
					}
					out.push({ file: name, line: i + 1, pattern: lit[1].replace(/''/g, "'"), raw: lit[0] });
					at += lit[0].length;
				}
			}
		});
	}
	return out;
}

/**
 * @param {HashFilesPattern[]} patterns
 * @param {string[]} tracked repo-relative, `/`-separated
 * @returns {string[]}
 */
export function checkHashFilesPatterns(patterns, tracked) {
	const candidates = new Set(tracked);
	for (const f of tracked) {
		for (let d = f.lastIndexOf('/'); d > 0; d = f.lastIndexOf('/', d - 1)) candidates.add(f.slice(0, d));
	}
	/** @type {string[]} */
	const errors = [];
	for (const p of patterns) {
		const at = `${p.file}:${p.line}`;
		if (p.pattern === null) {
			errors.push(`${at}: hashFiles() is given \`${p.raw}\`, which is not a string literal, so what it matches cannot be checked. Name the files literally.`);
			continue;
		}
		const re = globToRegExp(p.pattern.replace(/^!/, ''));
		if ([...candidates].some((c) => re.test(c))) continue;
		errors.push(
			`${at}: the hashFiles() pattern \`${p.pattern}\` matches no tracked file. hashFiles hashes the patterns that do match and ` +
				'says nothing about this one, so a change the key was meant to follow never invalidates the cache. ' +
				'Point it at the file that exists (the pub workspace has ONE pubspec.lock, at the repo root).',
		);
	}
	return errors;
}

/** @returns {string[]} */
function trackedFiles() {
	const root = join(dirname(fileURLToPath(import.meta.url)), '..');
	return execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf-8', maxBuffer: 256 * 1024 * 1024 })
		.split('\0')
		.filter(Boolean);
}

function main() {
	const workflows = readWorkflows(WORKFLOW_DIR);
	const actions = readActions(ACTION_DIR);
	const steps = cacheSteps(workflows, actions);
	if (steps.length === 0) {
		console.log('::error::check_cache_keys read no actions/cache step at all, which means its reader broke, not that the tree is clean.');
		return 1;
	}
	const patterns = hashFilesPatterns([...workflows, ...actions]);
	if (patterns.length === 0) {
		console.log('::error::check_cache_keys read no hashFiles() pattern at all, which means its reader broke, not that the tree is clean.');
		return 1;
	}
	const { errors, shared } = checkCacheKeys(steps);
	errors.push(...checkHashFilesPatterns(patterns, trackedFiles()));
	for (const e of errors) console.log(`::error::${e}`);
	if (errors.length > 0) return 1;
	console.log(
		`${steps.length} actions/cache step(s) read; ${shared} path(s) are cached on more than one runner OS, and every key and restore key for them names the OS. ` +
			`${patterns.length} hashFiles() pattern(s) read, each matching a tracked file.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
