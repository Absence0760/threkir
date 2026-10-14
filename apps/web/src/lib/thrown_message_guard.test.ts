import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { stripComments, stripSvelteComments } from './core/strip_comments';

/**
 * Guard-rail: a caught value is formatted through `thrownMessage`
 * (`core/supabase_error.ts`), never by hand.
 *
 * The data layer used to throw PostgREST errors as they came (`if (error)
 * throw error`), and those are plain objects, not `Error`s. So the idiom
 * `e instanceof Error ? e.message : String(e)` — and its cousins `${e}`,
 * `String(e)`, `(e as Error).message`, `e?.message` — showed the reader
 * "[object Object]" (or nothing, or threw on `undefined.includes`) every time a
 * read failed at the database. § 1914 moved every site in `src/` onto the
 * helper; this file fails the PR on the next one.
 *
 * Since § 1917 the data layer throws `DbError`, a real `Error`, so
 * `e instanceof Error ? e.message : m('copy')` no longer falls back to the
 * surface's copy on a database failure — it prints "invalid invite token
 * (P0001)" where the page said "This invite link is invalid or expired". That
 * shape is banned too: `appErrorMessage(e) ?? m('copy')` keeps the old split,
 * `thrownMessage(e) || 'x'` is for where the detail is the point.
 *
 * What is banned, after comments are stripped:
 *   1. `x instanceof Error ? x.message : <anything>` anywhere;
 *   2. `(x as Error).message` / `(x as Error)?.message` anywhere;
 *   3. inside a `catch (x)` block or a `.catch((x) => …)` callback, the bare
 *      binding stringified — `String(x)`, `${x}` — or read as `x?.message` /
 *      an unguarded `x.message` (the `: any` binding that lets it compile).
 *
 * `e instanceof Error && e.message === REFUSAL` is NOT banned: it compares an
 * app-raised machine code, which a `DbError`'s message never equals.
 *
 * Invocation:
 *   npx tsx --test src/lib/thrown_message_guard.test.ts
 */

const libRoot = import.meta.dirname;
const webRoot = resolve(libRoot, '..', '..');
const srcRoot = resolve(webRoot, 'src');

/// Sites allowed to format a caught value by hand,
/// `path relative to apps/web` -> `[count, why]`. Only for a value that never
/// reaches a reader. Empty today; keep it that way unless a site truly is not
/// user-facing AND cannot use the helper.
const ALLOW: Record<string, [number, string]> = {};

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			sourceFiles(full, out);
			continue;
		}
		if (!/\.(ts|svelte)$/.test(entry.name)) continue;
		if (/\.test\.ts$/.test(entry.name)) continue;
		out.push(full);
	}
	return out;
}

/// Index just past the bracket that closes the one at `open`. Quoted strings
/// are skipped so a `'{'` literal does not unbalance the count; template text
/// is not, which is fine — its `${…}` holes balance themselves.
function matchClose(src: string, open: number): number {
	const o = src[open];
	const c = o === '{' ? '}' : ')';
	let depth = 0;
	for (let i = open; i < src.length; i++) {
		const ch = src[i];
		if (ch === "'" || ch === '"') {
			for (i++; i < src.length && src[i] !== ch && src[i] !== '\n'; i++) if (src[i] === '\\') i++;
			continue;
		}
		if (ch === o) depth++;
		else if (ch === c && --depth === 0) return i + 1;
	}
	return src.length;
}

function escape(s: string): string {
	return s.replace(/[$]/g, '\\$');
}

/// Each catch scope in `src` as `[binding, body]`.
function catchScopes(src: string): Array<[string, string]> {
	const out: Array<[string, string]> = [];
	for (const m of src.matchAll(/\bcatch\s*\(\s*([A-Za-z_$][\w$]*)\s*(?::\s*[\w$]+\s*)?\)\s*\{/g)) {
		const open = m.index! + m[0].length - 1;
		out.push([m[1], src.slice(open, matchClose(src, open))]);
	}
	for (const m of src.matchAll(/\.catch\(\s*(?:async\s*)?\(?\s*([A-Za-z_$][\w$]*)\s*(?::\s*[\w$]+\s*)?\)?\s*=>/g)) {
		const open = m.index! + '.catch'.length;
		out.push([m[1], src.slice(open, matchClose(src, open))]);
	}
	return out;
}

function findHandFormatters(src: string): string[] {
	const hits: string[] = [];
	for (const m of src.matchAll(/\b([\w$]+)\s+instanceof\s+Error\s*\?\s*\1\.message\s*:/g)) {
		hits.push(m[0]);
	}
	for (const m of src.matchAll(/\(\s*[\w$]+ as Error\s*\)\??\.message/g)) hits.push(m[0]);
	for (const [name, body] of catchScopes(src)) {
		const n = escape(name);
		const guarded = body.replace(new RegExp(`\\b${n} instanceof Error\\s*(?:\\?|&&)\\s*${n}\\.message`, 'g'), '');
		const bad = new RegExp(
			`(?<![\\w$.])String\\(\\s*${n}\\s*\\)|\\$\\{\\s*${n}\\s*\\}|(?<![\\w$.])${n}\\??\\.message\\b`,
			'g',
		);
		for (const m of guarded.matchAll(bad)) hits.push(`catch (${name}) … ${m[0]}`);
	}
	return hits;
}

test('no source file formats a caught value by hand', () => {
	const found = new Map<string, string[]>();
	for (const file of sourceFiles(srcRoot)) {
		const rel = relative(webRoot, file);
		if (rel === 'src/lib/core/supabase_error.ts') continue;
		const raw = readFileSync(file, 'utf-8');
		const src = file.endsWith('.svelte') ? stripSvelteComments(raw) : stripComments(raw);
		const hits = findHandFormatters(src);
		if (hits.length) found.set(rel, hits);
	}
	const unexpected: string[] = [];
	for (const [rel, hits] of found) {
		const allowed = ALLOW[rel];
		if (!allowed) unexpected.push(`${rel}: ${hits.join(' | ')}`);
		else if (allowed[0] !== hits.length) {
			unexpected.push(`${rel}: registered ${allowed[0]}, found ${hits.length} — update the ALLOW count or use thrownMessage`);
		}
	}
	for (const rel of Object.keys(ALLOW)) {
		if (!found.has(rel)) unexpected.push(`${rel}: registered in ALLOW but has no hand formatter — drop the entry`);
	}
	assert.deepEqual(
		unexpected,
		[],
		'format a caught value with thrownMessage(e) from core/supabase_error.ts — a PostgREST error is a ' +
			'plain object and String(e) shows "[object Object]". Where the result gates an error state ' +
			'({#if err}, if (err)), compare against null: thrownMessage returns "" for a value with no message.',
	);
});

test('the scanner bites on every banned shape and passes the helper', () => {
	const bites = [
		'try { a() } catch (e) { x = e instanceof Error ? e.message : String(e); }',
		'try { a() } catch (err) { x = err instanceof Error ? err.message : `${err}`; }',
		'try { a() } catch (e) { showToast(m("k", { error: String(e) })); }',
		'try { a() } catch (e) { showToast(m("k", { error: `${e}` })); }',
		'try { a() } catch (e) { x = (e as Error).message; }',
		'try { a() } catch (e) { x = String((e as Error)?.message ?? e); }',
		'try { a() } catch (e: any) { showToast(e?.message ?? "x"); }',
		'try { a() } catch (e: any) { showToast(e.message); }',
		'p.catch((e) => toast(String(e)));',
		'p.catch(err => { log(`failed: ${err}`); });',
		'try { a() } catch (e) { x = e instanceof Error ? e.message : m("fallback"); }',
		'try { a() } catch (e) { const code = e instanceof Error ? e.message : ""; }',
		'try { a() } catch (e) { error = e instanceof Error\n\t? e.message\n\t: m("fallback"); }',
	];
	for (const src of bites) assert.ok(findHandFormatters(src).length > 0, `must flag: ${src}`);
	const passes = [
		'try { a() } catch (e) { x = thrownMessage(e); }',
		'try { a() } catch (e) { x = appErrorMessage(e) ?? m("fallback"); }',
		'try { a() } catch (e) { const code = appErrorMessage(e) ?? ""; }',
		'try { a() } catch (e) { console.warn("failed", e); }',
		'try { a() } catch (e) { if (e instanceof Error && e.message === REFUSAL) return; }',
		'try { a() } catch (e) { x = thrownMessage(e) || "{"; } const s = String(e);',
		'const label = String(count);',
	];
	for (const src of passes) assert.deepEqual(findHandFormatters(src), [], `must pass: ${src}`);
});
