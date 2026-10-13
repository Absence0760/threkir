// Pins the event_cancel sentence choice shared by NotificationBell and
// NotificationsList: a paid registrant's row (`refunded`, migration
// 20270725000002) reads the refund sentence, everyone else the plain one, and
// every key it can return exists — with its {title} slot where it takes one —
// in every shipped locale.
//
// Invocation:
//   npx tsx --test src/lib/social/event_cancel_copy.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { EVENT_CANCEL_KEYS, eventCancelMessage } from './event_cancel_copy';
import { SUPPORTED_LOCALES } from '../i18n/locale';
import { CATALOGUE_LOADERS } from '../i18n/catalogues';
import { interpolate } from '../i18n/interpolate';

test('a refunded row reads the refund sentence on both surfaces, titled or not', () => {
	assert.deepEqual(eventCancelMessage('notificationBell', { refunded: true }, 'Barre'), {
		key: 'notificationBell.eventCancelRefundedTitled',
		params: { title: 'Barre' },
	});
	assert.deepEqual(eventCancelMessage('notificationBell', { refunded: true }, null), {
		key: 'notificationBell.eventCancelRefunded',
	});
	assert.deepEqual(eventCancelMessage('notificationsList', { refunded: true }, 'Barre'), {
		key: 'notificationsList.verbEventCancelRefundedTitled',
		params: { title: 'Barre' },
	});
	assert.deepEqual(eventCancelMessage('notificationsList', { refunded: true }, null), {
		key: 'notificationsList.verbEventCancelRefunded',
	});
});

test('a free attendee, or a row from before the column, reads the plain sentence', () => {
	for (const row of [{ refunded: false }, {}, { refunded: null }]) {
		assert.deepEqual(eventCancelMessage('notificationBell', row, 'Barre'), {
			key: 'notificationBell.eventCancelTitled',
			params: { title: 'Barre' },
		});
		assert.deepEqual(eventCancelMessage('notificationsList', row, null), {
			key: 'notificationsList.verbEventCancel',
		});
	}
});

test('every event_cancel key exists in every locale, the refund ones differ from the plain ones', async () => {
	assert.equal(EVENT_CANCEL_KEYS.length, 8);
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const key of EVENT_CANCEL_KEYS) {
			const raw = dict[key];
			assert.ok(raw && raw.trim() !== '', `[${loc}] ${key} is missing`);
			if (key.endsWith('Titled')) {
				assert.ok(raw.includes('{title}'), `[${loc}] ${key} has no {title} slot`);
				const rendered = interpolate(raw, { title: 'Barre' });
				assert.ok(rendered.includes('Barre') && !rendered.includes('{'), `[${loc}] ${key} renders ${rendered}`);
			}
		}
		for (const surface of ['notificationBell', 'notificationsList'] as const) {
			for (const title of ['Barre', null]) {
				const plain = eventCancelMessage(surface, { refunded: false }, title);
				const paid = eventCancelMessage(surface, { refunded: true }, title);
				assert.notEqual(
					dict[paid.key],
					dict[plain.key],
					`[${loc}] ${surface} reads the same for a paid registrant as for a free one`,
				);
			}
		}
	}
});
