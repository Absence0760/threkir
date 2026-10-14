// Pins the event_waitlist_slot renderer shared by NotificationBell and
// NotificationsList, and the viewer-state reading the event page draws the
// claim from (migration 20270726000002, decisions § 1840): every key exists
// with its slots in every shipped locale, the sentence is not the generic or
// the cancel one, and a lapsed offer is never presented as a held seat.
//
// Invocation:
//   npx tsx --test src/lib/social/event_waitlist_offer.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { WAITLIST_SLOT_KEYS, waitlistOfferState, waitlistSlotMessage } from './event_waitlist_offer';
import { SUPPORTED_LOCALES } from '../i18n/locale';
import { CATALOGUE_LOADERS } from '../i18n/catalogues';
import { interpolate } from '../i18n/interpolate';

test('the titled shape carries the event title on both surfaces', () => {
	assert.deepEqual(waitlistSlotMessage('notificationBell', 'Reformer'), {
		key: 'notificationBell.waitlistSlotTitled',
		params: { title: 'Reformer' },
	});
	assert.deepEqual(waitlistSlotMessage('notificationsList', 'Reformer'), {
		key: 'notificationsList.verbWaitlistSlotTitled',
		params: { title: 'Reformer' },
	});
});

test('an untitled row reads the untitled sentence', () => {
	assert.deepEqual(waitlistSlotMessage('notificationBell', null), { key: 'notificationBell.waitlistSlot' });
	assert.deepEqual(waitlistSlotMessage('notificationsList', null), {
		key: 'notificationsList.verbWaitlistSlot',
	});
});

test('every waitlist-slot key exists in every locale and says something of its own', async () => {
	assert.equal(WAITLIST_SLOT_KEYS.length, 4);
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const key of WAITLIST_SLOT_KEYS) {
			const raw = dict[key];
			assert.ok(raw && raw.trim() !== '', `[${loc}] ${key} is missing`);
			if (key.endsWith('Titled')) {
				assert.ok(raw.includes('{title}'), `[${loc}] ${key} has no {title} slot`);
				const rendered = interpolate(raw, { title: 'Reformer' });
				assert.ok(rendered.includes('Reformer') && !rendered.includes('{'), `[${loc}] ${key} renders ${rendered}`);
			}
		}
		assert.notEqual(dict['notificationsList.verbWaitlistSlot'], dict['notificationsList.verbGeneric'], `[${loc}]`);
		assert.notEqual(dict['notificationBell.waitlistSlot'], dict['notificationBell.eventCancel'], `[${loc}]`);
		for (const key of ['clubEvent.waitlistOfferHeld', 'clubEvent.claimForPrice']) {
			const slot = key === 'clubEvent.waitlistOfferHeld' ? 'time' : 'price';
			assert.ok(dict[key]?.includes(`{${slot}}`), `[${loc}] ${key} has no {${slot}} slot`);
		}
		for (const key of ['clubEvent.joinWaitlist', 'clubEvent.waitlistJoined', 'clubEvent.leaveWaitlist']) {
			assert.ok(dict[key] && dict[key].trim() !== '', `[${loc}] ${key} is missing`);
		}
	}
});

const NOW = Date.parse('2026-10-13T12:00:00Z');

test('no row, or a row that is not waitlisted, is not on the waitlist', () => {
	assert.deepEqual(waitlistOfferState(null, NOW), { kind: 'none' });
	assert.deepEqual(waitlistOfferState({ status: 'going', offer_expires_at: null }, NOW), { kind: 'none' });
	// A stale deadline on a row that has moved on is not an offer.
	assert.deepEqual(
		waitlistOfferState({ status: 'declined', offer_expires_at: '2026-10-13T20:00:00Z' }, NOW),
		{ kind: 'none' },
	);
});

test('a queued waitlister with no offer is waiting', () => {
	assert.deepEqual(waitlistOfferState({ status: 'waitlisted', offer_expires_at: null }, NOW), {
		kind: 'waiting',
	});
});

test('a future deadline is a held seat, carrying the deadline', () => {
	assert.deepEqual(
		waitlistOfferState({ status: 'waitlisted', offer_expires_at: '2026-10-13T20:00:00Z' }, NOW),
		{ kind: 'offered', deadline: '2026-10-13T20:00:00Z' },
	);
});

test('a passed or unreadable deadline is lapsed, never a held seat', () => {
	for (const at of ['2026-10-13T12:00:00Z', '2026-10-13T11:00:00Z', 'garbage']) {
		assert.deepEqual(waitlistOfferState({ status: 'waitlisted', offer_expires_at: at }, NOW), {
			kind: 'lapsed',
		});
	}
});
