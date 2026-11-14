import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parkMonthNoticeMessage, parkNoticeMonth, PARK_MONTH_NOTICE_KEYS } from './park_month_notice_copy';
import { en } from '../i18n/locales/en';

test('parkNoticeMonth: reads the park-local 1st the row carries', () => {
	assert.deepEqual(parkNoticeMonth('2026-10-01'), { season: 2026, month: 10 });
	assert.deepEqual(parkNoticeMonth('2026-01-01T00:00:00'), { season: 2026, month: 1 });
	for (const raw of [null, undefined, '', '2026-13-01', '2026-00-01', '2026-10', 'October']) {
		assert.equal(parkNoticeMonth(raw), null, String(raw));
	}
});

test('parkMonthNoticeMessage: names the course, the month and the best time', () => {
	const msg = parkMonthNoticeMessage(
		'notificationBell',
		{ park_course_month: '2026-10-01', park_course_time_s: 1471 },
		'Beaver Lake Trail',
		'en',
	);
	assert.equal(msg.key, 'notificationBell.parkCourseMonthClosedNamed');
	assert.deepEqual(msg.params, { course: 'Beaver Lake Trail', month: 'October 2026', time: '24:31' });
});

test('parkMonthNoticeMessage: a missing course, month or time reads as the plain sentence', () => {
	const row = { park_course_month: '2026-10-01', park_course_time_s: 1471 };
	assert.deepEqual(parkMonthNoticeMessage('notificationsList', row, null, 'en'), {
		key: 'notificationsList.verbParkCourseMonthClosed',
	});
	assert.equal(parkMonthNoticeMessage('notificationsList', { ...row, park_course_month: null }, 'X', 'en').key, 'notificationsList.verbParkCourseMonthClosed');
	assert.equal(parkMonthNoticeMessage('notificationsList', { ...row, park_course_time_s: null }, 'X', 'en').key, 'notificationsList.verbParkCourseMonthClosed');
	assert.equal(parkMonthNoticeMessage('notificationsList', { ...row, park_course_time_s: 0 }, 'X', 'en').key, 'notificationsList.verbParkCourseMonthClosed');
});

test('parkMonthNoticeMessage: every key it returns is in the catalogue, and none names a rank', () => {
	for (const key of PARK_MONTH_NOTICE_KEYS) {
		const text = (en as Record<string, string>)[key];
		assert.ok(text, key);
		assert.doesNotMatch(text, /\{rank\}|#\{/, key);
	}
});
