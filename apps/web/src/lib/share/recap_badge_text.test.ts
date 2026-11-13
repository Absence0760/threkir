// The trophy grid's words come from the reader's catalogue, by badge id, for
// a recap built here and for one read back out of a published snapshot.
// Invocation: npx tsx --test src/lib/share/recap_badge_text.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { interpolate } from '../i18n/interpolate';
import { en } from '../i18n/locales/en';
import { messages as fr } from '../i18n/locales/fr';
import type { MessageKey } from '../i18n/messages';
import { RECAP_BADGE_IDS } from '../runs/recap';
import { recapBadgeFromSnapshot, recapBadgeText } from './recap_card_text';

const tEn = (key: MessageKey, params?: Record<string, string | number>) => interpolate(en[key], params, 'en');
const tFr = (key: MessageKey, params?: Record<string, string | number>) => interpolate(fr[key], params, 'fr');

test('every badge id has a label and a detail in English', () => {
	for (const id of RECAP_BADGE_IDS) {
		const { label, detail } = recapBadgeText({ id, icon: 'x', value: id === 'early' || id === 'night' ? '05:10' : 4 }, tEn);
		assert.ok(label.length > 0, id);
		assert.ok(detail.length > 0, id);
		assert.doesNotMatch(detail, /[{}]/, `${id} left a placeholder: ${detail}`);
	}
});

test('a counted detail is a plural in the reader\'s language', () => {
	assert.equal(recapBadgeText({ id: 'pr-1', icon: 'trophy', value: 1 }, tEn).detail, '1 personal record');
	assert.equal(recapBadgeText({ id: 'pr-1', icon: 'trophy', value: 2 }, tEn).detail, '2 personal records');
	assert.equal(recapBadgeText({ id: 'streak-7', icon: 'x', value: 9 }, tFr).label, 'Série d\'une semaine');
	assert.equal(recapBadgeText({ id: 'night', icon: 'x', value: '22:15' }, tEn).detail, 'Out at 22:15');
});

test('a counted badge without its value shows the label alone', () => {
	assert.deepEqual(recapBadgeText({ id: 'months-6', icon: 'x' }, tEn), { label: 'Half the year', detail: '' });
});

test('a snapshot badge keeps its value, and an old English one gives it back from the detail', () => {
	assert.deepEqual(recapBadgeFromSnapshot({ id: 'streak-14', icon: 'local_fire_department', value: 16 }), {
		id: 'streak-14',
		icon: 'local_fire_department',
		value: 16,
	});
	assert.deepEqual(
		recapBadgeFromSnapshot({ id: 'streak-14', icon: 'local_fire_department', label: 'Fortnight streak', detail: '16 days in a row' }),
		{ id: 'streak-14', icon: 'local_fire_department', value: 16 },
	);
	assert.deepEqual(
		recapBadgeFromSnapshot({ id: 'night', icon: 'bedtime', label: 'Night owl', detail: 'Out at 22:15' }),
		{ id: 'night', icon: 'bedtime', value: '22:15' },
	);
	assert.deepEqual(recapBadgeFromSnapshot({ id: 'dist-100', icon: 'route', label: 'Century', detail: '100 km on the year' }), {
		id: 'dist-100',
		icon: 'route',
	});
});

test('a snapshot badge this build does not know is dropped', () => {
	assert.equal(recapBadgeFromSnapshot({ id: 'dist-9000', icon: 'public' }), null);
	assert.equal(recapBadgeFromSnapshot(null), null);
	assert.equal(recapBadgeFromSnapshot('dist-100'), null);
});
