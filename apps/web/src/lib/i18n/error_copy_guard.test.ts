import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { stripComments, stripSvelteComments } from '../core/strip_comments';

/**
 * Guard-rail: a UI file never hands a thrown error's own text to the reader.
 *
 * `m('x.failed', { error: thrownMessage(e) })` dropped PostgREST's or the
 * browser's English ("violates check constraint …", "Failed to fetch") into a
 * localized sentence, and could carry a table or constraint name with it.
 * § 2291 moved every UI site onto `errorCopy(e, m, key)`
 * (`i18n/error_copy.ts`), which shows catalogue copy and logs the raw text;
 * this file fails the PR on the next raw one.
 *
 * Scope: every `.svelte` and `.svelte.ts` file under `src/` — the files that
 * render. Server handlers and the data layer are not scanned: their error
 * text goes to logs or into a thrown value a UI file then has to pass through
 * `errorCopy`.
 *
 * What is banned, after comments are stripped, outside a `console.*(…)` call
 * and outside `throw new …Error(…)`:
 *   1. any call to `thrownMessage(…)`;
 *   2. `<caught>.message`, where `<caught>` is one of the names a catch or a
 *      Supabase result's error is bound to here, unless it is only compared
 *      (`=== X`, `.includes(…)`, `.startsWith(…)`, `/re/.test(…)`);
 *   3. `String(<caught>)` and `${<caught>}`;
 *   4. any call to `appErrorMessage(…)`. `appErrorMessage(e) ?? m('copy')`
 *      showed any `Error` the app raised as it was: an English sentence from
 *      the data layer, a machine code, the browser's `TypeError: Failed to
 *      fetch`. A specific sentence is thrown as an `AppError` carrying its
 *      catalogue key, which `errorCopy` renders; a refusal code is compared
 *      through `refusalCode(e)`;
 *   5. the shapes of 2 and 3 on a reader result's `.error` (`res.error.message`,
 *      `String(res.error)`, `${res.error}`), and `{res.error}` in markup.
 *
 * The data layer gets one check of its own: a reader in `core/data.ts` hands
 * back the failure, never its text. `{ rows, error: string }` put PostgREST's
 * English (or an English fallback) in front of the reader through a field
 * this scan could not tell from copy; `{ rows, error: Error | null }` makes the
 * screen call `errorCopy(res.error, m, key)`, and svelte-check refuses a
 * screen that assigns it to a string.
 *
 * Invocation:
 *   npx tsx --test src/lib/i18n/error_copy_guard.test.ts
 */

const webRoot = resolve(import.meta.dirname, '..', '..', '..');
const srcRoot = resolve(webRoot, 'src');

/// Files where a hit is not reader-facing, how many hits that is, and why.
/// The count is exact, so a new raw site in one of these files still fails.
/// A classifier reads the thrown text only to compare it with a machine code
/// the data layer rethrows; its fallback branch goes through `errorCopy`.
const ALLOWED: Record<string, { hits: number; reason: string }> = {
	'src/lib/components/DonationFeed.svelte': {
		hits: 2,
		reason: "`e.message` is the donor's own note on a donation row (`e` is the loop entry), not an error",
	},
	'src/lib/components/settings/PrefsPage.svelte': {
		hits: 1,
		reason: '`page.error` is already `errorCopy` output, set in settings/prefs_page.svelte.ts',
	},
	'src/lib/components/RaceImportDialog.svelte': {
		hits: 1,
		reason: 'classifier: compares the text with the race-import refusal codes; every branch shows catalogue copy',
	},
	'src/lib/components/RunRaceResult.svelte': {
		hits: 1,
		reason: 'classifier: compares the text with the race-import refusal codes; every branch shows catalogue copy',
	},
	'src/routes/clubs/[slug]/events/[id]/board/+page.svelte': {
		hits: 1,
		reason: 'classifier: an organiser-only refusal turns the board into its access-denied state',
	},
	'src/routes/settings/payouts/+page.svelte': {
		hits: 1,
		reason: 'classifier: `stripe_not_configured` is an info toast; the rest go through errorCopy',
	},
};

const CAUGHT = '(?:e|err|error|ex|caught|failure|upErr|uploadErr|saveErr|loadErr)';
/// A reader result's failure: `res.error`, `planRes?.error`.
const RESULT_ERROR = '[\\w$]+\\??\\.error';

const DATA_LAYER = 'src/lib/core/data.ts';

/// Offset of the `{` that opens the object type around `at`, or -1.
function enclosingBrace(src: string, at: number): number {
	let depth = 0;
	for (let i = at - 1; i >= 0; i--) {
		if (src[i] === '}') depth++;
		else if (src[i] === '{' && depth-- === 0) return i;
	}
	return -1;
}

/// Every function in a data-layer source whose declared return type carries
/// an `error` typed as text, by name. A cast or a parameter shape
/// (`body as { error?: string }`) is not a return type and is not counted.
export function readersReturningErrorText(src: string): string[] {
	const fns = [...src.matchAll(/\bfunction\s+([\w$]+)\s*[<(]/g)].map((m) => ({
		at: m.index!,
		name: m[1],
	}));
	const names = new Set<string>();
	for (const m of src.matchAll(/\berror\??\s*:\s*string\b/g)) {
		const open = enclosingBrace(src, m.index!);
		if (open < 0) continue;
		const lead = src.slice(Math.max(0, open - 60), open);
		const alias = /\btype\s+([\w$]+)\s*=\s*$/.exec(lead);
		if (alias) {
			names.add(`type ${alias[1]}`);
			continue;
		}
		if (!/(?:Promise<|\)\s*:)\s*$/.test(lead)) continue;
		const owner = fns.filter((f) => f.at < m.index!).pop();
		names.add(owner ? owner.name : '<module scope>');
	}
	return [...names].sort();
}

function uiFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			uiFiles(full, out);
			continue;
		}
		if (/\.test\.ts$/.test(entry.name)) continue;
		if (!/\.svelte$|\.svelte\.ts$/.test(entry.name)) continue;
		out.push(full);
	}
	return out;
}

function closeParen(src: string, open: number): number {
	let depth = 0;
	for (let i = open; i < src.length; i++) {
		const ch = src[i];
		if (ch === "'" || ch === '"' || ch === '`') {
			for (i++; i < src.length && src[i] !== ch; i++) if (src[i] === '\\') i++;
			continue;
		}
		if (ch === '(') depth++;
		else if (ch === ')' && --depth === 0) return i + 1;
	}
	return src.length;
}

/// Offsets inside a call whose arguments never reach the reader.
function exemptSpans(src: string): Array<[number, number]> {
	const spans: Array<[number, number]> = [];
	for (const m of src.matchAll(/\bconsole\.\w+\s*\(|\bthrow\s+new\s+\w*Error\s*\(/g)) {
		const open = m.index! + m[0].length - 1;
		spans.push([open, closeParen(src, open)]);
	}
	return spans;
}

export function findRawErrorText(src: string): string[] {
	const spans = exemptSpans(src);
	const exempt = (at: number) => spans.some(([s, e]) => at > s && at < e);
	const hits: string[] = [];
	const lineOf = (at: number) => src.slice(0, at).split('\n').length;
	const push = (at: number, text: string) => {
		if (!exempt(at)) hits.push(`${lineOf(at)}: ${text}`);
	};

	for (const m of src.matchAll(/\b(?:thrownMessage|appErrorMessage)\s*\(/g)) push(m.index!, m[0]);

	const message = new RegExp(`(?<![\\w$.])${CAUGHT}\\??\\.message\\b`, 'g');
	for (const m of src.matchAll(message)) {
		const before = src.slice(Math.max(0, m.index! - 12), m.index!);
		const after = src.slice(m.index! + m[0].length, m.index! + m[0].length + 16);
		if (/^\s*(?:===|!==|==|!=)/.test(after)) continue;
		if (/^\??\.(?:includes|startsWith|endsWith|match|search)\s*\(/.test(after)) continue;
		if (/(?:===|!==|==|!=)\s*$/.test(before)) continue;
		if (/\.test\(\s*$/.test(before)) continue;
		push(m.index!, m[0]);
	}

	const stringified = new RegExp(`\\bString\\(\\s*${CAUGHT}\\s*\\)|\\$\\{\\s*${CAUGHT}\\s*\\}`, 'g');
	for (const m of src.matchAll(stringified)) push(m.index!, m[0]);

	const resultMessage = new RegExp(`(?<![\\w$.])${RESULT_ERROR}\\??\\.message\\b`, 'g');
	for (const m of src.matchAll(resultMessage)) {
		const before = src.slice(Math.max(0, m.index! - 12), m.index!);
		const after = src.slice(m.index! + m[0].length, m.index! + m[0].length + 16);
		if (/^\s*(?:===|!==|==|!=)/.test(after)) continue;
		if (/^\??\.(?:includes|startsWith|endsWith|match|search)\s*\(/.test(after)) continue;
		if (/(?:===|!==|==|!=)\s*$/.test(before)) continue;
		if (/\.test\(\s*$/.test(before)) continue;
		push(m.index!, m[0]);
	}
	const resultText = new RegExp(
		`\\bString\\(\\s*${RESULT_ERROR}\\s*\\)|\\$?\\{\\s*(?<![\\w$.])${RESULT_ERROR}\\s*\\}`,
		'g',
	);
	for (const m of src.matchAll(resultText)) push(m.index!, m[0]);

	return hits;
}

test('no UI file shows a thrown error\'s own text', () => {
	const found: string[] = [];
	for (const file of uiFiles(srcRoot)) {
		const rel = relative(webRoot, file);
		const raw = readFileSync(file, 'utf-8');
		const src = file.endsWith('.svelte') ? stripSvelteComments(raw) : stripComments(raw);
		const hits = findRawErrorText(src);
		if (rel in ALLOWED && hits.length === ALLOWED[rel].hits) continue;
		for (const hit of hits) found.push(`${rel}:${hit}`);
	}
	assert.deepEqual(
		found,
		[],
		'show a failure as `errorCopy(e, m, key)` (i18n/error_copy.ts), framed by the action\'s own ' +
			'sentence: `m(key, { error: errorCopy(e, m, key) })`, or as `errorCopy(e, m, context, ' +
			'fallbackKey)` where the surface has a line of its own. It maps offline, timeout, signed ' +
			'out, permission, not found, a refused value and a rate limit to catalogue copy and logs ' +
			'the raw text. Compare a refusal code with `refusalCode(e)`; throw a failure that needs ' +
			'its own sentence as `new AppError(key)` (core/app_error.ts). A raw message is English ' +
			'inside a localized page and can name a table or ' +
			'constraint. Log the raw text with `console.error(…)` if you need it.',
	);
});

test('no data-layer reader returns error text', () => {
	const src = stripComments(readFileSync(resolve(webRoot, DATA_LAYER), 'utf-8'));
	assert.deepEqual(
		readersReturningErrorText(src),
		[],
		`a reader in ${DATA_LAYER} returns its failure as text. Return the caught value, put ` +
			'through `dbError` (`{ rows, error: Error | null }`), and let the screen render it with ' +
			'`errorCopy(res.error, m, key)`: text here is English the scan above cannot see.',
	);
});

test('every allowlisted file still exists and still needs its exemption', () => {
	for (const [rel, { hits, reason }] of Object.entries(ALLOWED)) {
		assert.ok(reason.length > 20, `${rel} needs a reason`);
		const raw = readFileSync(resolve(webRoot, rel), 'utf-8');
		const src = rel.endsWith('.svelte') ? stripSvelteComments(raw) : stripComments(raw);
		const found = findRawErrorText(src).length;
		assert.ok(found > 0, `${rel} no longer needs its ALLOWED entry`);
		assert.ok(found <= hits, `${rel} has ${found} hits, ALLOWED says ${hits}`);
	}
});

test('the data-layer scan names a reader that declares its error as text', () => {
	const src = [
		'export async function a(): Promise<{ rows: X[]; error: string | null }> {}',
		'export async function b(): Promise<{',
		'\trows: X[];',
		'\terror: string | null;',
		'}> {}',
		'export async function c(): Promise<{ rows: X[]; error: Error | null }> {}',
		'async function d(): Promise<{ error?: string }> {}',
		'function e(): { ok: boolean; error: string } {}',
		"function f(body: unknown) { return (body as { error?: string }).error === 'x'; }",
		'export type G = { rows: X[]; error: string | null };',
	].join('\n');
	assert.deepEqual(readersReturningErrorText(src), ['a', 'b', 'd', 'e', 'type G']);
});

test('the scanner bites on every raw shape and passes the safe ones', () => {
	const bites = [
		"showToast(m('x.failed', { error: thrownMessage(e) }), 'error');",
		'loadError = thrownMessage(e);',
		"showToast(thrownMessage(e) || t('segments.createFailed'), 'error');",
		"if (error) showToast(m('prefs.saveFailed', { error: error.message }), 'error');",
		'<p class="error">{error.message}</p>',
		'passwordError = err?.message;',
		'status = String(e);',
		'banner = `Failed: ${err}`;',
		'loadError = res.error.message;',
		'detail = planRes?.error?.message ?? null;',
		'detail = String(res.error);',
		'banner = `Failed: ${result.error}`;',
		'<span class="error-detail">{res.error}</span>',
		"error = appErrorMessage(e) ?? m('clubJoin.invalidOrExpired');",
		"const code = appErrorMessage(e) ?? '';",
	];
	for (const src of bites) assert.ok(findRawErrorText(src).length > 0, `must flag: ${src}`);
	const passes = [
		"showToast(m('x.failed', { error: errorCopy(e, m, 'x.failed') }), 'error');",
		"console.error('saving failed', { message: thrownMessage(e) });",
		"console.warn(\n\t'x',\n\t{ message: e.message, detail: String(e) },\n);",
		'if (error) throw new Error(error.message);',
		"if (e instanceof Error && e.message === PAID_EVENT_DELETE_REFUSAL) return;",
		"if (error.message.includes('handle_taken')) handleError = m('h.taken');",
		'if (/42501|permission/i.test(e.message)) denied = true;',
		'const label = route.message;',
		"loadError = errorCopy(res.error, m, 'runs: loadError');",
		'if (res.error) throw dbError(res.error);',
		"if (res.error?.message === 'x') return;",
		"error = errorCopy(e, m, 'clubJoin.invalidOrExpired', 'clubJoin.invalidOrExpired');",
		"const code = refusalCode(e);",
	];
	for (const src of passes) assert.deepEqual(findRawErrorText(src), [], `must pass: ${src}`);
});
