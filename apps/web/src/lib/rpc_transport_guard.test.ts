// Source-level guard that every web `.rpc()` goes out with the HTTP method its
// function can take.
//
// supabase-js sends an RPC as a POST unless the call passes `{ get: true }`,
// and a POST is the one method nothing retries when Kong hands it a closing
// PostgREST connection (decisions § 1703). Which functions can take a GET —
// `stable` or `immutable`, every input a scalar, no argument named like a
// PostgREST directive — and why, is derived from the migrations by
// scripts/rpc_transport.mjs. That module is shared with
// scripts/check_dart_rpc_transport.mjs, which holds the Dart clients to the
// same rule (decisions § 1803).
//
// supabase-js stringifies each GET argument into the query string, so `null`
// becomes the four-letter string "null": a GET omits an argument (undefined)
// instead, and may only omit one whose parameter has a default.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments, stripSvelteComments } from './core/strip_comments';
import {
	balancedParen,
	explain,
	loadFunctions,
	splitTopLevel,
	takesGet
} from '../../../../scripts/rpc_transport.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WEB = resolve(__dirname, '../..');
const SCAN_ROOTS = [resolve(WEB, 'src'), resolve(WEB, 'lambda')];

// A stable, all-scalar function that must still go out as a POST.
const POST_EXEMPT: Record<string, string> = {};

interface Site {
	where: string;
	fn: string;
	args: string;
	options: string;
	get: boolean;
}

function sources(dir: string, out: string[] = []): string[] {
	let entries: string[];
	try {
		entries = readdirSync(dir);
	} catch {
		return out;
	}
	for (const name of entries) {
		if (name === 'node_modules') continue;
		const p = join(dir, name);
		if (statSync(p).isDirectory()) sources(p, out);
		else if (/\.(ts|js|mjs|svelte)$/.test(name) && !/\.(test|spec)\./.test(name)) out.push(p);
	}
	return out;
}

function callSites(): Site[] {
	const sites: Site[] = [];
	for (const root of SCAN_ROOTS) {
		for (const file of sources(root)) {
			const raw = readFileSync(file, 'utf-8');
			const src = file.endsWith('.svelte') ? stripSvelteComments(raw) : stripComments(raw);
			const re = /\.rpc\s*(?:<[^>]*>)?\s*\(/g;
			let m: RegExpExecArray | null;
			while ((m = re.exec(src))) {
				const open = m.index + m[0].length - 1;
				const close = balancedParen(src, open);
				const inner = src.slice(open + 1, close);
				const parts = splitTopLevel(inner);
				const name = /^\s*['"`](\w+)['"`]\s*$/.exec(parts[0] ?? '');
				const where = `${relative(WEB, file)}:${src.slice(0, m.index).split('\n').length}`;
				assert.ok(name, `${where}: .rpc() is not called with a literal function name`);
				const options = (parts[2] ?? '').trim();
				sites.push({
					where,
					fn: name[1],
					args: (parts[1] ?? '').trim(),
					options,
					get: /\bget\s*:\s*true\b/.test(options)
				});
			}
		}
	}
	return sites;
}

const FUNCTIONS = loadFunctions();
const SITES = callSites();

test('the scan reaches the call sites and the migrations it is meant to read', () => {
	assert.ok(SITES.length >= 100, `only ${SITES.length} .rpc() call sites found`);
	assert.ok(FUNCTIONS.size >= 200, `only ${FUNCTIONS.size} public functions parsed`);
	const markers = FUNCTIONS.get('route_markers_for_viewer');
	assert.equal(markers?.volatility, 'stable');
	assert.deepEqual(
		markers?.args.map((a) => a.type),
		['uuid']
	);
	assert.equal(FUNCTIONS.get('routes_intersecting_track')?.args[1].type, 'jsonb');
	assert.equal(FUNCTIONS.get('clear_discoverable_area')?.volatility, 'volatile');
});

test('the SECURITY DEFINER reads that write nothing are declared stable and go out as GETs', () => {
	// 20270722000001 re-declared these seven; each one's web call is a GET.
	const reads = [
		'am_i_admin',
		'clip_route_for_viewer',
		'fetch_checkpoint_crossings_for_organiser',
		'fetch_pending_reports',
		'fetch_reports_for_target',
		'get_event_meet_point',
		'my_pending_safety_requests'
	];
	for (const name of reads) {
		const fn = FUNCTIONS.get(name);
		assert.ok(fn, `${name} is not a live function`);
		assert.equal(fn.volatility, 'stable', `${name}: ${explain(fn)}`);
		const calls = SITES.filter((s) => s.fn === name);
		assert.ok(calls.length > 0, `${name} has no web call site`);
		assert.deepEqual(
			calls.filter((s) => !s.get).map((s) => s.where),
			[],
			`${name} is still sent as a POST`
		);
	}
});

test('every .rpc() names a function the migrations still define', () => {
	const missing = SITES.filter((s) => !FUNCTIONS.has(s.fn)).map((s) => `${s.where} ${s.fn}`);
	assert.deepEqual(missing, []);
});

test('a stable or immutable all-scalar RPC is sent as a GET', () => {
	const posts = SITES.filter((s) => {
		const fn = FUNCTIONS.get(s.fn);
		return fn && takesGet(fn) && !s.get && !(s.fn in POST_EXEMPT);
	}).map((s) => `${s.where} ${s.fn}: pass { get: true }`);
	assert.deepEqual(posts, []);
});

test('a GET is sent only to a function that can take one', () => {
	const bad = SITES.filter((s) => {
		const fn = FUNCTIONS.get(s.fn);
		return s.get && fn && !takesGet(fn);
	}).map((s) => `${s.where} ${s.fn}: ${explain(FUNCTIONS.get(s.fn)!)}`);
	assert.deepEqual(bad, []);
});

test('a GET never sends a null argument, which it would stringify to "null"', () => {
	const bad = SITES.filter((s) => s.get && /\bnull\b/.test(s.args)).map(
		(s) => `${s.where} ${s.fn}: omit the argument (undefined) instead of sending null`
	);
	assert.deepEqual(bad, []);
});

test('a GET omits only an argument whose parameter has a default', () => {
	const bad: string[] = [];
	for (const s of SITES.filter((x) => x.get)) {
		const fn = FUNCTIONS.get(s.fn);
		if (!fn) continue;
		const body = s.args.replace(/^\{|\}$/g, '');
		for (const entry of splitTopLevel(body)) {
			const key = /^\s*(?:\.\.\.)?\s*(\w+)\s*:/.exec(entry)?.[1];
			const omittable = /\bundefined\b/.test(entry) || /^\s*\.\.\./.test(entry);
			if (!omittable) continue;
			const names = key ? [key] : [...entry.matchAll(/\b(p_\w+)\s*:/g)].map((x) => x[1]);
			for (const n of names) {
				const arg = fn.args.find((a) => a.name === n);
				if (!arg?.hasDefault) bad.push(`${s.where} ${s.fn}.${n} can be omitted but has no default`);
			}
		}
	}
	assert.deepEqual(bad, []);
});

test('every POST exemption is still needed and still called', () => {
	const stale: string[] = [];
	for (const name of Object.keys(POST_EXEMPT)) {
		const fn = FUNCTIONS.get(name);
		if (!fn || !takesGet(fn)) stale.push(`${name}: no longer a GET candidate`);
		else if (!SITES.some((s) => s.fn === name && !s.get)) stale.push(`${name}: no POST call site left`);
	}
	assert.deepEqual(stale, []);
});
