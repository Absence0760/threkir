// `npx tsx --test src/lib/training/goal_event_label.test.ts`
//
// Parity pair with mobile's `plan_labels_test.dart` (`planGoalLabel` +
// `planLengthLabel`): same cases, same count. Rendered from the real English
// catalogue so a renamed or reworded key fails here, not on a plan card.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { en } from '../i18n/locales/en';
import { interpolate } from '../i18n/interpolate';
import type { MessageKey } from '../i18n/messages';
import { goalEventLabel, planLengthLabel } from './goal_event_label';

const t = (key: MessageKey, params?: Record<string, string | number>) =>
	interpolate((en as Record<string, string>)[key], params, 'en');

function recordingFormatter() {
	const seen: number[] = [];
	return { seen, fmt: (metres: number) => (seen.push(metres), `<${metres} m>`) };
}

test('named race distances read as their event, whatever distance is stored', () => {
	const { seen, fmt } = recordingFormatter();
	assert.equal(goalEventLabel(t, fmt, 'distance_5k', 5000), '5K');
	assert.equal(goalEventLabel(t, fmt, 'distance_10k', null), '10K');
	assert.equal(goalEventLabel(t, fmt, 'distance_half', 21097.5), 'Half marathon');
	assert.equal(goalEventLabel(t, fmt, 'distance_full', 42195), 'Marathon');
	assert.deepEqual(seen, []);
});

test('a custom plan with a stored distance names that distance', () => {
	const { seen, fmt } = recordingFormatter();
	assert.equal(goalEventLabel(t, fmt, 'custom', 50000), '<50000 m>');
	assert.deepEqual(seen, [50000]);
});

test('the distance goes through the unit formatter the caller hands in', () => {
	const miles = (metres: number) => `${(metres / 1609.344).toFixed(2)} mi`;
	assert.equal(goalEventLabel(t, miles, 'custom', 80467.2), '50.00 mi');
});

test('a custom plan with no usable distance falls back to Custom', () => {
	const { seen, fmt } = recordingFormatter();
	assert.equal(goalEventLabel(t, fmt, 'custom'), 'Custom');
	assert.equal(goalEventLabel(t, fmt, 'custom', null), 'Custom');
	assert.equal(goalEventLabel(t, fmt, 'custom', 0), 'Custom');
	assert.equal(goalEventLabel(t, fmt, 'custom', -5), 'Custom');
	assert.deepEqual(seen, []);
});

test('an unrecognised goal event reads as custom', () => {
	const { fmt } = recordingFormatter();
	assert.equal(goalEventLabel(t, fmt, 'distance_ultra'), 'Custom');
	assert.equal(goalEventLabel(t, fmt, 'distance_ultra', 100000), '<100000 m>');
});

test('plan length: singular for one week, plural otherwise', () => {
	assert.equal(planLengthLabel(t, 1, 3), '1 week · 3 days/week');
	assert.equal(planLengthLabel(t, 12, 4), '12 weeks · 4 days/week');
});
