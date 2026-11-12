/// Pure input validation and error mapping for park-course-report.
///
/// The database re-checks every rule here (submit_park_course_report, migration
/// 20271213000003); these run first so a malformed request spends no rate-limit
/// slot and no database round trip.

import { isValidUuid } from '../_shared/input_validation.ts';

/// The reasons a park course takes. The five course reasons belong to a park
/// course only; 'other' is shared with the general reports.
export const COURSE_REPORT_REASONS = [
  'course_hazard',
  'course_closure',
  'course_off_trail',
  'land_manager_request',
  'rights_holder_request',
  'other',
] as const;

export type CourseReportReason = (typeof COURSE_REPORT_REASONS)[number];

/// The requests that carry a two-business-day promise (decisions § 2469). The
/// database caps their signed-out filings in a bucket of their own, and so
/// does the per-address limit, so ordinary traffic cannot lock them out.
export const DEADLINE_REASONS: readonly CourseReportReason[] = ['land_manager_request', 'rights_holder_request'];

export function isDeadlineReason(reason: CourseReportReason): boolean {
  return DEADLINE_REASONS.includes(reason);
}

/// The per-address rate-limit bucket a signed-out report spends. `ip` is the
/// address the trusted header established, or null; the bucket's key is that
/// address, or the one `unknown` key every caller without one shares. Every
/// signed-out report spends a bucket. A deadline request spends one apart
/// from the ordinary one, so ordinary traffic cannot lock it out, and a
/// deadline request with no address spends a third, shared only with other
/// such requests: it caps the admin notices header-less callers can raise at
/// one address's worth an hour, where submit_park_course_report's own
/// deadline cap would admit 120.
export function addressBucket(reason: CourseReportReason, ip: string | null): string {
  if (!isDeadlineReason(reason)) return 'park-course-report:anon';
  return ip === null ? 'park-course-report:anon:deadline:unknown' : 'park-course-report:anon:deadline';
}

export const MAX_NOTES_LEN = 1000;
export const MAX_EMAIL_LEN = 254;
/// Room for a 1000-character note in any script plus the other fields.
export const MAX_BODY_BYTES = 8 * 1024;

const EMAIL_SHAPE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export interface CourseReport {
  courseId: string;
  reason: CourseReportReason;
  notes: string;
  contactEmail: string | null;
}

export type ParsedReport =
  | { ok: true; trap: false; report: CourseReport }
  /// The honeypot field was filled: a form a person sees leaves it empty.
  | { ok: true; trap: true }
  | { ok: false; error: string };

function isReason(v: unknown): v is CourseReportReason {
  return typeof v === 'string' && (COURSE_REPORT_REASONS as readonly string[]).includes(v);
}

export function parseReportBody(body: unknown): ParsedReport {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return { ok: false, error: 'invalid_body' };
  }
  const b = body as Record<string, unknown>;

  if (typeof b.website === 'string' && b.website.trim().length > 0) {
    return { ok: true, trap: true };
  }

  if (!isValidUuid(b.course_id)) return { ok: false, error: 'invalid_course' };
  if (!isReason(b.reason)) return { ok: false, error: 'invalid_reason' };

  if (typeof b.notes !== 'string') return { ok: false, error: 'notes_required' };
  const notes = b.notes.trim();
  if (notes.length === 0) return { ok: false, error: 'notes_required' };
  // Code points, as Postgres char_length counts them.
  if ([...notes].length > MAX_NOTES_LEN) return { ok: false, error: 'notes_too_long' };

  let contactEmail: string | null = null;
  if (b.contact_email !== undefined && b.contact_email !== null) {
    if (typeof b.contact_email !== 'string') return { ok: false, error: 'invalid_email' };
    const e = b.contact_email.trim();
    if (e.length > 0) {
      if (e.length > MAX_EMAIL_LEN || !EMAIL_SHAPE.test(e)) return { ok: false, error: 'invalid_email' };
      contactEmail = e;
    }
  }
  // A rights holder's request is answered by hand (decisions § 2469).
  if (b.reason === 'rights_holder_request' && contactEmail === null) {
    return { ok: false, error: 'email_required' };
  }

  return {
    ok: true,
    trap: false,
    report: { courseId: b.course_id as string, reason: b.reason, notes, contactEmail },
  };
}

/// The database's refusals, as the codes the clients map to copy. A message is
/// never forwarded: it names the function and the rule, not the person.
export function rpcErrorToResponse(code: string | undefined): { status: number; error: string } {
  switch (code) {
    case 'PT429':
      return { status: 429, error: 'rate_limited' };
    case '23505':
      return { status: 409, error: 'already_reported' };
    case '02000':
      return { status: 404, error: 'course_not_found' };
    case '22023':
      return { status: 400, error: 'invalid_report' };
    default:
      return { status: 500, error: 'report_failed' };
  }
}
