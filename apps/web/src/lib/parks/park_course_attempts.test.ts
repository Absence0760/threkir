import { test } from 'node:test';
import assert from 'node:assert/strict';
import { en } from '../i18n/locales/en.ts';
import { messages as ja } from '../i18n/locales/ja.ts';
import { interpolate } from '../i18n/interpolate.ts';
import type { MessageKey } from '../i18n/messages.ts';
import type { ParkCourseAttempt } from '../types.ts';
import { attemptCard, attemptFraction, attemptHref } from './park_course_attempts.ts';

const t = (key: MessageKey, params?: Record<string, string | number>) => interpolate(en[key], params, 'en');

function attempt(over: Partial<ParkCourseAttempt> = {}): ParkCourseAttempt {
	return {
		parkCourseId: 'c1',
		courseName: 'Lake Loop',
		parkName: 'Pocahontas State Park',
		region: 'US-VA',
		parkSlug: 'pocahontas',
		courseSlug: 'lake-loop',
		outcome: 'stopped_short',
		progressM: 3200,
		courseM: 5000,
		missedCheckpoint: null,
		checkpointCount: 4,
		...over,
	};
}

test('the card links to the course page under its lower-case region', () => {
	assert.equal(attemptHref(attempt()), '/parks/us-va/pocahontas/lake-loop');
	assert.equal(attemptCard(attempt(), 'km', 'en', t).href, '/parks/us-va/pocahontas/lake-loop');
});

test('stopped short names how far the runner got and to run the whole course', () => {
	const c = attemptCard(attempt(), 'km', 'en', t);
	assert.equal(c.reason, 'Lake Loop: no time. You ran 3.20 km of 5.00 km. Run the whole course to get a time.');
	assert.equal(c.progress, '3.20 km of 5.00 km');
	assert.equal(c.fraction, 0.64);
	assert.equal(c.barLabel, 'How far you got on Lake Loop');
});

test('a skipped checkpoint names which one of how many', () => {
	const c = attemptCard(
		attempt({ outcome: 'skipped_checkpoint', missedCheckpoint: 2, progressM: 1800 }),
		'km',
		'en',
		t,
	);
	assert.equal(
		c.reason,
		'Lake Loop: no time. You missed checkpoint 2 of 4. Stay on the course line to pass every one.',
	);
	assert.equal(c.progress, '1.80 km of 5.00 km');
});

test('off course and the wrong way round each say what to do instead', () => {
	assert.equal(
		attemptCard(attempt({ outcome: 'off_course', progressM: 5000 }), 'km', 'en', t).reason,
		'Lake Loop: no time. You ran too far off the course. Stay on the course line.',
	);
	assert.equal(
		attemptCard(attempt({ outcome: 'wrong_direction', progressM: 0 }), 'km', 'en', t).reason,
		'Lake Loop: no time. You ran it the wrong way round. Follow the arrows on the course map.',
	);
});

test('a gap at the finish says the recording could not be timed and to keep recording', () => {
	assert.equal(
		attemptCard(attempt({ outcome: 'gps_gap', progressM: 5000 }), 'km', 'en', t).reason,
		"Lake Loop: no time. Your recording has a gap where you reached the finish, so we couldn't time it. Keep recording until you're past the line.",
	);
});

test('the distances follow the runner unit, yards below a mile', () => {
	const c = attemptCard(attempt({ progressM: 800, courseM: 8047 }), 'mi', 'en', t);
	assert.equal(c.progress, '875 yd of 5.00 mi');
	assert.match(c.reason, /You ran 875 yd of 5\.00 mi\./);
});

test('the bar stays inside its track for out-of-range numbers', () => {
	assert.equal(attemptFraction(attempt({ progressM: 0 })), 0);
	assert.equal(attemptFraction(attempt({ progressM: 6000 })), 1);
	assert.equal(attemptFraction(attempt({ progressM: -5 })), 0);
	assert.equal(attemptFraction(attempt({ courseM: 0 })), 0);
	assert.equal(attemptCard(attempt({ progressM: 6000 }), 'km', 'en', t).progress, '5.00 km of 5.00 km');
});

test('every outcome has its own sentence in a non-English catalogue too', () => {
	const tj = (key: MessageKey, params?: Record<string, string | number>) =>
		interpolate(ja[key], params, 'ja');
	const outcomes = ['stopped_short', 'skipped_checkpoint', 'off_course', 'gps_gap', 'wrong_direction'] as const;
	const reasons = outcomes.map(
		(outcome) => attemptCard(attempt({ outcome, missedCheckpoint: outcome === 'skipped_checkpoint' ? 3 : null }), 'km', 'ja', tj).reason,
	);
	assert.equal(new Set(reasons).size, outcomes.length);
	for (const r of reasons) {
		assert.ok(r.startsWith('Lake Loop'), r);
		assert.doesNotMatch(r, /\{\w+\}/, r);
	}
});
