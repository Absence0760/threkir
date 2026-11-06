// Invocation:
//   npx tsx --test src/lib/routes/route_details.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	officialDistanceInputValue,
	parseOfficialDistanceInput,
	routeDetailsPatch,
	type RouteDetails,
} from './route_details';
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

const MILE = 1609.344;

test('an official distance typed in km is stored in metres', () => {
	assert.deepEqual(parseOfficialDistanceInput('42.195', 1000, 42670, null), { kind: 'set', officialM: 42195 });
	assert.deepEqual(parseOfficialDistanceInput(' 42,195 ', 1000, 42670, null), { kind: 'set', officialM: 42195 });
	assert.deepEqual(parseOfficialDistanceInput('21.0975', 1000, 21300, null), { kind: 'set', officialM: 21097.5 });
});

test('an official distance typed in miles converts at 1609.344 m', () => {
	assert.deepEqual(parseOfficialDistanceInput('26.21876', MILE, 42670, null), { kind: 'set', officialM: 42195 });
});

test('a blank official distance clears a stored one and leaves none alone', () => {
	assert.deepEqual(parseOfficialDistanceInput('  ', 1000, 42670, 42195), { kind: 'set', officialM: null });
	assert.deepEqual(parseOfficialDistanceInput('', 1000, 42670, null), { kind: 'unchanged' });
});

test('retyping the stored official distance writes nothing', () => {
	assert.deepEqual(parseOfficialDistanceInput('42.195', 1000, 42670, 42195), { kind: 'unchanged' });
	assert.deepEqual(parseOfficialDistanceInput('26.219', MILE, 42670, 42195), { kind: 'unchanged' });
});

test('an official distance is refused when not a number, not positive or over 10% off', () => {
	assert.deepEqual(parseOfficialDistanceInput('marathon', 1000, 42670, null), { kind: 'notANumber' });
	assert.deepEqual(parseOfficialDistanceInput('0', 1000, 42670, null), { kind: 'outOfRange' });
	assert.deepEqual(parseOfficialDistanceInput('-5', 1000, 42670, null), { kind: 'outOfRange' });
	assert.deepEqual(parseOfficialDistanceInput('50', 1000, 42670, null), { kind: 'tooFar' });
	assert.deepEqual(parseOfficialDistanceInput('38', 1000, 42670, null), { kind: 'tooFar' });
});

test('the edit field opens on the stored official distance in the viewer unit', () => {
	assert.equal(officialDistanceInputValue(42195, 1000), '42.195');
	assert.equal(officialDistanceInputValue(10000, 1000), '10');
	assert.equal(officialDistanceInputValue(42195, MILE), '26.219');
	assert.equal(officialDistanceInputValue(null, 1000), '');
});
