// Source-scan guard: the plan engine stays out of the download every route
// pays for.
//
// The root layout, the client hooks and everything they import statically
// end up in the chunks a reader fetches before any page renders. Twice a
// one-line static import put the plan code there: `core/data.ts` reaching
// `training.ts` for a date helper (decisions § 2109, then again § 2215), and
// `format/units.svelte.ts` reaching `plan_nudges.ts` for a rounding rule,
// which brought the replan, volume-anchor, comeback and training-load
// modules with it (§ 2215). Each cost every reader 5-10 KB gzipped, and the
// bundle budget only saw a total that had grown, with nothing pointing at the
// import. This walks the same static graph from the source, so the failure
// names the chain.
//
// When it fails: import the helper where it is used with `await import(...)`,
// or move it next to its route-level callers, rather than adding the module
// to SHELL_TRAINING_MODULES. A module belongs on that list only when it is
// small, imports nothing heavier, and the shell genuinely needs it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const LIB = join(SRC, 'lib');

const ROOTS = ['routes/+layout.svelte', 'routes/+layout.ts', 'hooks.client.ts'];

/// The training modules the shell is allowed to reach, each a leaf the data
/// layer reads for a row shape or a date shift.
const SHELL_TRAINING_MODULES = new Set([
	'lib/training/coach_load.ts',
	'lib/training/plan_bulk_ops.ts',
	'lib/training/plan_current.ts',
	'lib/training/relink_candidates.ts',
]);

const STATIC_IMPORT =
	/(?:^|[\n;])\s*(import|export)\s+(type\s+)?([^'"`;]*?)\s*from\s*['"]([^'"]+)['"]|(?:^|[\n;])\s*import\s*['"]([^'"]+)['"]/g;

function scriptOf(file: string, text: string): string {
	if (!file.endsWith('.svelte')) return text;
	return [...text.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script(?=[\s/>])[^>]*>/g)].map((m) => m[1]).join('\n');
}

function isTypeOnly(typeKeyword: string | undefined, clause: string): boolean {
	if (typeKeyword) return true;
	const braces = /^\{([\s\S]*)\}$/.exec(clause.trim());
	if (!braces) return false;
	const names = braces[1].split(',').map((s) => s.trim()).filter(Boolean);
	return names.length > 0 && names.every((n) => n.startsWith('type '));
}

function resolveSpecifier(from: string, spec: string): string | null {
	let base: string;
	if (spec.startsWith('#lib/')) base = join(LIB, spec.slice('#lib/'.length));
	else if (spec === '#lib') base = LIB;
	else if (spec.startsWith('$lib/')) base = join(LIB, spec.slice('$lib/'.length));
	else if (spec.startsWith('.')) base = resolve(dirname(from), spec);
	else return null;
	for (const candidate of [base, `${base}.ts`, `${base}.js`, join(base, 'index.ts')]) {
		if (existsSync(candidate) && !candidate.endsWith('/') && /\.(ts|js|svelte)$/.test(candidate)) {
			return candidate;
		}
	}
	return null;
}

/// Every source file statically reachable from the roots, with the importer
/// that first reached it, so a failure can print the whole chain.
function shellGraph(): Map<string, string | null> {
	const parent = new Map<string, string | null>();
	const queue: string[] = [];
	for (const root of ROOTS) {
		const abs = join(SRC, root);
		if (!existsSync(abs)) continue;
		parent.set(abs, null);
		queue.push(abs);
	}
	while (queue.length > 0) {
		const file = queue.shift()!;
		const text = scriptOf(file, readFileSync(file, 'utf8'));
		for (const m of text.matchAll(STATIC_IMPORT)) {
			const spec = m[4] ?? m[5];
			if (m[4] && isTypeOnly(m[2], m[3])) continue;
			const target = resolveSpecifier(file, spec);
			if (!target || parent.has(target)) continue;
			parent.set(target, file);
			queue.push(target);
		}
	}
	return parent;
}

function chain(parent: Map<string, string | null>, file: string): string {
	const out: string[] = [];
	for (let at: string | null = file; at; at = parent.get(at) ?? null) out.unshift(relative(SRC, at));
	return out.join(' -> ');
}

const graph = shellGraph();

test('the walk reaches the data layer and the units store, so an empty graph cannot pass', () => {
	const reached = new Set([...graph.keys()].map((f) => relative(SRC, f)));
	assert.ok(reached.has('lib/core/data.ts'), 'root layout no longer reaches core/data.ts statically');
	assert.ok(reached.has('lib/format/units.svelte.ts'), 'root layout no longer reaches format/units.svelte.ts');
});

test('no training module outside the allowlist is statically reachable from the root layout', () => {
	const offenders = [...graph.keys()]
		.filter((f) => relative(SRC, f).startsWith('lib/training/'))
		.filter((f) => !SHELL_TRAINING_MODULES.has(relative(SRC, f)))
		.map((f) => chain(graph, f));
	assert.deepEqual(offenders, [], `plan code in every route's download:\n  ${offenders.join('\n  ')}`);
});

test('every allowlisted training module is still reached, so the list cannot go stale', () => {
	const reached = new Set([...graph.keys()].map((f) => relative(SRC, f)));
	const stale = [...SHELL_TRAINING_MODULES].filter((m) => !reached.has(m));
	assert.deepEqual(stale, [], 'remove these from SHELL_TRAINING_MODULES');
});
