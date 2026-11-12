import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { en } from '#lib/i18n/locales/en.ts';
import {
	DISPUTE_DEADLINE_DEFAULT_DAYS,
	DISPUTE_DEADLINE_MAX_DAYS,
	DISPUTE_DEADLINE_MIN_DAYS,
	DISPUTE_NOTES_MAX,
	deadlineDaysOrNull,
	deadlinePassed,
	disputeClubsFor,
	disputeKindLabelKey,
	disputeStatusKey,
	disputeTargetHref,
} from './organiser_dispute.ts';

const MIGRATION = readFileSync(
	fileURLToPath(
		new URL(
			'../../../../backend/supabase/migrations/20271202000003_organiser_disputes.sql',
			import.meta.url,
		),
	),
	'utf8',
);

const V = { id: 'v', name: 'Verified Org', slug: 'verified-org' };
const W = { id: 'w', name: 'Second Org', slug: null };

test('a club cannot dispute its own content', () => {
	assert.deepEqual(disputeClubsFor([V, W], 'v'), [W]);
	assert.deepEqual(disputeClubsFor([V, W], null), [V, W]);
	assert.deepEqual(disputeClubsFor([V], 'v'), []);
});

test('the deadline bounds match resolve_organiser_dispute', () => {
	assert.match(MIGRATION, new RegExp(`coalesce\\(p_deadline_days, ${DISPUTE_DEADLINE_DEFAULT_DAYS}\\)`));
	assert.match(
		MIGRATION,
		new RegExp(`p_deadline_days < ${DISPUTE_DEADLINE_MIN_DAYS} or p_deadline_days > ${DISPUTE_DEADLINE_MAX_DAYS}`),
	);
	assert.match(MIGRATION, new RegExp(`char_length\\(v_notes\\) > ${DISPUTE_NOTES_MAX}`));
});

test('deadlineDaysOrNull accepts only whole days in range', () => {
	assert.equal(deadlineDaysOrNull('14'), 14);
	assert.equal(deadlineDaysOrNull(1), 1);
	assert.equal(deadlineDaysOrNull(60), 60);
	assert.equal(deadlineDaysOrNull('0'), null);
	assert.equal(deadlineDaysOrNull('61'), null);
	assert.equal(deadlineDaysOrNull('2.5'), null);
	assert.equal(deadlineDaysOrNull(''), null);
	assert.equal(deadlineDaysOrNull(null), null);
});

test('deadlinePassed', () => {
	const now = new Date('2036-01-10T12:00:00Z');
	assert.equal(deadlinePassed('2036-01-10T11:59:59Z', now), true);
	assert.equal(deadlinePassed('2036-01-11T00:00:00Z', now), false);
	assert.equal(deadlinePassed(null, now), false);
	assert.equal(deadlinePassed('not a date', now), false);
});

test('every disputable kind links to the page that shows it', () => {
	assert.equal(disputeTargetHref('club', 'x'), '/clubs/x');
	assert.equal(disputeTargetHref('route', 'x'), '/routes/x');
	assert.equal(disputeTargetHref('training_plan', 'x'), '/plans/library/x');
	assert.equal(disputeTargetHref('gym_routine', 'x'), '/gym/routines/library/x');
	assert.equal(disputeTargetHref('challenge', 'x'), '/challenges/x');
	assert.equal(disputeTargetHref('race_listing', 'x'), '/races/x');
});

test('every label and status key exists in the English catalogue', () => {
	const catalogue = en as Record<string, string>;
	for (const kind of ['club', 'route', 'training_plan', 'gym_routine', 'challenge', 'race_listing'] as const) {
		assert.ok(catalogue[disputeKindLabelKey(kind)], `missing label for ${kind}`);
	}
	for (const action of ['filed', 'takedown', 'rename_notice', 'dismiss', 'unhide'] as const) {
		for (const side of ['owner', 'organiser'] as const) {
			assert.ok(catalogue[disputeStatusKey(action, side)], `missing status for ${action}/${side}`);
		}
	}
});

test('the owner and the organiser read a hide and a notice differently', () => {
	assert.notEqual(disputeStatusKey('takedown', 'owner'), disputeStatusKey('takedown', 'organiser'));
	assert.notEqual(disputeStatusKey('rename_notice', 'owner'), disputeStatusKey('rename_notice', 'organiser'));
});
