import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

/**
 * The source half of `fixtures/mock-route.ts`. The fixture makes a mock that
 * never fired a failure at RUN time; this makes a mock that was never wrapped
 * a failure at REVIEW time, so the instrument covers the specs written after
 * it rather than only the ones converted with it.
 *
 * Nothing here is an inventory. Which call sites the rule reaches is derived
 * from the call sites themselves on every run — a spec added tomorrow is
 * classified by the same two clauses as the ones already in the tree.
 */

/**
 * Endpoints whose real invocation changes state, spends money or sends mail:
 * GoTrue (credentials and confirmation mail), the Edge Functions, and this
 * app's own `/api/` routes (the Anthropic-backed coach among them). A mock in
 * front of one of these is the only thing standing between the spec and the
 * real effect.
 *
 * `/rest/v1/` is deliberately NOT here. A PostgREST read shaped by a mock
 * announces its own absence: the page renders the real rows, the error state
 * the spec is asserting on never appears, and the case fails. Writes through
 * PostgREST are reached by the counting clause below instead, which is what
 * every spec that reasons about a write already does.
 */
const SIDE_EFFECTING = /auth\/v1\/|functions\/v1\/|\/api\//;

/**
 * Shapes that record the handler ran. A spec that counts is a spec reasoning
 * about whether the endpoint was hit — and a count of zero from a pattern that
 * cannot match is indistinguishable from a count of zero because the app
 * behaved. That is the vacuous assertion the instrument exists to end, so the
 * clause holds wherever the endpoint lives.
 */
const COUNTERS = [
	/[A-Za-z_$][\w$.]*\s*\+=\s*1\b/,
	/[A-Za-z_$][\w$.]*\+\+/,
	/[A-Za-z_$][\w$.]*\s*=\s*true\b/,
	/[A-Za-z_$][\w$.]*\.push\(/
];

/** A `.route(` or `mockRoute(` call, with its whole argument list. */
interface Site {
	file: string;
	line: number;
	wrapped: boolean;
	pattern: string;
	handler: string;
}

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

/** The balanced argument list starting at the `(` at `open`. */
function callArguments(source: string, open: number): string {
	let depth = 0;
	for (let i = open; i < source.length; i++) {
		if (source[i] === '(') depth += 1;
		else if (source[i] === ')') {
			depth -= 1;
			if (depth === 0) return source.slice(open + 1, i);
		}
	}
	return source.slice(open + 1);
}

/** Split an argument list at the top-level commas. */
function splitArguments(args: string): string[] {
	const parts: string[] = [];
	let depth = 0;
	let start = 0;
	for (let i = 0; i < args.length; i++) {
		const c = args[i];
		if (c === '(' || c === '[' || c === '{') depth += 1;
		else if (c === ')' || c === ']' || c === '}') depth -= 1;
		else if (c === ',' && depth === 0) {
			parts.push(args.slice(start, i));
			start = i + 1;
		}
	}
	parts.push(args.slice(start));
	return parts.map((p) => p.trim());
}

/**
 * A pattern written as a `const` resolves to its initialiser, so a site that
 * names `AUTH_USER_ENDPOINT` is classified by what the constant holds. Escapes
 * come out (`auth\/v1\/` in a regex literal is the same endpoint as
 * `auth/v1/` in a glob) so one test reaches both spellings.
 */
function resolvePattern(source: string, raw: string): string {
	let text = raw;
	if (/^[A-Za-z_$][\w$]*$/.test(raw)) {
		const declared = new RegExp(`const\\s+${raw}\\s*(?::[^=]*)?=\\s*([^;\\n]+)`).exec(source);
		if (declared) text = declared[1].trim();
	}
	return text.replace(/\\/g, '');
}

/**
 * True when the handler can answer as the real endpoint would — a 2xx
 * `fulfill` (a `fulfill` with no `status` is a 200), a `continue` or a
 * `fallback`. A handler whose every terminal is a 4xx/5xx or an `abort` is
 * injecting a failure the spec then asserts on, and stops being able to when
 * the pattern dies.
 */
function answersAsSuccess(handler: string): boolean {
	if (/\.(?:continue|fallback)\(/.test(handler)) return true;
	const fulfils = handler.split('.fulfill(').slice(1);
	for (const after of fulfils) {
		const status = /status:\s*(\d+)/.exec(after.slice(0, 400));
		if (!status || status[1].startsWith('2')) return true;
	}
	return false;
}

function mustBeWrapped(site: Site): boolean {
	const counts = COUNTERS.some((re) => re.test(site.handler));
	return counts || (SIDE_EFFECTING.test(site.pattern) && answersAsSuccess(site.handler));
}

function parseSites(rel: string, raw: string): Site[] {
	const source = stripComments(raw);
	const sites: Site[] = [];
	const call = /(?:\w+\.route|mockRoute)\(/g;
	let match: RegExpExecArray | null;
	while ((match = call.exec(source))) {
		const open = match.index + match[0].length - 1;
		const args = splitArguments(callArguments(source, open));
		const wrapped = match[0] === 'mockRoute(';
		// `mockRoute(target, pattern, handler)` vs `page.route(pattern, handler)`.
		const [raw, ...rest] = wrapped ? args.slice(1) : args;
		sites.push({
			file: rel,
			line: source.slice(0, match.index).split('\n').length,
			wrapped,
			pattern: resolvePattern(source, raw ?? ''),
			handler: rest.join(',')
		});
	}
	return sites;
}

function sitesIn(file: string): Site[] {
	return parseSites(relative(E2E_ROOT, file), readFileSync(file, 'utf8'));
}

function allSites(): Site[] {
	const out: Site[] = [];
	for (const file of scannedSources(E2E_ROOT)) {
		const rel = relative(E2E_ROOT, file);
		if (rel === 'fixtures/mock-route.ts' || rel === 'fixtures/mock-route.test.ts') continue;
		out.push(...sitesIn(file));
	}
	return out;
}

test('every route mock that guards a mutation goes through mockRoute', () => {
	const offenders = allSites()
		.filter((s) => !s.wrapped && mustBeWrapped(s))
		.map((s) => `${s.file}:${s.line} ${s.pattern.slice(0, 60)}`);

	assert.deepEqual(
		offenders,
		[],
		'These `page.route` mocks are the only thing standing between the spec and a real ' +
			'effect — a GoTrue / Edge Function / /api call answered as a success, or a handler ' +
			'whose invocations the spec counts — and nothing reports it when the pattern stops ' +
			'matching. Register them through `mockRoute` from tests-e2e/fixtures/mock-route.ts ' +
			`so a mock that never fires fails the case: ${offenders.join(' ')}`
	);
});

test('a spec that calls mockRoute takes `test` from the fixture', () => {
	const offenders: string[] = [];
	for (const file of scannedSources(E2E_ROOT)) {
		const rel = relative(E2E_ROOT, file);
		if (rel.startsWith('fixtures/mock-route')) continue;
		const source = stripComments(readFileSync(file, 'utf8'));
		if (!/\bmockRoute\(/.test(source)) continue;
		if (!/from\s+'(?:\.\.\/)+fixtures\/mock-route'/.test(source)) offenders.push(rel);
	}
	assert.deepEqual(
		offenders,
		[],
		'These files use `mockRoute` without importing `test` from fixtures/mock-route, so the ' +
			`fixture that provides it is not in scope: ${offenders.join(' ')}`
	);
});

test('the scan still finds the tree it is scanning', () => {
	// A rename, a formatting change or a broken regex would empty the scan, and
	// an empty scan passes every assertion above it in silence. Floors rather
	// than exact counts, so ordinary churn does not touch this file.
	const sites = allSites();
	assert.ok(sites.length > 150, `the route-call scan found only ${sites.length} sites`);
	const wrapped = sites.filter((s) => s.wrapped);
	assert.ok(wrapped.length > 50, `the scan found only ${wrapped.length} mockRoute sites`);
	assert.ok(
		sites.some((s) => !s.wrapped),
		'the scan no longer recognises a bare page.route call at all'
	);
});

test('the pattern resolver reaches a named constant and both escape spellings', () => {
	const source = "const AUTH_USER_ENDPOINT = /\\/auth\\/v1\\/user(\\?|$)/;\nconst X = 1;\n";
	assert.ok(SIDE_EFFECTING.test(resolvePattern(source, 'AUTH_USER_ENDPOINT')));
	assert.ok(SIDE_EFFECTING.test(resolvePattern(source, "'**/auth/v1/user*'")));
	assert.ok(!SIDE_EFFECTING.test(resolvePattern(source, "'**/rest/v1/runs*'")));
	// An unresolvable name must not be read as an endpoint it does not name.
	assert.equal(resolvePattern(source, 'UNKNOWN_CONST'), 'UNKNOWN_CONST');
});

test('the success test separates a stub that answers from one that injects a failure', () => {
	for (const probe of [
		'(route) => route.fulfill({ status: 200, body: "{}" })',
		'(route) => route.fulfill({ body: JSON.stringify({ ok: true }) })',
		'async (route) => { await route.continue(); }',
		'async (route) => { if (x) return route.fallback(); }',
		'(route) => route.fulfill({ status: 500, body: "{}" }) ; route.fulfill({ status: 204 })'
	]) {
		assert.ok(answersAsSuccess(probe), `read as a failure injection: ${probe}`);
	}
	for (const probe of [
		'(route) => route.fulfill({ status: 500, body: "boom" })',
		'(route) => route.abort("failed")',
		'(route) => route.fulfill({ status: 429, contentType: "application/json", body: "{}" })'
	]) {
		assert.ok(!answersAsSuccess(probe), `read as a success stub: ${probe}`);
	}
});

test('the counting clause reaches the shapes a spec records a hit with', () => {
	const site = (handler: string): Site => ({
		file: 'probe.spec.ts',
		line: 1,
		wrapped: false,
		pattern: "'**/rest/v1/runs*'",
		handler
	});
	for (const handler of [
		'async (route) => { seen.put += 1; await route.abort(); }',
		'async (route) => { calls++; await route.continue(); }',
		'async (route) => { sawRequest = true; await route.abort(); }',
		'async (route) => { requested.push(route.request().url()); await route.continue(); }'
	]) {
		assert.ok(mustBeWrapped(site(handler)), `the counting clause misses: ${handler}`);
	}
	// A read shaped with a 500 and no counter announces its own absence.
	assert.ok(
		!mustBeWrapped(site('async (route) => route.fulfill({ status: 500, body: "boom" })'))
	);
});

test('the scan reads the pattern out of the right argument on both call shapes', () => {
	const parsed = parseSites(
		'probe.spec.ts',
		[
			"await page.route('**/functions/v1/export-data', (route) => route.fulfill({ status: 200 }));",
			"await mockRoute(alexPage, '**/api/coach', (route) => route.fulfill({ status: 200 }));",
			'// await page.route("**/api/coach", (route) => route.fulfill({ status: 200 }));',
			'await page.unroute("**/api/coach");'
		].join('\n')
	);
	assert.deepEqual(
		parsed.map((s) => `${s.wrapped ? 'wrapped' : 'bare'} ${s.pattern}`),
		["bare '**/functions/v1/export-data'", "wrapped '**/api/coach'"],
		'a commented-out call, or an unroute, must not read as a mock — and the wrapped shape ' +
			'carries its pattern in the SECOND argument'
	);
	assert.ok(parsed.every((s) => mustBeWrapped(s)));
});
