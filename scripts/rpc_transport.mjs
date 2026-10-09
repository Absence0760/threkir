// Which HTTP method each `public` function can be called with over PostgREST,
// read from the migrations. Shared by the two client-side transport guards:
// apps/web/src/lib/rpc_transport_guard.test.ts (supabase-js) and
// scripts/check_dart_rpc_transport.mjs (postgrest-dart), so the rule a web
// call and a Dart call are held to is one rule.
//
// A client sends an RPC as a POST unless it asks for a GET. The local stack's
// Kong can hand a request to a PostgREST connection that is closing, and nginx
// replays it on a fresh one only when the method is idempotent, so a POST
// comes back 502 where a GET is retried unseen (decisions § 1703). Both
// clients' own backoff is GET/HEAD-only as well.
//
// A GET cannot carry every function, which is why this is derived rather than
// a blanket rule:
//   - PostgREST runs a GET in a READ ONLY transaction. A `volatile` function
//     that writes answers 405 (25006) there; one that happens not to write
//     succeeds today and breaks the day it gains a write. Only a function
//     declared `stable` or `immutable` has promised not to.
//   - Both clients stringify each GET argument into the query string. An
//     object becomes `[object Object]` (JS) or a Dart map literal, an array an
//     unquoted `{a,b}` literal that a comma or quote inside an element
//     corrupts, and a null the four-letter string "null" — a uuid parameter
//     then answers 400 and a text one searches for the word. So a GET must be
//     to a function whose every input is a scalar, and must never send a null.
//
// The last definition of each signature wins, `drop function` removes it, and
// `alter function … stable|volatile` / `set schema` are applied. Statements
// come from sql_lex.mjs with every literal and dollar-quoted body blanked, so
// a function BODY's text never answers for a keyword in its header; quoted
// identifiers are kept, because a parameter's name is read.
//
// Unit tests: `node --test scripts/rpc_transport.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { splitSqlStatements } from '../apps/backend/scripts/sql_lex.mjs';

export const MIGRATIONS_DIR = resolve(
	dirname(fileURLToPath(import.meta.url)),
	'../apps/backend/supabase/migrations'
);

/** @typedef {'volatile' | 'stable' | 'immutable'} Volatility */
/**
 * @typedef {{ name: string, type: string, hasDefault: boolean, defaultIsNull: boolean }} Arg
 * `defaultIsNull` separates a parameter whose omission means NULL from one
 * whose omission means some other value: a client that sends an explicit
 * null today and omits the key instead after moving to a GET changes what
 * the function receives unless the default is NULL.
 */
/** @typedef {{ name: string, args: Arg[], volatility: Volatility, file: string }} Fn */

/** @type {Record<string, string>} */
const TYPE_ALIASES = {
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

// PostgREST reads these query parameters as its own directives, so a
// function argument of the same name cannot travel in a GET's query string.
export const RESERVED_PARAMS = new Set([
	'select',
	'order',
	'limit',
	'offset',
	'columns',
	'on_conflict',
	'and',
	'or',
	'not'
]);

/**
 * @param {string} raw
 * @returns {string}
 */
export function normalizeType(raw) {
	let t = raw.trim().toLowerCase().replace(/\s+/g, ' ').replace(/^public\./, '');
	let suffix = '';
	while (t.endsWith('[]')) {
		suffix += '[]';
		t = t.slice(0, -2).trim();
	}
	t = t.replace(/\(.*\)$/, '').trim();
	return (TYPE_ALIASES[t] ?? t) + suffix;
}

/**
 * @param {string} type a normalized type
 * @returns {boolean}
 */
export function isScalar(type) {
	return SCALAR_TYPES.has(type);
}

/**
 * Split on the commas that sit outside every bracket pair.
 * @param {string} s
 * @returns {string[]}
 */
export function splitTopLevel(s) {
	/** @type {string[]} */
	const parts = [];
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

/**
 * @param {string} s
 * @param {number} open index of a `(`
 * @returns {number} index of its matching `)`, or -1
 */
export function balancedParen(s, open) {
	let depth = 0;
	for (let i = open; i < s.length; i++) {
		if (s[i] === '(') depth++;
		else if (s[i] === ')' && --depth === 0) return i;
	}
	return -1;
}

/**
 * The input parameters of a function's argument list; `out` ones are dropped.
 * @param {string} list
 * @returns {Arg[]}
 */
export function parseArgs(list) {
	/** @type {Arg[]} */
	const args = [];
	for (const part of splitTopLevel(list)) {
		const m = /^(.*?)(?:\s+default\s+|\s*=\s*)(.*)$/is.exec(part.trim());
		const decl = (m ? m[1] : part).trim();
		const defaultIsNull = !!m && /^null\b/i.test(m[2].trim());
		const tokens = decl.split(/\s+/);
		let mode = 'in';
		if (tokens.length > 1 && MODES.has(tokens[0].toLowerCase())) {
			mode = /** @type {string} */ (tokens.shift()).toLowerCase();
		}
		if (mode === 'out') continue;
		const whole = normalizeType(tokens.join(' '));
		const knownWhole =
			tokens.length === 1 ||
			isScalar(whole) ||
			isScalar(whole.replace(/(\[\])+$/, '')) ||
			/^(json|jsonb|record)(\[\])*$/.test(whole);
		if (knownWhole) {
			args.push({ name: '', type: whole, hasDefault: !!m, defaultIsNull });
		} else {
			args.push({
				name: tokens[0].replace(/"/g, ''),
				type: normalizeType(tokens.slice(1).join(' ')),
				hasDefault: !!m,
				defaultIsNull
			});
		}
	}
	return args;
}

/**
 * @param {string} name
 * @param {Arg[]} args
 * @returns {string}
 */
const signature = (name, args) => `${name}(${args.map((a) => a.type).join(',')})`;

/**
 * Every live `public` function, keyed by signature, after replaying the
 * migrations in filename order.
 * @param {{ file: string, sql: string }[]} migrations in apply order
 * @returns {Map<string, Fn>}
 */
export function replayFunctions(migrations) {
	/** @type {Map<string, Fn>} */
	const live = new Map();
	for (const { file, sql } of migrations) {
		for (const raw of splitSqlStatements(sql, { blankLiterals: true, keepIdentifiers: true })) {
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
					volatility: /** @type {Volatility | undefined} */ (vol?.[1]) ?? 'volatile',
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
				if (vol) fn.volatility = /** @type {Volatility} */ (vol[1]);
			}
		}
	}
	return live;
}

/**
 * Live functions keyed by NAME. A call site names a function, not a
 * signature, so a second live overload is a question this cannot answer and
 * it throws rather than pick one.
 * @param {Map<string, Fn>} live
 * @returns {Map<string, Fn>}
 */
export function byName(live) {
	/** @type {Map<string, Fn>} */
	const out = new Map();
	for (const fn of live.values()) {
		if (out.has(fn.name)) {
			throw new Error(
				`${fn.name} has more than one live overload; a transport guard cannot tell which one a call resolves to`
			);
		}
		out.set(fn.name, fn);
	}
	return out;
}

/**
 * @param {string} [dir]
 * @returns {Map<string, Fn>} every live public function by name
 */
export function loadFunctions(dir = MIGRATIONS_DIR) {
	const migrations = readdirSync(dir)
		.filter((f) => f.endsWith('.sql'))
		.sort()
		.map((file) => ({ file, sql: readFileSync(join(dir, file), 'utf-8') }));
	return byName(replayFunctions(migrations));
}

/**
 * @param {Fn} fn
 * @returns {boolean} whether the function may be called with a GET
 */
export function takesGet(fn) {
	return (
		fn.volatility !== 'volatile' &&
		fn.args.every((a) => isScalar(a.type) && !RESERVED_PARAMS.has(a.name))
	);
}

/**
 * @param {Fn} fn
 * @returns {string} why the function does or does not take a GET
 */
export function explain(fn) {
	const blocking = fn.args
		.filter((a) => !isScalar(a.type) || RESERVED_PARAMS.has(a.name))
		.map((a) => `${a.name} ${a.type}`);
	return `${fn.volatility}${blocking.length ? `, cannot be a query parameter: ${blocking.join(', ')}` : ''} (${fn.file})`;
}
