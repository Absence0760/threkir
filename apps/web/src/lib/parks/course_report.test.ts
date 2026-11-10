import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	COURSE_REPORT_REASONS,
	COURSE_REPORT_REASON_LABELS,
	courseReportEmailOk,
	courseReportErrorKey,
	landManagerDueAt,
} from './course_report.ts';

test('every reason has its own label', () => {
	const labels = COURSE_REPORT_REASONS.map((r) => COURSE_REPORT_REASON_LABELS[r]);
	assert.equal(new Set(labels).size, COURSE_REPORT_REASONS.length);
});

test('the contact email is optional and shape-checked', () => {
	assert.equal(courseReportEmailOk(''), true);
	assert.equal(courseReportEmailOk('   '), true);
	assert.equal(courseReportEmailOk(' ranger@park.example '), true);
	assert.equal(courseReportEmailOk('ranger'), false);
	assert.equal(courseReportEmailOk('a b@park.example'), false);
	assert.equal(courseReportEmailOk(`${'a'.repeat(250)}@b.example`), false);
});

test('each refusal the function sends maps to copy a reporter can act on', () => {
	assert.equal(courseReportErrorKey('rate_limited'), 'parks.report.errorRateLimited');
	assert.equal(courseReportErrorKey('rate_limit_exceeded'), 'parks.report.errorRateLimited');
	assert.equal(courseReportErrorKey('already_reported'), 'parks.report.errorAlreadyReported');
	assert.equal(courseReportErrorKey('course_not_found'), 'parks.report.errorNotFound');
	assert.equal(courseReportErrorKey('invalid_email'), 'parks.report.errorEmail');
	assert.equal(courseReportErrorKey('notes_too_long'), 'parks.report.errorInvalid');
	assert.equal(courseReportErrorKey('report_failed'), null);
	assert.equal(courseReportErrorKey(null), null);
});

test('a weekday request is due at the same time two business days later', () => {
	// Monday 2027-03-01 14:00 UTC → Wednesday 14:00.
	assert.equal(landManagerDueAt('2027-03-01T14:00:00Z').toISOString(), '2027-03-03T14:00:00.000Z');
	// Thursday → Monday, over the weekend.
	assert.equal(landManagerDueAt('2027-03-04T09:30:00Z').toISOString(), '2027-03-08T09:30:00.000Z');
	// Friday afternoon → Tuesday afternoon.
	assert.equal(landManagerDueAt('2027-03-05T16:00:00Z').toISOString(), '2027-03-09T16:00:00.000Z');
});

test('a weekend request is due at the end of Tuesday', () => {
	assert.equal(landManagerDueAt('2027-03-06T10:00:00Z').toISOString(), '2027-03-09T23:59:59.999Z');
	assert.equal(landManagerDueAt('2027-03-07T23:00:00Z').toISOString(), '2027-03-09T23:59:59.999Z');
});
