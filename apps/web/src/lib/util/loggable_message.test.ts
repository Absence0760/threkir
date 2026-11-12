import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loggableMessage, LOGGED_MESSAGE_MAX_CHARS } from './loggable_message';

test('a quoted value is blanked', () => {
	assert.equal(
		loggableMessage('invalid input syntax for type uuid: "a-runner-typed-this"'),
		'invalid input syntax for type uuid: "…"',
	);
	assert.equal(loggableMessage("submit_report: target 'run' x not found"), "submit_report: target '…' x not found");
});

test('a key detail is blanked', () => {
	assert.equal(
		loggableMessage('Key (email)=(runner@example.com) already exists.'),
		'Key (…)=(…) already exists.',
	);
});

test('an email address is blanked', () => {
	assert.equal(loggableMessage('no account for runner@example.com'), 'no account for <email>');
});

test('a long message is cut to the cap and says so', () => {
	const long = loggableMessage('x'.repeat(500));
	assert.equal(long.length, LOGGED_MESSAGE_MAX_CHARS);
	assert.ok(long.endsWith('…'));
	assert.equal(loggableMessage('x'.repeat(LOGGED_MESSAGE_MAX_CHARS)), 'x'.repeat(LOGGED_MESSAGE_MAX_CHARS));
});

test('text with nothing to blank passes through', () => {
	assert.equal(loggableMessage('Failed to fetch'), 'Failed to fetch');
});
