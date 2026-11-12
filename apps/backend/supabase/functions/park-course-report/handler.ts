/// Request handler for park-course-report, factored out of index.ts behind
/// injected deps (who the caller is, the two rate limits, the filing RPC) so
/// `handler.test.ts` drives every path with no stack.
///
/// Order: the method, then the body under its byte cap, then the shape, all of
/// which cost nothing, so a malformed request spends no rate-limit slot. A
/// filled honeypot answers exactly as a filed report does and files nothing, so
/// a bot learns nothing from the response. Then the caller: a verified JWT
/// files as that user against a per-user bucket; anyone else files signed out
/// against a per-address bucket (check_rate_limit through ipBucketKey, which
/// keeps a hash of the address, never the address); a land-manager or
/// rights-holder request has a per-address bucket of its own (lib.ts
/// addressBucket). Every bucket fails closed. The database then applies its
/// own caps, which no rotation of addresses gets around
/// (submit_park_course_report: 25 pending a course, and signed-out reports an
/// hour, 60 ordinary and 120 deadline requests, each counted apart).
///
/// Nothing the reporter wrote is logged: an error is logged by its code alone.

import { readJsonWithLimit } from '../_shared/body_limit.ts';
import {
  type CourseReport,
  type CourseReportReason,
  MAX_BODY_BYTES,
  parseReportBody,
  rpcErrorToResponse,
} from './lib.ts';

export interface ParkCourseReportDeps {
  /// The signed-in user's id when the request carries a valid user JWT, else
  /// null (no header, the publishable key, an expired or forged token).
  resolveUser: (req: Request) => Promise<string | null>;
  /// Null to proceed, or the 429 / 503 to return.
  limitUser: (userId: string) => Promise<Response | null>;
  /// The signed-out caller's per-address limit for this reason (lib.ts
  /// addressBucket decides which bucket, if any).
  limitAddress: (req: Request, reason: CourseReportReason) => Promise<Response | null>;
  submit: (report: CourseReport, reporterId: string | null) => Promise<{ errorCode: string | null }>;
}

const FILED = { ok: true } as const;

export function makeParkCourseReportHandler(deps: ParkCourseReportDeps): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method !== 'POST') {
      return Response.json({ error: 'method_not_allowed' }, { status: 405, headers: { Allow: 'POST' } });
    }

    const guarded = await readJsonWithLimit<unknown>(req, MAX_BODY_BYTES);
    if ('tooLarge' in guarded) return guarded.tooLarge;

    const parsed = parseReportBody(guarded.body);
    if (!parsed.ok) return Response.json({ error: parsed.error }, { status: 400 });
    if (parsed.trap) return Response.json(FILED, { status: 201 });

    const userId = await deps.resolveUser(req);
    const denied = userId
      ? await deps.limitUser(userId)
      : await deps.limitAddress(req, parsed.report.reason);
    if (denied) return denied;

    let errorCode: string | null;
    try {
      ({ errorCode } = await deps.submit(parsed.report, userId));
    } catch {
      errorCode = 'unknown';
    }
    if (errorCode !== null) {
      const mapped = rpcErrorToResponse(errorCode);
      if (mapped.status >= 500) console.error('park-course-report: filing failed (code):', errorCode);
      return Response.json({ error: mapped.error }, { status: mapped.status });
    }
    return Response.json(FILED, { status: 201 });
  };
}
