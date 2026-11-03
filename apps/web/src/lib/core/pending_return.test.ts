import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	PENDING_RETURN_KEY,
	PENDING_RETURN_TTL_MS,
	stashPendingReturn,
	takePendingReturn,
	type ReturnStore,
} from './pending_return.js';

function memoryStore(): ReturnStore & { map: Map<string, string> } {
	const map = new Map<string, string>();
	return {
		map,
		getItem: (k) => map.get(k) ?? null,
		setItem: (k, v) => void map.set(k, v),
		removeItem: (k) => void map.delete(k),
	};
}

test('a stashed invite survives to the callback, once', () => {
	const s = memoryStore();
	stashPendingReturn(s, '/challenges/join/abc', 1000);
	assert.equal(takePendingReturn(s, 2000), '/challenges/join/abc');
	assert.equal(takePendingReturn(s, 2000), null);
});

test('the default landing is not stashed, and clears an older stash', () => {
	const s = memoryStore();
	stashPendingReturn(s, '/clubs/join/x', 1000);
	stashPendingReturn(s, '/dashboard', 1000);
	assert.equal(s.map.has(PENDING_RETURN_KEY), false);
});

test('an off-origin target is never stashed or returned', () => {
	const s = memoryStore();
	stashPendingReturn(s, '//evil.example/x', 1000);
	assert.equal(takePendingReturn(s, 1000), null);
	s.setItem(PENDING_RETURN_KEY, JSON.stringify({ to: '/\\evil.example', at: 1000 }));
	assert.equal(takePendingReturn(s, 1000), null);
});

test('a stash older than a day, or from the future, is dropped', () => {
	const s = memoryStore();
	stashPendingReturn(s, '/challenges/join/abc', 0);
	assert.equal(takePendingReturn(s, PENDING_RETURN_TTL_MS + 1), null);
	stashPendingReturn(s, '/challenges/join/abc', 5000);
	assert.equal(takePendingReturn(s, 1000), null);
});

test('malformed storage and a throwing store read as nothing', () => {
	const s = memoryStore();
	s.setItem(PENDING_RETURN_KEY, 'not json');
	assert.equal(takePendingReturn(s, 0), null);
	const throwing: ReturnStore = {
		getItem: () => {
			throw new Error('blocked');
		},
		setItem: () => {
			throw new Error('blocked');
		},
		removeItem: () => {
			throw new Error('blocked');
		},
	};
	assert.doesNotThrow(() => stashPendingReturn(throwing, '/challenges/join/abc'));
	assert.equal(takePendingReturn(throwing), null);
	assert.equal(takePendingReturn(null), null);
});
