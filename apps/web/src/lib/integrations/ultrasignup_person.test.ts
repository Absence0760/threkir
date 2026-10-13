import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	linkFromCandidate,
	parseUltraSignUpCandidates,
	ULTRASIGNUP_NAME_MAX_LEN,
	ultraSignUpLinkFromRow,
	ultraSignUpNameReady
} from './ultrasignup_person';

test('a lookup answer is read candidate by candidate', () => {
	const out = parseUltraSignUpCandidates({
		candidates: [
			{
				id: '900001',
				firstName: 'Alex',
				lastName: 'Sample',
				age: 41,
				resultCount: 4,
				recentEvents: [
					{ name: 'Example Peaks 100 Mile', date: '2025-06-20' },
					{ name: 'Undated Race', date: null }
				]
			},
			{ id: '900002', firstName: 'Alex', lastName: 'Sample', age: null, resultCount: 1 }
		]
	});
	assert.deepEqual(out, [
		{
			id: '900001',
			firstName: 'Alex',
			lastName: 'Sample',
			age: 41,
			resultCount: 4,
			recentEvents: [
				{ name: 'Example Peaks 100 Mile', date: '2025-06-20' },
				{ name: 'Undated Race', date: null }
			]
		},
		{
			id: '900002',
			firstName: 'Alex',
			lastName: 'Sample',
			age: null,
			resultCount: 1,
			recentEvents: []
		}
	]);
});

test('a candidate that could never be stored is not offered', () => {
	// The stored row's CHECK wants a numeric id and both name halves; a row
	// without them would fail at the save, one step after the runner picked it.
	const out = parseUltraSignUpCandidates({
		candidates: [
			{ id: '0', firstName: 'A', lastName: 'B' },
			{ id: 'abc', firstName: 'A', lastName: 'B' },
			{ id: 900003, firstName: 'A', lastName: 'B' },
			{ id: '900004', firstName: '', lastName: 'B' },
			null,
			'x',
			{ id: '900005', firstName: 'A', lastName: 'B', age: -3, resultCount: 'many' }
		]
	});
	assert.deepEqual(
		out.map((c) => [c.id, c.age, c.resultCount]),
		[['900005', null, 0]]
	);
});

test('anything but the envelope is no candidates, not a guess', () => {
	for (const payload of [null, undefined, [], {}, { candidates: 'x' }, { error: 'nope' }]) {
		assert.deepEqual(parseUltraSignUpCandidates(payload), []);
	}
});

test('a picked candidate keeps UltraSignup\'s spelling of the name', () => {
	assert.deepEqual(
		linkFromCandidate({
			id: '900001',
			firstName: 'Alex',
			lastName: 'Sample',
			age: null,
			resultCount: 0,
			recentEvents: []
		}),
		{ personId: '900001', firstName: 'Alex', lastName: 'Sample' }
	);
});

test('the stored row is a link only when it is a whole one', () => {
	const row = { external_id: '900001', external_first_name: 'Alex', external_last_name: 'Sample' };
	assert.deepEqual(ultraSignUpLinkFromRow(row), {
		personId: '900001',
		firstName: 'Alex',
		lastName: 'Sample'
	});
	assert.equal(ultraSignUpLinkFromRow(null), null);
	assert.equal(ultraSignUpLinkFromRow({ ...row, external_id: null }), null);
	assert.equal(ultraSignUpLinkFromRow({ ...row, external_id: 'uid-42' }), null);
	assert.equal(ultraSignUpLinkFromRow({ ...row, external_last_name: ' ' }), null);
});

test('a name is ready to look up when both halves are present and within the cap', () => {
	assert.equal(ultraSignUpNameReady('Alex', 'Sample'), true);
	assert.equal(ultraSignUpNameReady('  ', 'Sample'), false);
	assert.equal(ultraSignUpNameReady('Alex', ''), false);
	assert.equal(ultraSignUpNameReady('a'.repeat(ULTRASIGNUP_NAME_MAX_LEN), 'B'), true);
	assert.equal(ultraSignUpNameReady('a'.repeat(ULTRASIGNUP_NAME_MAX_LEN + 1), 'B'), false);
});
