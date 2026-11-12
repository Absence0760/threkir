import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { canEditDm, DM_EDIT_WINDOW_MS } from './dm_edit.ts';

const me = 'me';
const sent = '2026-11-08T10:00:00.000Z';
const at = (minutes: number) => Date.parse(sent) + minutes * 60_000;
const msg = (over: Partial<{ sender_id: string; unsent_at: string | null; body: string | null; created_at: string; kind: string }> = {}) => ({
	sender_id: me,
	created_at: sent,
	unsent_at: null,
	body: 'hello',
	...over,
});

test('the window is the one edit_direct_message enforces', () => {
	const dir = fileURLToPath(new URL('../../../../backend/supabase/migrations/', import.meta.url));
	const file = readdirSync(dir).find((f) => f.endsWith('_dm_edit.sql'));
	assert.ok(file, 'the dm_edit migration is missing — re-anchor');
	const sql = readFileSync(dir + file, 'utf8');
	const m = sql.match(/c_window constant interval := interval '(\d+) minutes'/);
	assert.ok(m, 'c_window not found in the migration — re-anchor');
	assert.equal(DM_EDIT_WINDOW_MS, Number(m[1]) * 60_000);
});

test('the sender can edit a live message inside the window', () => {
	assert.equal(canEditDm(msg(), me, at(0)), true);
	assert.equal(canEditDm(msg(), me, at(14)), true);
	assert.equal(canEditDm(msg(), me, at(15)), true);
});

test('not past the window', () => {
	assert.equal(canEditDm(msg(), me, at(15) + 1), false);
	assert.equal(canEditDm(msg(), me, at(60)), false);
});

test('a created_at ahead of the local clock counts as just sent', () => {
	assert.equal(canEditDm(msg(), me, at(-2)), true);
});

test('not someone else\'s message, and not with no viewer', () => {
	assert.equal(canEditDm(msg({ sender_id: 'them' }), me, at(1)), false);
	assert.equal(canEditDm(msg(), null, at(1)), false);
	assert.equal(canEditDm(msg(), undefined, at(1)), false);
});

test('not an unsent message', () => {
	assert.equal(canEditDm(msg({ unsent_at: sent, body: null }), me, at(1)), false);
	assert.equal(canEditDm(msg({ body: null }), me, at(1)), false);
});

test('not a shared AI Coach answer', () => {
	assert.equal(canEditDm(msg({ kind: 'coach_share' }), me, at(1)), false);
	assert.equal(canEditDm(msg({ kind: 'group_renamed' }), me, at(1)), false);
	assert.equal(canEditDm(msg({ kind: 'text' }), me, at(1)), true);
});

test('not a message with an unreadable timestamp', () => {
	assert.equal(canEditDm(msg({ created_at: 'not a date' }), me, at(1)), false);
});
