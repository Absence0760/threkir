// The load-more readers page by keyset, not by offset. Invocation:
//   npx tsx --test src/lib/core/keyset_readers.test.ts
//
// An offset is a position. Delete one row from page 1 between two reads and
// offset 50 starts at what was row 51, so a row is never shown; the list looks
// complete and is not. Each reader below takes the previous page's cursor
// (`after`) and builds its filter with `keysetAfter`, so a page starts strictly
// after the last row shown wherever that row now sits. This pins the shape so
// a later edit cannot quietly put the offset back.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from './strip_comments.ts';

const source = stripComments(readFileSync(resolve(import.meta.dirname, 'data.ts'), 'utf-8'));

/** The body of `export async function <name>(`, to the next top-level export. */
function body(name: string): string {
	const start = source.indexOf(`export async function ${name}(`);
	assert.ok(start >= 0, `Could not locate ${name} — rename?`);
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next === -1 ? undefined : next);
}

const READERS = ['fetchFollowers', 'fetchFollowing'];

for (const name of READERS) {
	test(`${name} pages by keyset cursor, not by offset`, () => {
		const fn = body(name);
		assert.match(fn, /after\?: KeysetCursor \| null/, `${name} must take the previous page's cursor`);
		assert.match(fn, /keysetAfter\(/, `${name} must filter to the rows after the cursor`);
		assert.match(fn, /nextCursor\(/, `${name} must hand back the cursor of the last row it read`);
		assert.doesNotMatch(fn, /\boffset\b/, `${name} must not page by offset`);
		assert.doesNotMatch(fn, /\.range\(/, `${name} must not page with .range()`);
	});
}
