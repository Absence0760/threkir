import { test } from 'node:test';
import assert from 'node:assert/strict';
import { entryNumbers, nextFree } from './next_decision_number.mjs';

test('entryNumbers reads only level-two numbered headings', () => {
	assert.deepEqual(entryNumbers('# Decisions\n## 1. a\ntext ## 9. not\n### 5. no\n## 12. b\n'), [1, 12]);
});

test('nextFree skips every number an open PR already holds above main', () => {
	const byRef = new Map([
		['origin/main', [2580, 2581, 2583]],
		['#1 a', [2580, 2581, 2582]],
		['#2 b', [2580, 2581, 2588]],
		['#3 c', [2580, 2581]],
	]);
	assert.deepEqual(nextFree(byRef), {
		next: 2589,
		claims: [
			{ ref: '#2 b', numbers: [2588] },
		],
	});
});

test('nextFree with no open PRs is main plus one', () => {
	assert.equal(nextFree(new Map([['origin/main', [1, 2, 3]]])).next, 4);
});
