import { test } from 'node:test';
import assert from 'node:assert/strict';
import { leaveDecision } from './leave_guard.ts';

const base = { leaving: false, busy: false, dirty: false, unload: false };

test('a clean, idle form leaves freely', () => {
	assert.equal(leaveDecision(base), 'allow');
	assert.equal(leaveDecision({ ...base, unload: true }), 'allow');
});

test('a confirmed leave is never asked again', () => {
	assert.equal(leaveDecision({ ...base, leaving: true, busy: true, dirty: true }), 'allow');
});

test('unsaved input asks before discarding', () => {
	assert.equal(leaveDecision({ ...base, dirty: true }), 'ask');
});

test('a create in flight refuses, even over unsaved input', () => {
	assert.equal(leaveDecision({ ...base, busy: true }), 'busy');
	assert.equal(leaveDecision({ ...base, busy: true, dirty: true }), 'busy');
});

test('closing the tab hands either case to the browser prompt', () => {
	assert.equal(leaveDecision({ ...base, dirty: true, unload: true }), 'browser');
	assert.equal(leaveDecision({ ...base, busy: true, unload: true }), 'browser');
});
