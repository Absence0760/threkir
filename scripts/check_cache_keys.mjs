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
// Reads: `.github/workflows/*.yml` and `.github/actions/*/action.yml`.
// CI:  the `workflow-lint` job in .github/workflows/ci.yml.
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

function main() {
	const steps = cacheSteps(readWorkflows(WORKFLOW_DIR), readActions(ACTION_DIR));
	if (steps.length === 0) {
		console.log('::error::check_cache_keys read no actions/cache step at all, which means its reader broke, not that the tree is clean.');
		return 1;
	}
	const { errors, shared } = checkCacheKeys(steps);
	for (const e of errors) console.log(`::error::${e}`);
	if (errors.length > 0) return 1;
	console.log(
		`${steps.length} actions/cache step(s) read; ${shared} path(s) are cached on more than one runner OS, and every key and restore key for them names the OS.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
