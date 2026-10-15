import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { appendPage } from './offset_page';

const id = (r: { id: string }) => r.id;
const rows = (...ids: string[]) => ids.map((i) => ({ id: i }));

test('a follow between two newest-first reads does not repeat the overlapped row', () => {
	// Page 1 of a newest-first follower list is f5..f4 (page size 2). Someone
	// follows (f6) before "load more", so offset 2 now starts at f4 — the row
	// page 1 already ended on. Appended blindly, f4 renders twice and the
	// keyed follower list on /u/[id] throws each_key_duplicate.
	const page1 = rows('f5', 'f4');
	const page2 = rows('f4', 'f3');
	const merged = appendPage(page1, page2, id);
	assert.deepEqual(merged.map(id), ['f5', 'f4', 'f3']);
	const keys = merged.map(id);
	assert.equal(new Set(keys).size, keys.length);
});

test('a page with no overlap appends in order', () => {
	assert.deepEqual(appendPage(rows('a', 'b'), rows('c', 'd'), id).map(id), ['a', 'b', 'c', 'd']);
});

test('the row already shown keeps its place and its value', () => {
	const shown = [{ id: 'a', v: 1 }];
	const merged = appendPage(shown, [{ id: 'a', v: 2 }, { id: 'b', v: 3 }], (r) => r.id);
	assert.deepEqual(merged, [
		{ id: 'a', v: 1 },
		{ id: 'b', v: 3 },
	]);
});

test('duplicates inside one page collapse too', () => {
	assert.deepEqual(appendPage([], rows('a', 'a', 'b'), id).map(id), ['a', 'b']);
});

test('the shown list is not mutated', () => {
	const shown = rows('a');
	appendPage(shown, rows('b'), id);
	assert.deepEqual(shown.map(id), ['a']);
});
