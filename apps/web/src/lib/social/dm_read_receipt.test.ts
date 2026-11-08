import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dmMarkReadThrough, seenReceipt } from './dm_read_receipt.ts';

const me = 'me';
const them = 'them';
const msg = (id: string, sender_id: string, seen_at: string | null = null) => ({ id, sender_id, seen_at });

test('seenReceipt is the viewer\'s newest seen message', () => {
	const list = [
		msg('1', me, '2026-11-07T10:00:00Z'),
		msg('2', me, '2026-11-07T10:01:00Z'),
		msg('3', them),
		msg('4', me),
	];
	assert.equal(seenReceipt(list, me)?.id, '2');
});

test('seenReceipt ignores the partner\'s messages and unseen ones', () => {
	assert.equal(seenReceipt([msg('1', them, '2026-11-07T10:00:00Z'), msg('2', me)], me), null);
});

test('seenReceipt is null with no viewer or no messages', () => {
	assert.equal(seenReceipt([msg('1', me, '2026-11-07T10:00:00Z')], null), null);
	assert.equal(seenReceipt([], me), null);
});

test('dmMarkReadThrough is the newest partner message', () => {
	const list = [msg('1', them), msg('2', them), msg('3', me)];
	assert.equal(dmMarkReadThrough(list, them, null), '2');
});

test('dmMarkReadThrough is null once that message is marked', () => {
	const list = [msg('1', them), msg('2', them), msg('3', me)];
	assert.equal(dmMarkReadThrough(list, them, '2'), null);
});

test('dmMarkReadThrough moves on when a newer partner message arrives', () => {
	const list = [msg('1', them), msg('2', them), msg('3', them)];
	assert.equal(dmMarkReadThrough(list, them, '2'), '3');
});

test('dmMarkReadThrough is null with nothing from the partner', () => {
	assert.equal(dmMarkReadThrough([msg('1', me)], them, null), null);
	assert.equal(dmMarkReadThrough([], them, null), null);
});
