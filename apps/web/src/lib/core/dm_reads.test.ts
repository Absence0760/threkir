// The direct-message reads in data.ts, pinned by shape. Invocation:
//   npx tsx --test src/lib/core/dm_reads.test.ts
//
// data.ts pulls in the Svelte stores and the Supabase client, so it cannot be
// imported under tsx; the paging arithmetic itself is unit-tested in
// social/dm_thread.test.ts and this file pins that the reader uses it.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from './strip_comments.ts';

const source = stripComments(readFileSync(resolve(import.meta.dirname, 'data.ts'), 'utf-8'));

function body(name: string): string {
	const start = source.lastIndexOf(`export async function ${name}(`);
	assert.ok(start >= 0, `Could not locate ${name} — rename?`);
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next === -1 ? undefined : next);
}

test('fetchDmThread reads from the newest end by keyset, not the oldest 200', () => {
	// It read `created_at` ascending with `.limit(200)`, so past 200 messages
	// the newest never showed (decisions § 1916 follow-up).
	const fn = body('fetchDmThread');
	assert.match(fn, /before\?: DmOrderKey/, 'the reader must take the oldest message shown');
	assert.match(fn, /query\.or\(dmPageBeforeFilter\(opts\.before\)\)/, 'an older page must start before it');
	assert.match(
		fn,
		/for \(const k of DM_THREAD_ORDER\)[\s\S]*?\.order\(k\.column/,
		'the read must sort by the order its cursor is taken in',
	);
	assert.match(fn, /\.limit\(limit \+ 1\)/, 'one row past the page says whether older messages exist');
	assert.match(fn, /dmPageFromRows\(/, 'the newest-first rows must be turned into an oldest-first page');
	assert.doesNotMatch(fn, /ascending: true/, 'an ascending read stops at the oldest messages');
	assert.doesNotMatch(fn, /limit = 200/);
});

test('fetchDmThread matches the pair with two in filters, leaving the one or= to the keyset', () => {
	const fn = body('fetchDmThread');
	assert.match(fn, /\.in\('sender_id', pair\)/);
	assert.match(fn, /\.in\('recipient_id', pair\)/);
	assert.equal((fn.match(/\.or\(/g) ?? []).length, 1, 'the keyset is the only or= tree');
});
