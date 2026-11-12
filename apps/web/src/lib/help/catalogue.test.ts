// Unit tests for the pure help index: ordering, grouping, route matching and
// search ranking.
//   npx tsx --test src/lib/help/catalogue.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHelpIndex } from './catalogue';
import type { Guide } from './types';

function guide(over: Partial<Guide> & Pick<Guide, 'id'>): Guide {
	return {
		title: over.id,
		summary: 'A summary.',
		kind: 'how-to',
		category: 'running',
		audience: ['everyone'],
		platforms: ['web'],
		sections: [{ heading: 'Body', blocks: [{ type: 'p', text: 'Nothing here.' }] }],
		...over,
	};
}

const fixtures: Guide[] = [
	guide({ id: 'zeta', title: 'Zeta', category: 'account' }),
	guide({ id: 'beta', title: 'Beta', category: 'races', kind: 'explainer' }),
	guide({ id: 'alpha', title: 'Alpha', category: 'races' }),
	guide({ id: 'start', title: 'Start', category: 'races', kind: 'start', routes: ['/races', '/races/[id]'] }),
	guide({
		id: 'cafe',
		title: 'Café meetups',
		summary: 'Where the club meets after a run.',
		category: 'clubs',
		routes: ['/races'],
	}),
	guide({
		id: 'body',
		title: 'Something else',
		category: 'clubs',
		sections: [{ heading: 'Details', blocks: [{ type: 'steps', items: ['Open **Meetups** first.'] }] }],
	}),
	guide({ id: 'sum', title: 'Another', summary: 'All about meetups.', category: 'clubs' }),
];

const index = createHelpIndex(fixtures);

test('allGuides orders by category, then start / how-to / explainer, then title', () => {
	assert.deepEqual(
		index.allGuides().map((g) => g.id),
		['start', 'alpha', 'beta', 'sum', 'cafe', 'body', 'zeta'],
	);
});

test('guideFor finds by id and misses cleanly', () => {
	assert.equal(index.guideFor('alpha')?.title, 'Alpha');
	assert.equal(index.guideFor('nope'), undefined);
});

test('guidesByCategory follows the category order and omits empty ones', () => {
	assert.deepEqual(
		index.guidesByCategory().map((g) => [g.category, g.guides.length]),
		[
			['races', 3],
			['clubs', 3],
			['account', 1],
		],
	);
});

test('guidesForRoute matches the exact route id only', () => {
	assert.deepEqual(
		index.guidesForRoute('/races').map((g) => g.id),
		['start', 'cafe'],
	);
	assert.deepEqual(index.guidesForRoute('/races/[id]').map((g) => g.id), ['start']);
	assert.deepEqual(index.guidesForRoute('/rac'), []);
});

test('search ranks a title match over a summary match over a body match', () => {
	assert.deepEqual(
		index.searchGuides('meetups').map((g) => g.id),
		['cafe', 'sum', 'body'],
	);
});

test('search ignores case and accents in both directions', () => {
	assert.deepEqual(index.searchGuides('CAFE').map((g) => g.id), ['cafe']);
	assert.deepEqual(index.searchGuides('café').map((g) => g.id), ['cafe']);
});

test('search needs every word, and an empty query finds nothing', () => {
	assert.deepEqual(index.searchGuides('cafe zzz'), []);
	assert.deepEqual(index.searchGuides('   '), []);
	assert.deepEqual(index.searchGuides('club meets').map((g) => g.id), ['cafe']);
});

test('search reads markup as its labels, not its syntax', () => {
	assert.deepEqual(index.searchGuides('**').map((g) => g.id), []);
});

