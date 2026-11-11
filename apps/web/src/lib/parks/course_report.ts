/**
 * "Report a problem with this course" (issue #1346, decisions § 2449): the
 * reasons a park course report takes, the limits the form shows, the copy for
 * each refusal of the `park-course-report` Edge Function, and the
 * land-manager and rights-holder deadlines the admin queue shows.
 *
 * The reasons are a rail of `reports.reason` in
 * `apps/web/scripts/check_constraint_unions.mjs`; the mobile list is
 * `kCourseReportReasons` in `apps/mobile_android/lib/park_course_report.dart`.
 * The limits mirror `submit_park_course_report`, which is the authority.
 */

import type { MessageKey } from '../i18n/messages.ts';

export const COURSE_REPORT_REASONS = [
	'course_hazard',
	'course_closure',
	'course_off_trail',
	'land_manager_request',
	'rights_holder_request',
	'other',
] as const;
export type CourseReportReason = (typeof COURSE_REPORT_REASONS)[number];

export const COURSE_REPORT_REASON_LABELS: Record<CourseReportReason, MessageKey> = {
	course_hazard: 'parks.report.reasonHazard',
	course_closure: 'parks.report.reasonClosure',
	course_off_trail: 'parks.report.reasonOffTrail',
	land_manager_request: 'parks.report.reasonLandManager',
	rights_holder_request: 'parks.report.reasonRightsHolder',
	other: 'parks.report.reasonOther',
};

export const COURSE_REPORT_NOTES_MAX = 1000;
export const COURSE_REPORT_EMAIL_MAX = 254;

const EMAIL_SHAPE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** A rights holder's request is answered by hand, so it needs an address
 *  (decisions § 2469); every other reason leaves the email optional. */
export function courseReportEmailRequired(reason: CourseReportReason): boolean {
	return reason === 'rights_holder_request';
}

/** True for a plausible address, or for an empty field when the reason leaves
 *  the email optional. */
export function courseReportEmailOk(raw: string, reason?: CourseReportReason): boolean {
	const e = raw.trim();
	if (e.length === 0) return !(reason && courseReportEmailRequired(reason));
	return e.length <= COURSE_REPORT_EMAIL_MAX && EMAIL_SHAPE.test(e);
}

/**
 * The admin's reply link to a reporter's address. The whole address is
 * percent-encoded, which RFC 6068 allows, so a `?` or `&` a reporter typed
 * stays part of the address and cannot add a BCC or a body to the draft.
 */
export function courseReportMailto(email: string): string {
	return `mailto:${encodeURIComponent(email)}`;
}

/** The copy for each code the Edge Function refuses with; null for the rest,
 *  which take the generic failure line. */
export function courseReportErrorKey(code: string | null): MessageKey | null {
	switch (code) {
		case 'rate_limited':
		case 'rate_limit_exceeded':
		case 'rate_limit_unavailable':
			return 'parks.report.errorRateLimited';
		case 'already_reported':
			return 'parks.report.errorAlreadyReported';
		case 'course_not_found':
			return 'parks.report.errorNotFound';
		case 'invalid_email':
			return 'parks.report.errorEmail';
		case 'email_required':
			return 'parks.report.errorEmailRequired';
		case 'notes_required':
		case 'notes_too_long':
		case 'invalid_report':
		case 'invalid_reason':
		case 'invalid_course':
		case 'invalid_body':
			return 'parks.report.errorInvalid';
		default:
			return null;
	}
}

/** The two business days the permit decision on #1097 gives a land manager's
 *  request, and the Terms give a rights holder's answer (decisions § 2469). */
export const LAND_MANAGER_BUSINESS_DAYS = 2;
export const RIGHTS_HOLDER_BUSINESS_DAYS = 2;

/**
 * When a land manager's request received at `receivedIso` must be honoured:
 * the same time of day two business days later, counting Monday to Friday in
 * UTC, so a Friday afternoon request is due Tuesday afternoon. A request
 * received on a weekend is due at the end of the second business day (Tuesday).
 * Public holidays are not counted out, so the deadline errs early, the safe
 * side for a promise.
 */
export function landManagerDueAt(receivedIso: string): Date {
	return businessDaysAfter(receivedIso, LAND_MANAGER_BUSINESS_DAYS);
}

/** When a rights holder's request received at `receivedIso` must be answered,
 *  counted as `landManagerDueAt` counts. */
export function rightsHolderDueAt(receivedIso: string): Date {
	return businessDaysAfter(receivedIso, RIGHTS_HOLDER_BUSINESS_DAYS);
}

function businessDaysAfter(receivedIso: string, days: number): Date {
	const due = new Date(receivedIso);
	const receivedDay = due.getUTCDay();
	let left = days;
	while (left > 0) {
		due.setUTCDate(due.getUTCDate() + 1);
		const day = due.getUTCDay();
		if (day !== 0 && day !== 6) left -= 1;
	}
	if (receivedDay === 0 || receivedDay === 6) due.setUTCHours(23, 59, 59, 999);
	return due;
}
