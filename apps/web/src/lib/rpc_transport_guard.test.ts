// Source-level guard that every web `.rpc()` goes out with the HTTP method its
// function can take.
//
// supabase-js sends an RPC as a POST unless the call passes `{ get: true }`.
// The local stack's Kong can hand a request to a PostgREST connection that is
// closing, and nginx replays the request on a fresh one only when the method
// is idempotent, so a POST comes back 502 where a GET is retried unseen
// (decisions § 1703). postgrest-js's own backoff is GET/HEAD-only as well.
//
// A GET cannot carry every function, which is why this is derived rather than
// a blanket rule:
//   - PostgREST runs a GET in a READ ONLY transaction. A `volatile` function
//     that writes answers 405 (25006) there; one that happens not to write
//     succeeds today and breaks the day it gains a write. Only a function
//     declared `stable` or `immutable` has promised not to.
//   - postgrest-js stringifies each GET argument into the query string. An
//     object becomes `[object Object]`, an array becomes an unquoted `{a,b}`
//     literal that a comma or quote inside an element corrupts, and `null`
//     becomes the four-letter string "null" — a uuid parameter then answers
//     400 and a text one searches for the word. So a GET must be to a
//     function whose every input is a scalar, and must never send a null.
//
// Volatility and argument types are read from the migrations: the last
// definition of each signature wins, and a `drop function` removes it.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments, stripSvelteComments } from './core/strip_comments';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WEB = resolve(__dirname, '../..');
const MIGRATIONS = resolve(WEB, '../backend/supabase/migrations');
const SCAN_ROOTS = [resolve(WEB, 'src'), resolve(WEB, 'lambda')];

// A stable, all-scalar function that must still go out as a POST.
const POST_EXEMPT: Record<string, string> = {};

type Volatility = 'volatile' | 'stable' | 'immutable';
interface Arg {
	name: string;
	type: string;
	hasDefault: boolean;
}
interface Fn {
	name: string;
	args: Arg[];
	volatility: Volatility;
	file: string;
}

const TYPE_ALIASES: Record<string, string> = {
	int: 'integer',
	int4: 'integer',
	int8: 'bigint',
	int2: 'smallint',
	bool: 'boolean',
	float8: 'double precision',
	float4: 'real',
	decimal: 'numeric',
	varchar: 'character varying',
	timestamptz: 'timestamp with time zone',
	'timestamp without time zone': 'timestamp',
	timetz: 'time with time zone',
	'time without time zone': 'time'
};

const SCALAR_TYPES = new Set([
	'text',
	'character varying',
	'char',
	'character',
	'citext',
	'uuid',
	'smallint',
	'integer',
	'bigint',
	'numeric',
	'real',
	'double precision',
	'boolean',
	'date',
	'time',
	'time with time zone',
	'timestamp',
	'timestamp with time zone',
	'interval'
]);

const MODES = new Set(['in', 'out', 'inout', 'variadic']);

function normalizeType(raw: string): string {
	let t = raw.trim().toLowerCase().replace(/\s+/g, ' ').replace(/^public\./, '');
	let suffix = '';
	while (t.endsWith('[]')) {
		suffix += '[]';
		t = t.slice(0, -2).trim();
	}
	t = t.replace(/\(.*\)$/, '').trim();
	return (TYPE_ALIASES[t] ?? t) + suffix;
}

function isScalar(type: string): boolean {
	return SCALAR_TYPES.has(type);
}

/**
 * The SQL with comments removed and every quoted literal and dollar-quoted
 * body blanked, so statement text can be split on `;` and searched for
 * keywords without a function body's contents answering.
 */
function stripSql(sql: string): string {
	let out = '';
	let i = 0;
	while (i < sql.length) {
		const c = sql[i];
		if (c === '-' && sql[i + 1] === '-') {
			const nl = sql.indexOf('\n', i);
			i = nl === -1 ? sql.length : nl;
			continue;
		}
		if (c === '/' && sql[i + 1] === '*') {
			const end = sql.indexOf('*/', i + 2);
			i = end === -1 ? sql.length : end + 2;
			out += ' ';
			continue;
		}
		if (c === "'") {
			let j = i + 1;
			while (j < sql.length) {
				if (sql[j] === "'" && sql[j + 1] === "'") j += 2;
				else if (sql[j] === "'") break;
				else j++;
			}
			out += "''";
			i = j + 1;
			continue;
		}
		if (c === '$') {
			const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
			if (m) {
				const end = sql.indexOf(m[0], i + m[0].length);
				out += ' $body$ ';
				i = end === -1 ? sql.length : end + m[0].length;
				continue;
			}
		}
		out += c;
		i++;
	}
	return out;
}

function splitTopLevel(s: string): string[] {
	const parts: string[] = [];
	let depth = 0;
	let cur = '';
	for (const c of s) {
		if ('([{'.includes(c)) depth++;
		if (')]}'.includes(c)) depth--;
		if (c === ',' && depth === 0) {
			parts.push(cur);
			cur = '';
		} else cur += c;
	}
	if (cur.trim()) parts.push(cur);
	return parts;
}

function parseArgs(list: string): Arg[] {
	const args: Arg[] = [];
	for (const part of splitTopLevel(list)) {
		const m = /^(.*?)(?:\s+default\s+|\s*=\s*)(.*)$/is.exec(part.trim());
		const decl = (m ? m[1] : part).trim();
		const tokens = decl.split(/\s+/);
		let mode = 'in';
		if (tokens.length > 1 && MODES.has(tokens[0].toLowerCase())) {
			mode = tokens.shift()!.toLowerCase();
		}
		if (mode === 'out') continue;
		const whole = normalizeType(tokens.join(' '));
		const knownWhole =
			tokens.length === 1 ||
			isScalar(whole) ||
			isScalar(whole.replace(/(\[\])+$/, '')) ||
			/^(json|jsonb|record)(\[\])*$/.test(whole);
		if (knownWhole) {
			args.push({ name: '', type: whole, hasDefault: !!m });
		} else {
			args.push({
				name: tokens[0].replace(/"/g, ''),
				type: normalizeType(tokens.slice(1).join(' ')),
				hasDefault: !!m
			});
		}
	}
	return args;
}

function balancedParen(s: string, open: number): number {
	let depth = 0;
	for (let i = open; i < s.length; i++) {
		if (s[i] === '(') depth++;
		else if (s[i] === ')' && --depth === 0) return i;
	}
	return -1;
}

const signature = (name: string, args: Arg[]) => `${name}(${args.map((a) => a.type).join(',')})`;

function loadFunctions(): Map<string, Fn> {
	const live = new Map<string, Fn>();
	const files = readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	for (const file of files) {
		const sql = stripSql(readFileSync(join(MIGRATIONS, file), 'utf-8'));
		for (const raw of sql.split(';')) {
			const stmt = raw.trim();
			const create =
				/^create\s+(?:or\s+replace\s+)?function\s+(?:(\w+|"\w+")\.)?"?(\w+)"?\s*\(/i.exec(stmt);
			if (create) {
				const schema = (create[1] ?? 'public').replace(/"/g, '').toLowerCase();
				if (schema !== 'public') continue;
				const open = create[0].length - 1;
				const close = balancedParen(stmt, open);
				const args = parseArgs(stmt.slice(open + 1, close));
				const tail = stmt.slice(close + 1).toLowerCase();
				const vol = /\b(immutable|stable|volatile)\b/.exec(tail);
				const name = create[2].toLowerCase();
				live.set(signature(name, args), {
					name,
					args,
					volatility: (vol?.[1] as Volatility) ?? 'volatile',
					file
				});
				continue;
			}
			const drop = /^drop\s+function\s+(?:if\s+exists\s+)?(?:(\w+)\.)?"?(\w+)"?\s*(\()?/i.exec(stmt);
			if (drop) {
				if ((drop[1] ?? 'public').toLowerCase() !== 'public') continue;
				const name = drop[2].toLowerCase();
				if (drop[3]) {
					const open = drop[0].length - 1;
					const args = parseArgs(stmt.slice(open + 1, balancedParen(stmt, open)));
					live.delete(signature(name, args));
				} else {
					for (const [key, fn] of live) if (fn.name === name) live.delete(key);
				}
				continue;
			}
			const alter = /^alter\s+function\s+(?:(\w+)\.)?"?(\w+)"?\s*\(/i.exec(stmt);
			if (alter && (alter[1] ?? 'public').toLowerCase() === 'public') {
				const open = alter[0].length - 1;
				const close = balancedParen(stmt, open);
				const key = signature(alter[2].toLowerCase(), parseArgs(stmt.slice(open + 1, close)));
				const fn = live.get(key);
				if (!fn) continue;
				const rest = stmt.slice(close + 1).toLowerCase();
				if (/\bset\s+schema\b/.test(rest)) live.delete(key);
				const vol = /^\s*(immutable|stable|volatile)\b/.exec(rest);
				if (vol) fn.volatility = vol[1] as Volatility;
			}
		}
	}
	const byName = new Map<string, Fn>();
	for (const fn of live.values()) {
		assert.ok(
			!byName.has(fn.name),
			`${fn.name} has more than one live overload; this guard cannot tell which one a call resolves to`
		);
		byName.set(fn.name, fn);
	}
	return byName;
}

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

// PostgREST reads these query parameters as its own directives, so a
// function argument of the same name cannot travel in a GET's query string.
const RESERVED_PARAMS = new Set(['select', 'order', 'limit', 'offset', 'columns', 'on_conflict', 'and', 'or', 'not']);

function takesGet(fn: Fn): boolean {
	return (
		fn.volatility !== 'volatile' &&
		fn.args.every((a) => isScalar(a.type) && !RESERVED_PARAMS.has(a.name))
	);
}

function explain(fn: Fn): string {
	const blocking = fn.args
		.filter((a) => !isScalar(a.type) || RESERVED_PARAMS.has(a.name))
		.map((a) => `${a.name} ${a.type}`);
	return `${fn.volatility}${blocking.length ? `, cannot be a query parameter: ${blocking.join(', ')}` : ''} (${fn.file})`;
}

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
