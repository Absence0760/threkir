// The parkrun leg's reachability probe, guarded in the
// `race-results-import/rate_limit_buckets.test.ts` idiom.
//
// parkrun needs no credential, so this probe answers a different question from
// its sibling's: not "is a key set" but "is this leg deployed at all" — the one
// a minimal deployment gets wrong, and the reason the Settings card can be kept
// off a deployment whose Edge Functions were never pushed. That makes two
// properties load-bearing and neither is visible from the client:
//
//   1. the probe must answer BEFORE the import's 4/hour bucket is charged, or
//      a handful of Settings loads consume a runner's whole import allowance
//      (the failure § 1007 describes, where an exhausted bucket answers 429 and
//      every client grades that as "provider unavailable");
//   2. it must answer before the scrape, since a probe that fetched
//      parkrun.org.uk would spend the deployment-wide IP reputation the import
//      bucket exists to protect.
//
// Source-level rather than behavioural because the handler needs a live
// Supabase to exercise; the claim is about statement order, which is readable.
import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

function offsetOf(pattern: RegExp, what: string): number {
  const m = SRC.match(pattern);
  assert(m?.index !== undefined, `${what} is no longer present in index.ts`);
  return m.index;
}

Deno.test('the probe answers before the import bucket is charged', () => {
  const probe = offsetOf(/if \(guarded\.body\?\.probe === true\) \{/, 'the probe branch');
  const importBucket = offsetOf(
    /checkRateLimitTiered\(supabase, user\.id, 'parkrun-import',/,
    "the import bucket's checkRateLimitTiered call",
  );
  assert(
    probe < importBucket,
    'the probe branch now runs after the 4/hour import bucket is charged, so opening ' +
      'Settings spends imports',
  );
});

Deno.test('the probe answers before the outbound parkrun fetch', () => {
  const probe = offsetOf(/return Response\.json\(\{ configured: true \}\);/, 'the probe response');
  const fetchOut = offsetOf(/await fetch\(url, \{/, 'the parkrun scrape');
  assert(
    probe < fetchOut,
    'the probe now falls through to the scrape, spending the deployment-wide parkrun ' +
      'IP reputation on a question that reads no upstream',
  );
});

Deno.test('the probe is authenticated', () => {
  const auth = offsetOf(
    /if \(!user\) return Response\.json\(\{ error: 'unauthorized' \}, \{ status: 401 \}\);/,
    'the auth check',
  );
  const probe = offsetOf(/if \(guarded\.body\?\.probe === true\) \{/, 'the probe branch');
  assert(
    auth < probe,
    'the probe branch now runs before the caller is authenticated, making the ' +
      'rate limiter it charges unattributable to a user',
  );
});

Deno.test('the probe has its own bucket, more generous than the import one, both fail closed', () => {
  function limits(bucket: string): [number, number] {
    const re = new RegExp(`'${bucket}',\\s*(\\d+),\\s*(\\d+),`);
    const m = SRC.match(re);
    assert(m, `no checkRateLimitTiered call for the ${bucket} bucket`);
    return [Number(m[1]), Number(m[2])];
  }
  const [probeFree, probePro] = limits('parkrun-import:probe');
  const [importFree, importPro] = limits('parkrun-import');
  assert(
    probeFree > importFree,
    `the probe bucket (${probeFree}/h free) is no more generous than the import bucket ` +
      `(${importFree}/h), so opening Settings still spends imports`,
  );
  assert(probePro > importPro, `the Pro probe bucket (${probePro}/h) is no more generous`);
  assert(
    (SRC.match(/failClosed: true/g) ?? []).length === 2,
    'both buckets must fail closed — falling open on an RPC blip drops the only bound ' +
      'on how often one account can drive either path (§ 974)',
  );
});
