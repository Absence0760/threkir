import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

/**
 * The source half of the crash net (`fixtures/test.ts`, decisions § 1944).
 * The fixture only watches a test that was declared with ITS `test`; one
 * declared with `@playwright/test`'s, or with `mock-route`'s (the layer the
 * net extends), runs unwatched and nothing says so. So no file in the tree
 * may take a runtime `test` from either, and every spec must take it from
 * `fixtures/test`. Type imports from `@playwright/test` (`Page`, `Locator`,
 * …) are fine, as are its other values (`expect`, `chromium`, `devices`).
 *
 * A spec that must not be watched does not belong here: it opts out with
 * `test.use({ crashNet: { off: '<reason>' } })`, which is reviewable in the
 * spec and annotated on every run. This list is for the fixture layers only.
 */
const DIRECT_IMPORT_ALLOWED: Record<string, string> = {
	'fixtures/mock-route.ts':
		'the base layer: it extends @playwright/test, and the crash net extends it in turn',
	'fixtures/test.ts': 'the crash net itself, built on mock-route’s test'
};

const SCANNED = ['.ts', '.mjs'];

function scannedSources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) scannedSources(full, out);
		else if (SCANNED.some((ext) => full.endsWith(ext))) out.push(full);
	}
	return out;
}

function relPath(file: string): string {
	return relative(E2E_ROOT, file).split(sep).join('/');
}

export interface TestImport {
	/** The module specifier as written. */
	from: string;
	/**
	 * `named` is `import { test }` (or `test as x`); `namespace` is `import * as x`;
	 * `default` is `import x from`, which is `test` for @playwright/test; `reexport`
	 * is `export { test } from` or `export * from`; `require` is a CommonJS load.
	 */
	shape: 'named' | 'namespace' | 'default' | 'reexport' | 'require';
}

const NAMED = /\bimport\s+(type\s+)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/g;
const NAMESPACE = /\bimport\s+(?:[\w$]+\s*,\s*)?\*\s+as\s+\w+\s+from\s*['"]([^'"]+)['"]/g;
const DEFAULT = /\bimport\s+(?!type\s)([\w$]+)\s*(?:,\s*(?:\{[^}]*\}|\*\s+as\s+\w+))?\s*from\s*['"]([^'"]+)['"]/g;
const REEXPORT_NAMED = /\bexport\s+(type\s+)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/g;
const REEXPORT_ALL = /\bexport\s+\*\s+(?:as\s+\w+\s+)?from\s*['"]([^'"]+)['"]/g;
const REQUIRE = /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g;

function namesTest(list: string): boolean {
	return list
		.split(',')
		.map((s) => s.trim())
		.filter((s) => s && !s.startsWith('type '))
		.map((s) => s.split(/\s+as\s+/)[0].trim())
		.includes('test');
}

/** Every runtime import of a `test` binding, whatever module it names. */
export function runtimeTestImports(source: string): TestImport[] {
	const code = stripComments(source);
	const found: TestImport[] = [];
	for (const m of code.matchAll(NAMED)) {
		if (!m[1] && namesTest(m[2])) found.push({ from: m[3], shape: 'named' });
	}
	for (const m of code.matchAll(NAMESPACE)) found.push({ from: m[1], shape: 'namespace' });
	for (const m of code.matchAll(DEFAULT)) found.push({ from: m[2], shape: 'default' });
	for (const m of code.matchAll(REEXPORT_NAMED)) {
		if (!m[1] && namesTest(m[2])) found.push({ from: m[3], shape: 'reexport' });
	}
	for (const m of code.matchAll(REEXPORT_ALL)) found.push({ from: m[1], shape: 'reexport' });
	for (const m of code.matchAll(REQUIRE)) found.push({ from: m[1], shape: 'require' });
	return found;
}

/** The repo-relative fixture a relative specifier names, extension optional. */
function resolvesTo(file: string, specifier: string, target: string): boolean {
	if (!specifier.startsWith('.')) return false;
	const abs = resolve(dirname(file), specifier).replace(/\.ts$/, '');
	return abs === join(E2E_ROOT, target);
}

/** A runtime `test` the crash net does not wrap. */
function unwatched(file: string, imp: TestImport): boolean {
	if (imp.from === '@playwright/test') return true;
	return resolvesTo(file, imp.from, 'fixtures/mock-route');
}

// This file's own reader cases are string literals shaped like the imports it bans.
const SELF = fileURLToPath(import.meta.url);

function directImporters(): Map<string, TestImport[]> {
	const out = new Map<string, TestImport[]>();
	for (const file of scannedSources(E2E_ROOT)) {
		if (file === SELF) continue;
		const imports = runtimeTestImports(readFileSync(file, 'utf8')).filter((i) => unwatched(file, i));
		if (imports.length) out.set(relPath(file), imports);
	}
	return out;
}

test('no file takes a runtime `test` from @playwright/test or mock-route', () => {
	const offenders = [...directImporters()]
		.filter(([rel]) => !(rel in DIRECT_IMPORT_ALLOWED))
		.map(([rel, imps]) => `${rel} (${imps.map((i) => i.from).join(', ')})`);
	assert.deepEqual(
		offenders,
		[],
		'These files declare tests the crash net never sees, so a page that crashes under them ' +
			"passes. Import `test` (and `expect`) from tests-e2e/fixtures/test instead; a spec that " +
			"must crash opts out with test.use({ crashNet: { off: '<reason>' } }): " +
			offenders.join(' ')
	);
});

test('every spec takes `test` from the crash net', () => {
	const offenders: string[] = [];
	for (const file of scannedSources(E2E_ROOT)) {
		if (!file.endsWith('.spec.ts')) continue;
		const fromNet = runtimeTestImports(readFileSync(file, 'utf8')).some((i) =>
			resolvesTo(file, i.from, 'fixtures/test')
		);
		if (!fromNet) offenders.push(relPath(file));
	}
	assert.deepEqual(
		offenders,
		[],
		`These specs import no \`test\` from tests-e2e/fixtures/test: ${offenders.join(' ')}`
	);
});

test('every allowlist entry still names a file that imports directly', () => {
	const importers = directImporters();
	const stale = Object.keys(DIRECT_IMPORT_ALLOWED).filter(
		(rel) => !existsSync(join(E2E_ROOT, rel)) || !importers.has(rel)
	);
	assert.deepEqual(
		stale,
		[],
		`These DIRECT_IMPORT_ALLOWED entries are gone or no longer import \`test\` directly; delete them: ${stale.join(' ')}`
	);
	for (const [rel, reason] of Object.entries(DIRECT_IMPORT_ALLOWED)) {
		assert.ok(reason.trim().length > 0, `${rel} needs a reason`);
	}
});

test('the import reader tells a runtime `test` from a type and from other names', () => {
	assert.deepEqual(runtimeTestImports("import { expect, test } from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'named' }
	]);
	assert.deepEqual(runtimeTestImports("import { test as base, expect } from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'named' }
	]);
	assert.deepEqual(runtimeTestImports("import * as pw from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'namespace' }
	]);
	assert.deepEqual(runtimeTestImports("import type { test } from '@playwright/test';"), []);
	assert.deepEqual(runtimeTestImports("import { type test, expect } from '@playwright/test';"), []);
	assert.deepEqual(runtimeTestImports("import { expect, type Page } from '@playwright/test';"), []);
	assert.deepEqual(runtimeTestImports("import { testInfo } from './x';"), []);
	assert.deepEqual(runtimeTestImports("// import { test } from '@playwright/test';"), []);
	assert.deepEqual(
		runtimeTestImports("import {\n\texpect,\n\ttest\n} from '@playwright/test';"),
		[{ from: '@playwright/test', shape: 'named' }]
	);
});

test('the import reader sees the shapes that bind `test` without naming it in braces', () => {
	assert.deepEqual(runtimeTestImports("import test from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'default' }
	]);
	assert.deepEqual(runtimeTestImports("import test, { expect } from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'default' }
	]);
	assert.deepEqual(runtimeTestImports("import base, * as pw from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'namespace' },
		{ from: '@playwright/test', shape: 'default' }
	]);
	assert.deepEqual(runtimeTestImports("export { test, expect } from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'reexport' }
	]);
	assert.deepEqual(runtimeTestImports("export { test as base } from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'reexport' }
	]);
	assert.deepEqual(runtimeTestImports("export * from '@playwright/test';"), [
		{ from: '@playwright/test', shape: 'reexport' }
	]);
	assert.deepEqual(runtimeTestImports("const { test } = require('@playwright/test');"), [
		{ from: '@playwright/test', shape: 'require' }
	]);
	assert.deepEqual(runtimeTestImports("export type { test } from '@playwright/test';"), []);
	assert.deepEqual(runtimeTestImports("export { expect } from '@playwright/test';"), []);
	assert.deepEqual(runtimeTestImports("import type test from '@playwright/test';"), []);
});

test('the scan still finds the tree it is scanning', () => {
	// An empty scan passes every assertion above in silence. A floor, not a
	// count, so adding or deleting a spec does not touch this file.
	const specs = scannedSources(E2E_ROOT).filter((f) => f.endsWith('.spec.ts'));
	assert.ok(specs.length > 400, `the scan found only ${specs.length} specs`);
});
