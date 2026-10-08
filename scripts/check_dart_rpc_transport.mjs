#!/usr/bin/env node
// Every Dart `.rpc()` goes out with the HTTP method its function can take.
//
// The Dart twin of apps/web/src/lib/rpc_transport_guard.test.ts, and held to
// the same rule through the same module: scripts/rpc_transport.mjs reads the
// migrations and says which `public` functions can take a GET (`stable` or
// `immutable`, every input a scalar, no argument named like a PostgREST
// directive) and why. Web moved every such call to a GET under § 1735; the
// Dart clients kept POSTing them, and nothing said so, until § 1803.
//
// postgrest-dart 2.8.0 sends `rpc(fn, params:, get: true)` as a GET and
// retries a GET or HEAD on 503/520; a POST is sent once. Its GET path differs
// from supabase-js in two ways this guard has to know about:
//
//   - A GET with no `params` map THROWS (`ArgumentError: argument must be a
//     Map`) before any request is made. A no-argument function therefore
//     needs `params: const {}` beside `get: true`.
//   - Each value is interpolated with `'$value'`, so a null becomes the
//     string "null" exactly as it does on web. The Dart way to omit an
//     argument is a null-aware element (`'k': ?v`) or a collection-`if`
//     entry, and omitting is only equivalent to
//     sending null when the parameter's default IS null. Web's `undefined`
//     was always omitted from a POST body too, so web never changed what a
//     function received; a Dart POST sent the explicit null, so a Dart call
//     moving to a GET may only omit a parameter that defaults to NULL.
//
// What is read: every `packages/*/lib` and `apps/mobile_android/lib`
// (`apps/mobile_ios/lib` is its byte-identical twin, decisions § 39), comments
// blanked by comment_strip.mjs, `_test.dart` files skipped. A `params` map
// built elsewhere and passed by name cannot be read, so its entries are not
// checked; a map literal's are.
//
// Run:  node scripts/check_dart_rpc_transport.mjs
// Test: node --test scripts/check_dart_rpc_transport.test.mjs

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripComments } from './comment_strip.mjs';
import { balancedParen, explain, loadFunctions, splitTopLevel, takesGet } from './rpc_transport.mjs';

/** @typedef {import('./rpc_transport.mjs').Fn} Fn */

export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/**
 * A stable, all-scalar function that must still go out as a POST, with the
 * reason. Empty: none does today.
 * @type {Record<string, string>}
 */
export const POST_EXEMPT = {};

/**
 * @param {string} root
 * @returns {string[]} the Dart source roots, repo-relative
 */
export function sourceRoots(root = REPO_ROOT) {
	const packages = readdirSync(join(root, 'packages'))
		.filter((p) => statSync(join(root, 'packages', p)).isDirectory())
		.sort()
		.map((p) => `packages/${p}/lib`);
	return [...packages, 'apps/mobile_android/lib'];
}

/**
 * @param {string} [root]
 * @returns {Map<string, string>} repo-relative path → source, test files excluded
 */
export function collectFiles(root = REPO_ROOT) {
	/** @type {Map<string, string>} */
	const files = new Map();
	/** @param {string} dir */
	const walk = (dir) => {
		let entries;
		try {
			entries = readdirSync(dir, { withFileTypes: true });
		} catch {
			return;
		}
		for (const e of entries) {
			const p = join(dir, e.name);
			if (e.isDirectory()) walk(p);
			else if (e.name.endsWith('.dart') && !e.name.endsWith('_test.dart')) {
				files.set(relative(root, p).split(sep).join('/'), readFileSync(p, 'utf8'));
			}
		}
	};
	for (const r of sourceRoots(root)) walk(join(root, r));
	return files;
}

/**
 * @typedef {{ key: string | null, conditional: boolean, value: string }} Entry
 * `key` is null for an entry this cannot read (a spread, a `for`).
 */

/**
 * @typedef {{
 *   where: string, fn: string | null, get: boolean, getLiteral: boolean,
 *   params: string | null, entries: Entry[] | null
 * }} Site
 * `params` is the argument's source, null when absent; `entries` is null
 * unless it is a map literal.
 */

/**
 * The entries of a Dart map literal (`{…}`, `const {…}`, `<K, V>{…}`), or
 * null when the expression is anything else.
 * @param {string} expr
 * @returns {Entry[] | null}
 */
export function mapEntries(expr) {
	const m = /^(?:const\s+)?(?:<[^>{}]*>\s*)?\{([\s\S]*)\}$/.exec(expr.trim());
	if (!m) return null;
	return splitTopLevel(m[1]).map((raw) => {
		let text = raw.trim();
		let conditional = false;
		const cond = /^if\s*\(/.exec(text);
		if (cond) {
			const close = balancedParen(text, cond[0].length - 1);
			text = text.slice(close + 1).trim();
			conditional = true;
		}
		const kv = /^(['"])(\w+)\1\s*:\s*([\s\S]*)$/.exec(text);
		if (!kv) return { key: null, conditional, value: text };
		let value = kv[3].trim();
		// `'k': ?v` is a null-aware element: the entry is left out when v is null.
		if (/^\?(?!\?)/.test(value)) {
			value = value.slice(1).trim();
			conditional = true;
		}
		return { key: kv[2], conditional, value };
	});
}

/**
 * @param {string} rel
 * @param {string} raw Dart source
 * @returns {{ sites: Site[], unreadable: string[] }}
 */
export function readSites(rel, raw) {
	const src = stripComments(raw, 'dart');
	/** @type {Site[]} */
	const sites = [];
	/** @type {string[]} */
	const unreadable = [];
	for (const hit of src.matchAll(/\.rpc\s*(?:<[^>]*>)?\s*\(/g)) {
		const at = hit.index ?? 0;
		const where = `${rel}:${src.slice(0, at).split('\n').length}`;
		const open = at + hit[0].length - 1;
		const close = balancedParen(src, open);
		if (close === -1) {
			unreadable.push(`${where}: unbalanced .rpc( call`);
			continue;
		}
		const parts = splitTopLevel(src.slice(open + 1, close)).map((p) => p.trim());
		const name = /^(['"])(\w+)\1$/.exec(parts[0] ?? '');
		/** @param {string} label */
		const named = (label) => {
			const p = parts.slice(1).find((x) => new RegExp(`^${label}\\s*:`).test(x));
			return p === undefined ? null : p.replace(new RegExp(`^${label}\\s*:`), '').trim();
		};
		const get = named('get');
		const params = named('params');
		if (!name) unreadable.push(`${where}: .rpc() is not called with a literal function name`);
		sites.push({
			where,
			fn: name ? name[2] : null,
			get: get === 'true',
			getLiteral: get === null || get === 'true' || get === 'false',
			params,
			entries: params === null ? null : mapEntries(params)
		});
	}
	return { sites, unreadable };
}

/**
 * @param {Map<string, string>} files
 * @param {Map<string, Fn>} functions live public functions by name
 * @param {Record<string, string>} [exempt]
 * @returns {{ findings: string[], sites: Site[] }}
 */
export function checkDartRpcTransport(files, functions, exempt = POST_EXEMPT) {
	/** @type {string[]} */
	const findings = [];
	/** @type {Site[]} */
	const sites = [];
	for (const [rel, src] of files) {
		const read = readSites(rel, src);
		findings.push(...read.unreadable);
		sites.push(...read.sites);
	}

	for (const s of sites) {
		if (s.fn === null) continue;
		if (!s.getLiteral) {
			findings.push(`${s.where} ${s.fn}: \`get:\` must be the literal true or false, so this guard can read the method`);
			continue;
		}
		const fn = functions.get(s.fn);
		if (!fn) {
			findings.push(`${s.where} ${s.fn}: no migration defines this function any more`);
			continue;
		}
		const eligible = takesGet(fn);
		if (eligible && !s.get && !(s.fn in exempt)) {
			findings.push(`${s.where} ${s.fn}: ${explain(fn)} — pass \`get: true\`${s.params === null ? ' and `params: const {}`' : ''}`);
		}
		if (!s.get) continue;
		if (!eligible) {
			findings.push(`${s.where} ${s.fn}: sent as a GET, but ${explain(fn)}`);
			continue;
		}
		if (s.params === null) {
			findings.push(`${s.where} ${s.fn}: a GET without a params map throws ArgumentError in postgrest-dart — pass \`params: const {}\``);
			continue;
		}
		if (s.entries === null) continue;
		const given = new Set();
		for (const e of s.entries) {
			if (e.key === null) {
				findings.push(`${s.where} ${s.fn}: \`${e.value}\` is not a map entry this guard can read; build the GET's params as plain or collection-if entries`);
				continue;
			}
			given.add(e.key);
			const arg = fn.args.find((a) => a.name === e.key);
			if (!arg) {
				findings.push(`${s.where} ${s.fn}.${e.key}: the function has no such parameter`);
				continue;
			}
			if (/\bnull\b/.test(e.value)) {
				findings.push(`${s.where} ${s.fn}.${e.key}: a GET sends null as the string "null" — omit the entry with a collection-if instead`);
			}
			if (e.conditional && !arg.defaultIsNull) {
				findings.push(
					`${s.where} ${s.fn}.${e.key}: omitted conditionally, but the parameter ${arg.hasDefault ? 'defaults to something other than NULL' : 'has no default'}, so omitting it is not the null the POST used to send`
				);
			}
		}
		for (const a of fn.args) {
			if (!a.hasDefault && !given.has(a.name)) {
				findings.push(`${s.where} ${s.fn}.${a.name}: a required parameter the GET never sends`);
			}
		}
	}

	for (const [name, reason] of Object.entries(exempt)) {
		const fn = functions.get(name);
		if (!fn || !takesGet(fn)) findings.push(`POST_EXEMPT ${name} (${reason}): no longer a GET candidate`);
		else if (!sites.some((s) => s.fn === name && !s.get)) findings.push(`POST_EXEMPT ${name} (${reason}): no POST call site left`);
	}
	return { findings, sites };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const { findings, sites } = checkDartRpcTransport(collectFiles(), loadFunctions());
	if (sites.length === 0) findings.push('no Dart .rpc() call site found — the scan has stopped matching the tree');
	if (findings.length > 0) {
		for (const f of findings) console.error(f);
		console.error(`\n${findings.length} Dart RPC transport finding(s).`);
		process.exit(1);
	}
	const gets = sites.filter((s) => s.get).length;
	console.log(`Dart RPC transport: ${sites.length} call sites, ${gets} sent as GET, ${sites.length - gets} as POST, each matching its function`);
}
