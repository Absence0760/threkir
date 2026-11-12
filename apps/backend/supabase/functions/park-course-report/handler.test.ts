/// The park-course-report request path with fake deps: validation before any
/// rate-limit spend, the honeypot, the signed-in and signed-out buckets, the
/// reporter passed to the filing, and the database's refusals mapped to codes.
///
/// Run with:
///   cd apps/backend && deno test --no-check --allow-read --allow-env \
///     supabase/functions/park-course-report/

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { makeParkCourseReportHandler, type ParkCourseReportDeps } from './handler.ts';
import { type CourseReport, MAX_BODY_BYTES } from './lib.ts';

const URL = 'http://127.0.0.1:24321/functions/v1/park-course-report';
const COURSE = '6f1c2b8e-3a4d-4e5f-8a9b-0c1d2e3f4a5b';
const USER = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

interface Recorded {
  calls: string[];
  filed: { report: CourseReport; reporterId: string | null }[];
}

function deps(over: Partial<ParkCourseReportDeps> = {}): { deps: ParkCourseReportDeps; rec: Recorded } {
  const rec: Recorded = { calls: [], filed: [] };
  return {
    rec,
    deps: {
      resolveUser: (req) => {
        rec.calls.push('user');
        return Promise.resolve(req.headers.get('Authorization') === 'Bearer user-jwt' ? USER : null);
      },
      limitUser: (id) => {
        rec.calls.push(`limit-user:${id}`);
        return Promise.resolve(null);
      },
      limitAddress: (_req, reason) => {
        rec.calls.push(`limit-address:${reason}`);
        return Promise.resolve(null);
      },
      submit: (report, reporterId) => {
        rec.calls.push('submit');
        rec.filed.push({ report, reporterId });
        return Promise.resolve({ errorCode: null });
      },
      ...over,
    },
  };
}

function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

const VALID = {
  course_id: COURSE,
  reason: 'land_manager_request',
  notes: '  Please close it for restoration.  ',
  contact_email: ' office@park.example ',
};

Deno.test('a signed-out report is filed with no reporter, against the address bucket', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(post(VALID));
  assertEquals(res.status, 201);
  assertEquals(await res.json(), { ok: true });
  assertEquals(rec.calls, ['user', 'limit-address:land_manager_request', 'submit']);
  assertEquals(rec.filed, [{
    report: {
      courseId: COURSE,
      reason: 'land_manager_request',
      notes: 'Please close it for restoration.',
      contactEmail: 'office@park.example',
    },
    reporterId: null,
  }]);
});

Deno.test('a signed-in report is filed as that user, against the user bucket', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(post(
    { course_id: COURSE, reason: 'course_hazard', notes: 'Tree down.' },
    { Authorization: 'Bearer user-jwt' },
  ));
  assertEquals(res.status, 201);
  assertEquals(rec.calls, ['user', `limit-user:${USER}`, 'submit']);
  assertEquals(rec.filed[0].reporterId, USER);
  assertEquals(rec.filed[0].report.contactEmail, null);
});

Deno.test('a token that does not verify files signed out, never as a claimed user', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(post(VALID, { Authorization: 'Bearer forged' }));
  assertEquals(res.status, 201);
  assertEquals(rec.calls, ['user', 'limit-address:land_manager_request', 'submit']);
  assertEquals(rec.filed[0].reporterId, null);
});

Deno.test('a filled honeypot answers like a filed report and files nothing', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(post({ ...VALID, website: 'http://spam.example' }));
  assertEquals(res.status, 201);
  assertEquals(await res.json(), { ok: true });
  assertEquals(rec.calls, []);
});

Deno.test('malformed requests are refused before any rate-limit spend', async () => {
  const cases: [unknown, string][] = [
    ['not json', 'invalid_json'],
    [[1, 2], 'invalid_body'],
    [{ ...VALID, course_id: 'nope' }, 'invalid_course'],
    [{ ...VALID, reason: 'spam' }, 'invalid_reason'],
    [{ ...VALID, reason: 'organiser_dispute' }, 'invalid_reason'],
    [{ ...VALID, notes: '   ' }, 'notes_required'],
    [{ ...VALID, notes: 42 }, 'notes_required'],
    [{ ...VALID, notes: 'a'.repeat(1001) }, 'notes_too_long'],
    [{ ...VALID, contact_email: 'nobody' }, 'invalid_email'],
    [{ ...VALID, contact_email: 7 }, 'invalid_email'],
    [{ ...VALID, contact_email: `${'a'.repeat(250)}@b.example` }, 'invalid_email'],
    [{ ...VALID, reason: 'rights_holder_request', contact_email: null }, 'email_required'],
    [{ ...VALID, reason: 'rights_holder_request', contact_email: '  ' }, 'email_required'],
  ];
  for (const [body, error] of cases) {
    const { deps: d, rec } = deps();
    const res = await makeParkCourseReportHandler(d)(post(body));
    assertEquals(res.status, 400, `status for ${error}`);
    assertEquals((await res.json()).error, error);
    assertEquals(rec.calls, [], `no deps called for ${error}`);
  }
});

Deno.test('1000 characters of notes in a non-Latin script are within the limit', async () => {
  const { deps: d } = deps();
  const res = await makeParkCourseReportHandler(d)(post({ ...VALID, notes: 'あ'.repeat(1000) }));
  assertEquals(res.status, 201);
});

Deno.test('an empty contact email is no email', async () => {
  const { deps: d, rec } = deps();
  await makeParkCourseReportHandler(d)(post({ ...VALID, contact_email: '  ' }));
  assertEquals(rec.filed[0].report.contactEmail, null);
});

Deno.test('a rights-holder request with an address is filed with it', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(post({ ...VALID, reason: 'rights_holder_request' }));
  assertEquals(res.status, 201);
  assertEquals(rec.filed[0].report.reason, 'rights_holder_request');
  assertEquals(rec.filed[0].report.contactEmail, 'office@park.example');
});

Deno.test('a body over the byte cap is a 413 that spends nothing', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(post({ ...VALID, notes: 'a'.repeat(MAX_BODY_BYTES) }));
  assertEquals(res.status, 413);
  assertEquals(rec.calls, []);
});

Deno.test('only POST is served', async () => {
  const { deps: d, rec } = deps();
  const res = await makeParkCourseReportHandler(d)(new Request(URL, { method: 'GET' }));
  assertEquals(res.status, 405);
  assertEquals(rec.calls, []);
});

Deno.test('a rate-limit denial is returned and nothing is filed', async () => {
  const limited = Response.json({ error: 'rate_limit_exceeded' }, { status: 429 });
  const { deps: d, rec } = deps({ limitAddress: () => Promise.resolve(limited) });
  const res = await makeParkCourseReportHandler(d)(post(VALID));
  assertEquals(res.status, 429);
  assertEquals(rec.filed, []);
});

Deno.test('the database refusals map to codes and never forward a message', async () => {
  const cases: [string, number, string][] = [
    ['PT429', 429, 'rate_limited'],
    ['23505', 409, 'already_reported'],
    ['02000', 404, 'course_not_found'],
    ['22023', 400, 'invalid_report'],
    ['XX000', 500, 'report_failed'],
  ];
  for (const [code, status, error] of cases) {
    const { deps: d } = deps({ submit: () => Promise.resolve({ errorCode: code }) });
    const res = await makeParkCourseReportHandler(d)(post(VALID));
    assertEquals(res.status, status, code);
    assertEquals(await res.json(), { error });
  }
});

Deno.test('a thrown filing is a 500, not an unhandled rejection', async () => {
  const { deps: d } = deps({ submit: () => Promise.reject(new Error('network')) });
  const res = await makeParkCourseReportHandler(d)(post(VALID));
  assertEquals(res.status, 500);
  assertEquals(await res.json(), { error: 'report_failed' });
});

Deno.test('the address limit is told the reason, so a deadline request spends its own bucket', async () => {
  const { deps: d, rec } = deps();
  await makeParkCourseReportHandler(d)(post({ ...VALID, reason: 'other' }));
  await makeParkCourseReportHandler(d)(post(VALID));
  assertEquals(rec.calls.filter((c) => c.startsWith('limit-address')), [
    'limit-address:other',
    'limit-address:land_manager_request',
  ]);
});
