// The trophy grid's words come from the reader's catalogue, by badge id, for
// a recap built here and for one read back out of a published snapshot.
// Invocation: npx tsx --test src/lib/share/recap_badge_text.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { interpolate } from '../i18n/interpolate';
import { en } from '../i18n/locales/en';
import { messages as fr } from '../i18n/locales/fr';
import { messages as de } from '../i18n/locales/de';
import { messages as es } from '../i18n/locales/es';
import { messages as ja } from '../i18n/locales/ja';
import { messages as ptBR } from '../i18n/locales/pt-BR';
import { messages as ptPT } from '../i18n/locales/pt-PT';
import type { MessageKey } from '../i18n/messages';
import { RECAP_BADGE_IDS } from '../runs/recap';
import { recapBadgeFromSnapshot, recapBadgeText } from './recap_card_text';

const tEn = (key: MessageKey, params?: Record<string, string | number>) => interpolate(en[key], params, 'en');
const tFr = (key: MessageKey, params?: Record<string, string | number>) => interpolate(fr[key], params, 'fr');

test('every badge id has a label and a detail in English', () => {
	for (const id of RECAP_BADGE_IDS) {
		const { label, detail } = recapBadgeText({ id, icon: 'x', value: id === 'early' || id === 'night' ? '05:10' : 4 }, tEn, 'km');
		assert.ok(label.length > 0, id);
		assert.ok(detail.length > 0, id);
		assert.doesNotMatch(detail, /[{}]/, `${id} left a placeholder: ${detail}`);
		assert.doesNotMatch(label, /[{}]/, `${id} left a placeholder: ${label}`);
	}
});

test('a counted detail is a plural in the reader\'s language', () => {
	assert.equal(recapBadgeText({ id: 'pr-1', icon: 'trophy', value: 1 }, tEn, 'km').detail, '1 personal record');
	assert.equal(recapBadgeText({ id: 'pr-1', icon: 'trophy', value: 2 }, tEn, 'km').detail, '2 personal records');
	assert.equal(recapBadgeText({ id: 'streak-7', icon: 'x', value: 9 }, tFr, 'km').label, 'Série d\'une semaine');
	assert.equal(recapBadgeText({ id: 'night', icon: 'x', value: '22:15' }, tEn, 'km').detail, 'Out at 22:15');
});

test('a badge that names a distance names it in the reader\'s unit and number format', () => {
	assert.equal(recapBadgeText({ id: 'long-marathon', icon: 'x' }, tEn, 'km').detail, '42.2 km in one run');
	assert.equal(recapBadgeText({ id: 'long-marathon', icon: 'x' }, tEn, 'mi').detail, '26.2 mi in one run');
	assert.equal(recapBadgeText({ id: 'long-half', icon: 'x' }, tEn, 'mi').detail, '13.1 mi in one run');
	assert.equal(recapBadgeText({ id: 'long-ultra', icon: 'x' }, tEn, 'km').detail, '50 km+ in one run');
	assert.equal(recapBadgeText({ id: 'long-ultra', icon: 'x' }, tEn, 'mi').detail, '31.1 mi+ in one run');
	assert.equal(recapBadgeText({ id: 'dist-2000', icon: 'x' }, tEn, 'km', 'en').label, '2,000 km');
	assert.equal(recapBadgeText({ id: 'dist-2000', icon: 'x' }, tEn, 'mi', 'en').label, '1,243 mi');
	assert.equal(recapBadgeText({ id: 'dist-100', icon: 'x' }, tEn, 'mi', 'en').detail, '62 mi on the year');
	assert.equal(recapBadgeText({ id: 'elev-5000', icon: 'x' }, tEn, 'km', 'en').label, '5,000 m climbed');
	assert.equal(recapBadgeText({ id: 'elev-5000', icon: 'x' }, tEn, 'mi', 'en').label, '16,404 ft climbed');
	assert.equal(recapBadgeText({ id: 'long-marathon', icon: 'x' }, tFr, 'km', 'fr').detail, '42,2 km en une course');
	assert.equal(recapBadgeText({ id: 'dist-1000', icon: 'x' }, tFr, 'km', 'fr').label, 'Club des 1\u202f000 km');
});

test('no recap badge string hard-codes a distance unit in any locale', () => {
	const locales = { en, fr, de, es, ja, ptBR, ptPT } as Record<string, Record<string, string>>;
	for (const [loc, cat] of Object.entries(locales)) {
		for (const [key, value] of Object.entries(cat)) {
			if (!key.startsWith('recap.badge')) continue;
			assert.doesNotMatch(value, /\d\s?(km|mi)\b/, `${loc} ${key} hard-codes a distance: ${value}`);
		}
	}
});

test('a counted badge without its value shows the label alone', () => {
	assert.deepEqual(recapBadgeText({ id: 'months-6', icon: 'x' }, tEn, 'km'), { label: 'Half the year', detail: '' });
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
