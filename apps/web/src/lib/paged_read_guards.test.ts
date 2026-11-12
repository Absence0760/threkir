// Every whole-table read composes into the whole table, or it composes into
// something nobody can name. Invocation:
//   npx tsx --test src/lib/paged_read_guards.test.ts
//
// PostgREST turns `.range(from, to)` into LIMIT/OFFSET, and an OFFSET names a
// position. Postgres makes no promise about the order of rows a query does not
// order, nor which of two equal sort keys comes first, so an OFFSET walk over
// a non-unique ORDER BY can return a row on a page boundary twice and another
// not at all. Ending the order on a unique column fixed that, and was this
// guard's first rule. It does not fix the other half: a row inserted or
// deleted while the walk is between two pages moves every later position, so
// the next OFFSET starts a row early or late even over a total order.
// `createBackup` writes a manifest saying `complete` over such a walk; the
// account export, the recap and the heatmap read the history through one; the
// two ZIP importers build their dedupe set from one, where a dropped row
// re-imports a run the runner already has.
//
// So the rule now is: no `.range()` read at all. A load-more list pages by
// keyset cursor (`core/keyset_readers.test.ts`), and an every-row read walks
// by one through `walkKeyset` (`core/keyset_page.ts`, decisions § 1936) —
// over an order that ends on a column unique per row, and sorted by the same
// key spec the cursor is read from.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { stripComments } from './core/strip_comments';

const srcRoot = resolve(import.meta.dirname, '..');

/**
 * Columns that are unique within one query's result set, so an ordering
 * ending on one is a total order. `id` is every table's primary key here;
 * the two membership tables are keyed on a pair whose other half the query
 * already fixes with `.eq()`, which is why their own readers tiebreak on the
 * user — or, for a user's own clubs, on the club — rather than on an id they
 * do not have.
 */
const UNIQUE_TIEBREAKS = ['id', 'user_id', 'club_id', 'follower_id', 'followee_id'];

function sources(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) {
			if (entry === 'node_modules' || entry === '.svelte-kit') continue;
			out.push(...sources(full));
			continue;
		}
		if (!/\.(ts|svelte)$/.test(entry)) continue;
		if (/\.test\.ts$/.test(entry)) continue;
		out.push(full);
	}
	return out;
}

/**
 * The chained builder call each `.range(` sits at the end of, as raw text.
 * Walked BACKWARDS over balanced brackets rather than sliced at the nearest
 * delimiter, because `.order('x', { ascending: false })` puts a brace inside
 * every chain this guard is about.
 */
function chainsEndingInRange(src: string): { line: number; chain: string }[] {
	const out: { line: number; chain: string }[] = [];
	for (const m of src.matchAll(/\.range\(/g)) {
		const at = m.index;
		let depth = 0;
		let i = at - 1;
		for (; i >= 0; i--) {
			const c = src[i];
			if (c === ')' || c === ']' || c === '}') depth++;
			else if (c === '(' || c === '[' || c === '{') {
				if (depth === 0) break;
				depth--;
			} else if (depth === 0 && (c === ';' || c === ',')) break;
			else if (depth === 0 && c === '>' && src[i - 1] === '=') break;
		}
		out.push({
			line: src.slice(0, at).split('\n').length,
			chain: src.slice(i + 1, at),
		});
	}
	return out;
}

/** Every `.order('col'` in a chunk of source, in order. */
function orderKeys(text: string): string[] {
	return [...text.matchAll(/\.order\(\s*['"]([A-Za-z_][\w]*)['"]/g)].map((m) => m[1]);
}

test('no read pages by offset: `.range()` is gone from the tree', () => {
	const offenders: string[] = [];
	for (const file of sources(srcRoot)) {
		const src = stripComments(readFileSync(file, 'utf-8'));
		for (const { line, chain } of chainsEndingInRange(src)) {
			const rel = file.slice(resolve(srcRoot, '..').length + 1);
			const orders = orderKeys(chain);
			offenders.push(
				`${rel}:${line}: an OFFSET walk${orders.length ? ` over ${orders.join(', ')}` : ''} — use walkKeyset`,
			);
		}
	}
	assert.deepEqual(
		offenders.sort(),
		[],
		'`.range()` pages by OFFSET, so a row inserted or deleted between two pages ' +
			'is skipped or repeated. Walk by keyset cursor (`walkKeyset` in core/keyset_page.ts).',
	);
});

/** Every `const NAME: readonly KeysetKey[] = [ ... ]` in the tree, by name → file → columns. */
function keysetOrders(): Map<string, Map<string, string[]>> {
	const out = new Map<string, Map<string, string[]>>();
	for (const file of sources(srcRoot)) {
		const src = stripComments(readFileSync(file, 'utf-8'));
		for (const m of src.matchAll(/\bconst\s+([A-Z_][A-Z0-9_]*)\s*:\s*readonly KeysetKey\[\]\s*=\s*\[([^\]]*)\]/g)) {
			const columns = [...m[2].matchAll(/column:\s*'([a-z_][a-z0-9_]*)'/g)].map((c) => c[1]);
			if (!out.has(m[1])) out.set(m[1], new Map());
			out.get(m[1])!.set(file, columns);
		}
	}
	return out;
}

test('every keyset walk runs over a total order that something sorts by', () => {
	const orders = keysetOrders();
	const offenders: string[] = [];
	let walks = 0;
	const allSource = sources(srcRoot)
		.map((f) => stripComments(readFileSync(f, 'utf-8')))
		.join('\n');
	for (const file of sources(srcRoot)) {
		if (file.endsWith('core/keyset_page.ts')) continue;
		const src = stripComments(readFileSync(file, 'utf-8'));
		const rel = file.slice(resolve(srcRoot, '..').length + 1);
		for (const m of src.matchAll(/\bwalkKeyset\b[^(]*\(\s*([A-Z_][A-Z0-9_]*)\s*,/g)) {
			walks++;
			const name = m[1];
			const declared = orders.get(name);
			const columns = declared?.get(file) ?? (declared?.size === 1 ? [...declared.values()][0] : undefined);
			if (!columns) {
				offenders.push(`${rel}: walkKeyset(${name}) — order not resolvable as a KeysetKey[] literal`);
				continue;
			}
			const last = columns[columns.length - 1];
			if (!UNIQUE_TIEBREAKS.includes(last)) {
				offenders.push(`${rel}: walkKeyset(${name}) ends its order on \`${last}\`, which is not unique`);
			}
			const sorts = new RegExp(`for \\(const (\\w+) of ${name}\\)[\\s\\S]{0,40}?\\.order\\(\\1\\.column`);
			if (!sorts.test(allSource)) {
				offenders.push(`${rel}: nothing sorts by ${name}, so its cursor names a row in an order the read does not use`);
			}
		}
	}

	// Population: a walk that resolved nothing would satisfy the assertion
	// below while proving nothing. Nine today — fetchRuns, the exercise
	// catalogue, the backup's runs and routes, the three ZIP-import reads, and
	// the caller's clubs and a club's pending requests (§ 1940).
	assert.ok(walks >= 9, `only found ${walks} walkKeyset calls — walker broken?`);
	assert.deepEqual(offenders.sort(), []);
});
