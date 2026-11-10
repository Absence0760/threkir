/// Report a problem with a park course (issue #1346, decisions § 2447):
///   POST /functions/v1/park-course-report
///   { course_id, reason, notes, contact_email?, website? }
///
/// Park staff need no account, so `verify_jwt = false` in config.toml: a
/// signed-out browser's supabase-js sends the publishable key as its bearer,
/// which the platform gate would 401. The handler is the trust boundary. A
/// valid user JWT files as that user; anything else files signed out. The
/// filing RPC is executable by the service role only, so this function is the
/// one way a report reaches the table. See handler.ts for the order of checks.

import { createClient } from 'npm:@supabase/supabase-js@2.119.0';
import type { Database, DbClient } from '../_shared/database.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { withCors } from '../_shared/cors.ts';
import { makeParkCourseReportHandler } from './handler.ts';

/// Per signed-in user, and per client address for a signed-out caller, each
/// an hour. A land manager reporting several courses of one park in one
/// sitting stays well inside either.
export const PARK_COURSE_REPORT_USER_PER_HOUR = 10;
export const PARK_COURSE_REPORT_ADDRESS_PER_HOUR = 10;

let admin: DbClient | null = null;

function adminClient(): DbClient {
  if (!admin) {
    admin = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());
  }
  return admin;
}

const handler = makeParkCourseReportHandler({
  resolveUser: async (req) => {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return null;
    const caller = createClient<Database>(Deno.env.get('SUPABASE_URL')!, publishableKey(), {
      global: { headers: { Authorization: authHeader } },
    });
    try {
      const { data: { user } } = await caller.auth.getUser();
      return user?.id ?? null;
    } catch {
      return null;
    }
  },
  limitUser: (userId) =>
    checkRateLimit(adminClient(), userId, 'park-course-report', PARK_COURSE_REPORT_USER_PER_HOUR, 3600, {
      failClosed: true,
    }),
  limitAddress: async (req) =>
    checkRateLimit(
      adminClient(),
      await ipBucketKey(req),
      'park-course-report:anon',
      PARK_COURSE_REPORT_ADDRESS_PER_HOUR,
      3600,
      { failClosed: true },
    ),
  submit: async (report, reporterId) => {
    const { error } = await adminClient().rpc('submit_park_course_report', {
      p_course_id: report.courseId,
      p_reason: report.reason,
      p_notes: report.notes,
      // Omitted rather than null: the generated Args type has no null, and
      // the SQL default for both is null.
      p_contact_email: report.contactEmail ?? undefined,
      p_reporter_id: reporterId ?? undefined,
    });
    return { errorCode: error ? (error.code ?? 'unknown') : null };
  },
});

Deno.serve(withCors(withSentry('park-course-report', handler)));
