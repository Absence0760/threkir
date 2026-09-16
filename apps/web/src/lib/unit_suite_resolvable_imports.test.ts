// `npm run test:unit` is raw `tsx --test` over `src/**/*.test.ts`. tsx resolves
// path aliases from tsconfig, and `apps/web/tsconfig.json` gets `$lib` / `$app`
// only by extending `./.svelte-kit/tsconfig.json`, which `svelte-kit sync`
// generates and CI never runs before this job. So an aliased import in a unit
// test passes in a worktree where some earlier `svelte-check` happened to
// generate that file, and fails in CI with ERR_MODULE_NOT_FOUND. Relative
// imports resolve either way.
//
// The alias does not have to be in the test file to break it. tsx loads every
// module the test reaches, so a relative import of a module that itself imports
// `$lib/format/time` fails the same way — which is how `demo_preview.ts` went
// red on PR #915 while this guard, then reading only the test files' own import
// lines, passed. The check is therefore over the modules each suite actually
// LOADS, found by following its relative imports.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';

import { stripComments } from './core/strip_comments';

const WEB_ROOT = resolve(import.meta.dirname, '..', '..');

const GLOB_TAIL = '/**/*.test.ts';

/// The roots `test:unit` globs, read from the script itself so a glob added
/// there is a root walked here without anyone restating it. A glob of any
/// other shape throws rather than being skipped, because a skipped root is a
/// tree this guard stops reading while still reporting a pass.
function unitSuiteRoots(): string[] {
	const pkg = JSON.parse(readFileSync(join(WEB_ROOT, 'package.json'), 'utf-8'));
	const script: string = pkg.scripts['test:unit'];
	return [...script.matchAll(/'([^']+)'/g)].map(([, glob]) => {
		if (!glob.endsWith(GLOB_TAIL)) {
			throw new Error(`test:unit glob '${glob}' is not <root>${GLOB_TAIL}; teach unitSuiteRoots its shape`);
		}
		return join(WEB_ROOT, glob.slice(0, -GLOB_TAIL.length));
	});
}

function unitTestFiles(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) out.push(...unitTestFiles(full));
		else if (entry.name.endsWith('.test.ts')) out.push(full);
	}
	return out;
}

interface ImportSite {
	specifier: string;
	typeOnly: boolean;
}

/// Every module specifier `source` loads at runtime or names in a type-only
/// statement, which tsx erases.
///
/// Anchored at column 0 with no leading whitespace, because only a real module
/// specifier counts: `map_surface_basemap_guard.test.ts` carries an aliased
/// import inside a quoted fixture line it asserts about, and that line is
/// indented. Prettier keeps every import statement flush-left. The clause may
/// span lines — `[^;'"]` crosses newlines — and cannot run past the statement,
/// because an import clause holds no quote and no semicolon.
function importSites(source: string): ImportSite[] {
	const stripped = stripComments(source);
	const out: ImportSite[] = [];
	for (const m of stripped.matchAll(
		/^(?:import|export)\s+(type\s+)?(?:[^;'"]*?\sfrom\s+)?['"]([^'"]+)['"]/gm
	)) {
		out.push({ specifier: m[2], typeOnly: m[1] !== undefined });
	}
	for (const m of stripped.matchAll(/\bimport\(\s*['"]([^'"]+)['"]\s*\)/g)) {
		out.push({ specifier: m[1], typeOnly: false });
	}
	return out;
}

const ALIAS = /^\$(?:lib|app|env)(?:\/|$)/;

function resolveRelative(from: string, specifier: string): string | null {
	const base = resolve(dirname(from), specifier);
	for (const candidate of [base, `${base}.ts`, `${base}.js`, join(base, 'index.ts')]) {
		try {
			if (statSync(candidate).isFile() && /\.(ts|js|mjs)$/.test(candidate)) return candidate;
		} catch {
			// not this shape; try the next
		}
	}
	return null;
}

/// Every module the unit suite loads, each with the first test that reaches it.
function loadedModules(): Map<string, string> {
	const reachedFrom = new Map<string, string>();
	for (const root of unitSuiteRoots()) {
		for (const testFile of unitTestFiles(root)) {
			const queue = [testFile];
			while (queue.length > 0) {
				const file = queue.pop()!;
				if (reachedFrom.has(file)) continue;
				reachedFrom.set(file, testFile);
				for (const { specifier, typeOnly } of importSites(readFileSync(file, 'utf-8'))) {
					if (typeOnly || !specifier.startsWith('.')) continue;
					const next = resolveRelative(file, specifier);
					if (next) queue.push(next);
				}
			}
		}
	}
	return reachedFrom;
}

test('importSites reads a multi-line clause and skips a type-only one', () => {
	const sites = importSites(
		[
			`import {`,
			`\tformatDuration,`,
			`\tformatPace`,
			`} from '$lib/format/time';`,
			`import type { TrackPoint } from '$lib/types';`,
			`export { x } from './x';`,
			`import './side_effect';`,
			`const lazy = await import('../lazy');`,
			`\timport { indented } from '$lib/format/pace_format';`,
			`export const label = 'from';`,
		].join('\n')
	);
	assert.deepEqual(sites, [
		{ specifier: '$lib/format/time', typeOnly: false },
		{ specifier: '$lib/types', typeOnly: true },
		{ specifier: './x', typeOnly: false },
		{ specifier: './side_effect', typeOnly: false },
		{ specifier: '../lazy', typeOnly: false },
	]);
});

test('the suite roots come from the test:unit script', () => {
	const roots = unitSuiteRoots();
	assert.ok(
		roots.map((r) => relative(WEB_ROOT, r)).includes('src'),
		`test:unit roots read as ${JSON.stringify(roots)}`
	);
	for (const root of roots) assert.ok(statSync(root).isDirectory(), `${root} is not a directory`);
});

test('no module the unit suite loads imports through a SvelteKit path alias', () => {
	const modules = loadedModules();
	const offenders: string[] = [];
	for (const [file, testFile] of modules) {
		const aliased = importSites(readFileSync(file, 'utf-8')).filter(
			(s) => !s.typeOnly && ALIAS.test(s.specifier)
		);
		if (aliased.length === 0) continue;
		const via = file === testFile ? '' : `, loaded by ${relative(WEB_ROOT, testFile)}`;
		offenders.push(
			`${relative(WEB_ROOT, file)} (${aliased.map((s) => s.specifier).join(', ')}${via})`
		);
	}
	// A walk that stopped at the test files would report nothing here and pass
	// for the reason this test was widened.
	const testFiles = unitSuiteRoots().flatMap(unitTestFiles).length;
	assert.ok(
		modules.size > testFiles,
		`the walk loaded ${modules.size} modules for ${testFiles} test files — it is not following imports`
	);
	assert.deepEqual(
		offenders,
		[],
		`These modules are loaded by \`npm run test:unit\` and import through a ` +
			`SvelteKit alias, which resolves only after \`svelte-kit sync\` has written ` +
			`.svelte-kit/tsconfig.json. CI does not run it before the suite, so each ` +
			`fails there with ERR_MODULE_NOT_FOUND while passing locally. Use a ` +
			`relative import:\n  ` +
			offenders.join('\n  ')
	);
});
