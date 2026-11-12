/// The pure rules behind park-course-report's signed-out limit: which reasons
/// carry a deadline, and which per-address bucket each request spends.
///
/// Run with:
///   cd apps/backend && deno test --no-check --allow-read --allow-env \
///     supabase/functions/park-course-report/

import { assertEquals, assertNotEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { addressBucket, COURSE_REPORT_REASONS, isDeadlineReason } from './lib.ts';

const IP = '203.0.113.7';

Deno.test('isDeadlineReason is true for the land-manager and rights-holder requests only', () => {
  assertEquals(isDeadlineReason('land_manager_request'), true);
  assertEquals(isDeadlineReason('rights_holder_request'), true);
  for (const reason of ['course_hazard', 'course_closure', 'course_off_trail', 'other'] as const) {
    assertEquals(isDeadlineReason(reason), false, reason);
  }
  assertEquals(COURSE_REPORT_REASONS.filter(isDeadlineReason).length, 2);
});

Deno.test('addressBucket: an ordinary report spends the ordinary bucket, with or without an address', () => {
  assertEquals(addressBucket('other', IP), 'park-course-report:anon');
  assertEquals(addressBucket('course_hazard', null), 'park-course-report:anon');
});

Deno.test('addressBucket: a deadline request with an address spends the per-address deadline bucket', () => {
  assertEquals(addressBucket('land_manager_request', IP), 'park-course-report:anon:deadline');
  assertEquals(addressBucket('rights_holder_request', IP), 'park-course-report:anon:deadline');
});

Deno.test('addressBucket: a deadline request with no address spends a shared bucket, never none', () => {
  // A header-less caller used to spend no per-address bucket on a deadline
  // reason, so the database's 120-an-hour cap was the only bound on the admin
  // notices it raised.
  for (const reason of ['land_manager_request', 'rights_holder_request'] as const) {
    const bucket = addressBucket(reason, null);
    assertEquals(bucket, 'park-course-report:anon:deadline:unknown');
    assertNotEquals(bucket, addressBucket('other', null), 'ordinary header-less traffic cannot lock it out');
    assertNotEquals(bucket, addressBucket(reason, IP));
  }
});
