import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

/**
 * A context's init scripts also run in each new page's initial `about:blank`,
 * whose opaque origin has no storage, so a hand-rolled script that writes
 * `localStorage` throws a SecurityError there and the crash net
 * (`fixtures/test.ts`) records a pageerror for a page the app never ran on.
 * `setStorageOnLoad` / `acceptCookieConsent` in `fixtures/helpers.ts` skip
 * that document; every storage init script goes through them.
 *
 * A file here must still hold an init script that touches storage, or the
 * entry is stale and fails below.
 */
const STORAGE_INIT_ALLOWED: Record<string, string> = {
	'fixtures/helpers.ts': 'setStorageOnLoad itself, which guards the about: document'
};

const SCANNED = ['.ts', '.mjs'];
const STORAGE = /\b(?:localStorage|sessionStorage)\b/;
const IDENT = /^\s*([A-Za-z_$][\w$]*)\s*(?:,|$)/;

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

/**
 * The index just past the bracket that closes the one at `open`, skipping
 * string and template literals. `-1` when it never closes.
 */
function closeOf(code: string, open: number): number {
	let depth = 0;
	for (let i = open; i < code.length; i++) {
		const c = code[i];
		if (c === "'" || c === '"' || c === '`') {
			for (i++; i < code.length && code[i] !== c; i++) if (code[i] === '\\') i++;
			continue;
		}
		if (c === '(' || c === '{' || c === '[') depth++;
		else if (c === ')' || c === '}' || c === ']') {
			depth--;
			if (depth === 0) return i + 1;
		}
	}
	return -1;
}

/** The text of a same-file `function name` / `const name =` declaration. */
function declarationOf(code: string, name: string): string | null {
	const decl = new RegExp(`(?:\\bfunction\\s+${name}\\s*\\(|\\b(?:const|let|var)\\s+${name}\\s*(?::[^=]+)?=)`);
	const m = decl.exec(code);
	if (!m) return null;
	const start = m.index + m[0].length;
	const end = code.slice(start).search(/\n\S|;\s*\n/);
	const brace = code.indexOf('{', start);
	if (brace !== -1 && (end === -1 || brace < start + end)) {
		const close = closeOf(code, brace);
		return code.slice(m.index, close === -1 ? code.length : close);
	}
	return code.slice(m.index, end === -1 ? code.length : start + end);
}

/**
 * The 1-based line of every `addInitScript(...)` call in `source` whose
 * script touches web storage — written inline, or a function the call names
 * that is declared in the same file.
 */
export function storageInitScripts(source: string): number[] {
	const code = stripComments(source);
	const lines: number[] = [];
	for (const m of code.matchAll(/\.addInitScript\s*\(/g)) {
		const open = m.index + m[0].length - 1;
		const close = closeOf(code, open);
		const args = code.slice(open + 1, close === -1 ? code.length : close - 1);
		const ident = IDENT.exec(args)?.[1];
		const body = ident ? (declarationOf(code, ident) ?? '') : args;
		if (STORAGE.test(body)) lines.push(code.slice(0, m.index).split('\n').length);
	}
	return lines;
}

const SELF = fileURLToPath(import.meta.url);

function storageInitFiles(): Map<string, number[]> {
	const out = new Map<string, number[]>();
	for (const file of scannedSources(E2E_ROOT)) {
		if (file === SELF) continue;
		const lines = storageInitScripts(readFileSync(file, 'utf8'));
		if (lines.length) out.set(relPath(file), lines);
	}
	return out;
}

test('no init script touches web storage except through setStorageOnLoad', () => {
	const offenders = [...storageInitFiles()]
		.filter(([rel]) => !(rel in STORAGE_INIT_ALLOWED))
		.map(([rel, lines]) => `${rel}:${lines.join(',')}`);
	assert.deepEqual(
		offenders,
		[],
		'These init scripts read or write web storage directly, so on a new page’s initial ' +
			'about:blank they throw a SecurityError the crash net reports. Use setStorageOnLoad ' +
			'or acceptCookieConsent from tests-e2e/fixtures/helpers instead: ' +
			offenders.join(' ')
	);
});

test('every allowlist entry still names a file with a storage init script', () => {
	const files = storageInitFiles();
	const stale = Object.keys(STORAGE_INIT_ALLOWED).filter(
		(rel) => !existsSync(join(E2E_ROOT, rel)) || !files.has(rel)
	);
	assert.deepEqual(
		stale,
		[],
		`These STORAGE_INIT_ALLOWED entries are gone or no longer touch storage; delete them: ${stale.join(' ')}`
	);
	for (const [rel, reason] of Object.entries(STORAGE_INIT_ALLOWED)) {
		assert.ok(reason.trim().length > 0, `${rel} needs a reason`);
	}
});

test('the reader sees storage in an inline script, a named one and either store', () => {
	assert.deepEqual(
		storageInitScripts("await context.addInitScript(() => {\n\tlocalStorage.setItem('a', 'b');\n});"),
		[1]
	);
	assert.deepEqual(
		storageInitScripts("x;\nawait page.addInitScript(() => window.localStorage.removeItem('a'));"),
		[2]
	);
	assert.deepEqual(
		storageInitScripts("await page.addInitScript((k) => sessionStorage.setItem(k, '1'), key);"),
		[1]
	);
	assert.deepEqual(
		storageInitScripts(
			"function seed() {\n\tlocalStorage.setItem('locale', 'de');\n}\nawait ctx.addInitScript(seed);"
		),
		[4]
	);
	assert.deepEqual(
		storageInitScripts(
			"const seed = () => localStorage.clear();\nawait ctx.addInitScript(seed);"
		),
		[2]
	);
});

test('the reader passes scripts that leave storage alone', () => {
	assert.deepEqual(storageInitScripts("await setStorageOnLoad(page, { local: { locale: 'de' } });"), []);
	assert.deepEqual(
		storageInitScripts(
			"await page.addInitScript(() => {\n\tObject.defineProperty(navigator, 'share', { value: undefined });\n});\nlocalStorage;"
		),
		[]
	);
	assert.deepEqual(
		storageInitScripts("await page.addInitScript(() => {\n\t// localStorage is not touched here\n});"),
		[]
	);
	assert.deepEqual(
		storageInitScripts(
			"function observe() {\n\twindow.__seen = [];\n}\nawait ctx.addInitScript(observe, ')');\nlocalStorage.clear();"
		),
		[]
	);
});
