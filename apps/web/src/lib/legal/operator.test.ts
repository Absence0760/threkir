import { strict as assert } from 'node:assert';
import { test } from 'node:test';

import { NOT_PROVIDED, OPERATOR, operatorFactsComplete, type OperatorFacts } from './operator';

const rep = { name: 'Rep Ltd', address: '1 Example St, Dublin', email: 'rep@example.com' };

const complete: OperatorFacts = {
	serviceName: 'Threkir',
	controllerDescription: 'Test operator',
	postalAddress: '123 Main St',
	governingLaw: 'the State of Example, USA',
	euRepresentative: rep,
	ukRepresentative: rep,
};

test('complete facts pass', () => {
	assert.equal(operatorFactsComplete(complete), true);
});

test('any single null fact fails closed', () => {
	for (const key of [
		'postalAddress',
		'governingLaw',
		'euRepresentative',
		'ukRepresentative',
	] as const) {
		assert.equal(operatorFactsComplete({ ...complete, [key]: null }), false, key);
	}
});

test('a fact the operator declined to provide is decided, not pending', () => {
	for (const key of ['postalAddress', 'euRepresentative', 'ukRepresentative'] as const) {
		assert.equal(operatorFactsComplete({ ...complete, [key]: NOT_PROVIDED }), true, key);
	}
});

test('the shipped OPERATOR constant never claims completeness with a null fact', () => {
	const allFilled =
		OPERATOR.postalAddress !== null &&
		OPERATOR.governingLaw !== null &&
		OPERATOR.euRepresentative !== null &&
		OPERATOR.ukRepresentative !== null;
	assert.equal(operatorFactsComplete(OPERATOR), allFilled);
});
