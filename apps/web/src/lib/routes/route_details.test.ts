// Invocation:
//   npx tsx --test src/lib/routes/route_details.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { routeDetailsPatch, type RouteDetails } from './route_details';
import { lengthLimit } from '../core/column_limits';

const loaded: RouteDetails = { name: 'Allianz Richmond Marathon 2026', description: null };

test('a rename writes only the name', () => {
	assert.deepEqual(
		routeDetailsPatch(loaded, { ...loaded, name: 'Richmond Marathon 2026 course (unofficial)' }),
		{ kind: 'patch', patch: { name: 'Richmond Marathon 2026 course (unofficial)' } },
	);
});

test('a description edit writes only the description', () => {
	assert.deepEqual(routeDetailsPatch(loaded, { ...loaded, description: 'Redrawn from OSM.' }), {
		kind: 'patch',
		patch: { description: 'Redrawn from OSM.' },
	});
});

test('both fields are trimmed before comparing and writing', () => {
	assert.deepEqual(
		routeDetailsPatch(loaded, { name: '  New name  ', description: '\n Notes \n' }),
		{ kind: 'patch', patch: { name: 'New name', description: 'Notes' } },
	);
});

test('untouched or whitespace-only changes write nothing', () => {
	assert.deepEqual(routeDetailsPatch(loaded, { ...loaded }), { kind: 'unchanged' });
	assert.deepEqual(routeDetailsPatch(loaded, { name: ` ${loaded.name} `, description: '   ' }), {
		kind: 'unchanged',
	});
});

test('clearing a description stores null', () => {
	const described: RouteDetails = { name: 'Loop', description: 'Old text' };
	assert.deepEqual(routeDetailsPatch(described, { name: 'Loop', description: '  ' }), {
		kind: 'patch',
		patch: { description: null },
	});
});

test('a blank name is refused', () => {
	assert.deepEqual(routeDetailsPatch(loaded, { ...loaded, name: '   ' }), { kind: 'nameRequired' });
});

test('text past the column caps is refused, and text at the caps is not', () => {
	const nameMax = lengthLimit('routes.name');
	const descMax = lengthLimit('routes.description');
	assert.deepEqual(routeDetailsPatch(loaded, { ...loaded, name: 'a'.repeat(nameMax + 1) }), {
		kind: 'tooLong',
		field: 'name',
	});
	assert.deepEqual(
		routeDetailsPatch(loaded, { ...loaded, description: 'a'.repeat(descMax + 1) }),
		{ kind: 'tooLong', field: 'description' },
	);
	assert.equal(
		routeDetailsPatch(loaded, { name: 'a'.repeat(nameMax), description: 'a'.repeat(descMax) }).kind,
		'patch',
	);
});
