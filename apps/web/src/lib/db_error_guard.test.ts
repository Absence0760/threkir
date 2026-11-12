import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { stripComments, stripSvelteComments } from './core/strip_comments';

/**
 * Guard-rail: a Supabase result's `error` is thrown through `dbError`
 * (`core/supabase_error.ts`), never raw.
 *
 * postgrest-js hands back `error` as the parsed JSON body — a plain object. A
 * raw `if (error) throw error` therefore reached Sentry as "Object captured as
 * exception" with no stack, made `instanceof Error` false at every catch site,
 * and carried `details` / `hint` (which can echo row data) into whatever
 * logged it. § 1917 moved every site in `src/` onto `dbError`; this file fails
 * the PR on the next raw one.
 *
 * What is banned, after comments are stripped:
 *   1. `throw <expr>.error` — the `.error` of a result, however it is named;
 *   2. `throw <name>` where `<name>` is bound by destructuring a result's
 *      `error` key (`const { error } = …`, `const { error: upErr } = …`),
 *      unless the throw sits inside a `catch (<name>)` that rebinds it.
 * Both also when followed by `??` (`throw error ?? new Error('x')`).
 *
 * A caught value rethrown as itself (`catch (e) { …; throw e; }`) is not a
 * result's error and is not flagged.
 *
 * Invocation:
 *   npx tsx --test src/lib/db_error_guard.test.ts
 */

const libRoot = import.meta.dirname;
const webRoot = resolve(libRoot, '..', '..');
const srcRoot = resolve(webRoot, 'src');

const IDENT = '[A-Za-z_$][\\w$]*';

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

function matchClose(src: string, open: number): number {
	let depth = 0;
	for (let i = open; i < src.length; i++) {
		const ch = src[i];
		if (ch === "'" || ch === '"') {
			for (i++; i < src.length && src[i] !== ch && src[i] !== '\n'; i++) if (src[i] === '\\') i++;
			continue;
		}
		if (ch === '{') depth++;
		else if (ch === '}' && --depth === 0) return i + 1;
	}
	return src.length;
}

/// Names a destructuring pattern binds to a result's `error` key.
function errorBindings(src: string): Set<string> {
	const names = new Set<string>();
	for (const m of src.matchAll(/\{([^{}]*)\}\s*=(?![=>])/g)) {
		for (const part of m[1].split(',')) {
			const t = part.trim();
			if (t === 'error') names.add('error');
			const renamed = t.match(new RegExp(`^error\\s*:\\s*(${IDENT})$`));
			if (renamed) names.add(renamed[1]);
		}
	}
	return names;
}

function catchScopes(src: string): Array<[string, number, number]> {
	const out: Array<[string, number, number]> = [];
	for (const m of src.matchAll(new RegExp(`\\bcatch\\s*\\(\\s*(${IDENT})[^)]*\\)\\s*\\{`, 'g'))) {
		const open = m.index! + m[0].length - 1;
		out.push([m[1], open, matchClose(src, open)]);
	}
	return out;
}

function findRawThrows(src: string): string[] {
	const bound = errorBindings(src);
	const scopes = catchScopes(src);
	const hits: string[] = [];
	const re = new RegExp(`\\bthrow\\s+(${IDENT}(?:\\??\\.${IDENT})*)(?=\\s*(?:;|\\?\\?|\\}|\\n|$))`, 'g');
	for (const m of src.matchAll(re)) {
		const head = m[1];
		if (/\??\.error$/.test(head)) {
			hits.push(m[0]);
			continue;
		}
		if (head.includes('.') || !bound.has(head)) continue;
		const rebound = scopes.some(([name, s, e]) => name === head && m.index! > s && m.index! < e);
		if (!rebound) hits.push(m[0]);
	}
	return hits;
}

test('no source file throws a supabase result error raw', () => {
	const found: string[] = [];
	for (const file of sourceFiles(srcRoot)) {
		const raw = readFileSync(file, 'utf-8');
		const src = file.endsWith('.svelte') ? stripSvelteComments(raw) : stripComments(raw);
		for (const hit of findRawThrows(src)) found.push(`${relative(webRoot, file)}: ${hit}`);
	}
	assert.deepEqual(
		found,
		[],
		'throw a Supabase result error as `throw dbError(error)` (core/supabase_error.ts). The raw ' +
			'value is a plain object: no stack for Sentry, `instanceof Error` false, and its ' +
			'details/hint can echo row data into a log. For `throw error ?? new Error(…)` write ' +
			'`throw error ? dbError(error) : new Error(…)`.',
	);
});

test('the scanner bites on every raw shape and passes the wrapped ones', () => {
	const bites = [
		"const { error } = await supabase.from('runs').delete(); if (error) throw error;",
		"const { data, error: upErr } = await supabase.storage.from('b').upload(p, f);\nif (upErr) throw upErr;",
		"const res = await supabase.rpc('x'); if (res.error) throw res.error;",
		"if (universalRes.error || deviceRes.error) { throw universalRes.error ?? deviceRes.error; }",
		"const { data, error } = await q; if (error || !data) throw error ?? new Error('No data');",
		"const { error } = await q; if (error) {\n\tthrow error\n}",
		"const r = await q; if (r?.error) throw r?.error;",
	];
	for (const src of bites) assert.ok(findRawThrows(src).length > 0, `must flag: ${src}`);
	const passes = [
		"const { error } = await supabase.from('runs').delete(); if (error) throw dbError(error);",
		"const res = await supabase.rpc('x'); if (res.error) throw dbError(res.error);",
		"const { data, error } = await q; if (error || !data) throw error ? dbError(error) : new Error('No data');",
		'try { await a(); } catch (e) { cleanup(); throw e; }',
		"const { error } = await q; try { await b(); } catch (error) { log(); throw error; }",
		"if (error.message === REFUSAL) throw new Error(REFUSAL);",
		"cached = pending.then((bag) => bag, (err) => { cached = null; throw err; });",
	];
	for (const src of passes) assert.deepEqual(findRawThrows(src), [], `must pass: ${src}`);
});
