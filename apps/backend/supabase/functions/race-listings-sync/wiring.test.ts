/// The provider selector, which is the whole of this function's decision
/// surface today.
///
/// `race-listings-sync` had no test of any kind. Its body is a bare
/// `Deno.serve` with no exports, so these are source greps in the
/// `delete-account/wiring.test.ts` idiom, each paired with the positive it
/// depends on.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/race-listings-sync/wiring.test.ts`.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const SIBLING = await Deno.readTextFile(
  new URL('../race-results-import/handler.ts', import.meta.url),
);

Deno.test('an unrecognised provider is refused, not read as the default', () => {
  // `body.provider === 'ultrasignup' ? 'ultrasignup' : 'runsignup'` gated a
  // caller's request on a credential for a provider they never named: a 503
  // while RunSignUp's key is missing, and a `synced: 0` success once it lands,
  // for a provider this function has never heard of.
  assert(
    /if \(requested !== 'runsignup' && requested !== 'ultrasignup'\) \{/.test(SRC),
    'the provider must be validated against the set it supports',
  );
  const refusal = SRC.slice(SRC.indexOf("requested !== 'runsignup'"));
  assert(
    /'unknown_provider'[\s\S]{0,60}status: 400/.test(refusal),
    'an unknown provider must answer 400 unknown_provider',
  );
  assert(
    !/body\.provider === 'ultrasignup' \? 'ultrasignup' : 'runsignup'/.test(SRC),
    'the coercing selector must not come back',
  );
  // The sibling this is aligned with still answers the same way, so the two
  // legs of one feature cannot drift apart again unnoticed.
  assert(
    SIBLING.includes("'unknown_provider'"),
    'race-results-import must still refuse an unknown provider too',
  );
});

Deno.test('an omitted provider still defaults, so the refusal costs nothing', () => {
  assert(
    /const requested = body\.provider \?\? 'runsignup';/.test(SRC),
    'an absent provider must still default to RunSignUp',
  );
});

Deno.test('UltraSignup is gated on its own key pair; RunSignUp listings are keyless', () => {
  // RunSignUp's `GET /Rest/races` answers 200 with no key (measured
  // 2026-10-14), so gating the leg on RUNSIGNUP_API_KEY kept a public feed out
  // of the calendar on every deployment without a partner key — which is all of
  // them. UltraSignup's endpoint is still unverified and stays fail-closed.
  assert(SRC.includes("Deno.env.get('ULTRASIGNUP_API_KEY')"), 'the ultrasignup key is not read');
  assert(SRC.includes("Deno.env.get('RUNSIGNUP_API_KEY')"), 'the runsignup key is not read');
  assert(
    /const credentialRequired = provider === 'ultrasignup';/.test(SRC),
    'only UltraSignup may require a credential',
  );
  assert(
    /if \(credentialRequired && \(!apiKey \|\| !apiSecret\)\) \{[\s\S]{0,140}status: 503/.test(SRC),
    'a missing UltraSignup key OR secret must answer 503 provider_not_configured',
  );
  assert(
    !/if \(!apiKey \|\| !apiSecret\) \{/.test(SRC),
    'an unconditional key gate would close the public RunSignUp feed again',
  );
  const gate = SRC.indexOf('if (credentialRequired && (!apiKey || !apiSecret))');
  // Against the outbound FETCH: the thing a missing credential must stop is the
  // request going out at all (decisions § 977).
  const out = SRC.indexOf('await fetch(');
  assert(gate !== -1, 'the credential gate is gone');
  assert(out !== -1, 'the leg makes no outbound call at all — is it a stub again?');
  assert(gate < out, 'the credential gate must precede the outbound fetch');
});

Deno.test('a region hint the provider cannot search by is refused before the fetch', () => {
  const check = SRC.indexOf('nearHintError(provider, nearHint.near)');
  const out = SRC.indexOf('await fetch(');
  assert(check !== -1, 'the per-provider hint check is gone');
  assert(check < out, 'an unsearchable hint must be refused before the request goes out');
  assert(/if \(nearError\) \{[\s\S]{0,80}status: 400/.test(SRC), 'it must answer 400');
});

Deno.test('the caller is identified and throttled before the gate is spent', () => {
  const auth = SRC.indexOf('await supabase.auth.getUser()');
  const limit = SRC.indexOf('checkRateLimitTiered(');
  const gate = SRC.indexOf('const requested =');
  assert(auth !== -1 && limit !== -1 && gate !== -1);
  assert(auth < limit, 'the caller must be identified before their bucket is chosen');
  assert(limit < gate, 'the throttle must precede the provider work');
  assert(
    /checkRateLimitTiered\(supabase, user\.id, 'race-listings-sync', 2, 8, 3600, \{\s*failClosed: true,?\s*\}\)/
      .test(SRC),
    'the tiered ceilings and window must stay 2 / 8 per hour, and fail closed',
  );
});

Deno.test('the calendar write runs as the service role, not as the caller', () => {
  // `race_listings_force_unverified` (migration `20270214_001`) forces
  // `is_verified` false for every role but service_role, and the INSERT policy
  // requires `submitted_by = auth.uid()` — so a provider race written on the
  // caller's client would land as an unverified crowd submission attributed to
  // whoever happened to trigger the sync (decisions § 977). The write itself
  // lives in write.ts (write.test.ts drives it); this pins the client it gets.
  assert(SRC.includes("import { publishableKey, secretKey }"), 'the secret key is not imported');
  const service = SRC.indexOf('const service = createClient<Database>(Deno.env.get(\'SUPABASE_URL\')!, secretKey());');
  assert(service !== -1, 'the write client is not the service role');
  assert(
    SRC.includes('await syncProviderPayload(service, provider, payload)'),
    'the write does not go through the service client',
  );
  assert(!/syncProviderPayload\(supabase/.test(SRC), 'the caller-scoped client must never write');
  assert(
    !/supabase\s*\n?\s*\.from\('race_listings'\)/.test(SRC),
    'the caller-scoped client must never write race_listings',
  );
});

Deno.test('an upstream that is not 2xx or not JSON fails loud, and writes nothing', () => {
  // Feeding an error page into the parser answers `synced: 0`, which is
  // indistinguishable from a region with no races.
  assert(/if \(!upstream\.ok\) \{[\s\S]{0,400}?status: 502/.test(SRC), 'a non-2xx is not refused');
  assert(
    /upstream not JSON` \}, \{ status: 502 \}/.test(SRC),
    'an unparseable body is not refused',
  );
  const bad = SRC.indexOf('if (!upstream.ok)');
  const write = SRC.indexOf('syncProviderPayload(service');
  assert(bad !== -1 && write !== -1 && bad < write, 'the upstream check must precede any write');
});

Deno.test('a call that did not ask for a sync performs none', () => {
  // No client probes this function any more — web and mobile ask
  // `race-results-import`, the leg their tiles gate (§ 1041). The assertions
  // are about `index.ts` refusing to walk the provider feed for a caller that
  // did not ask for a sync, which would write the shared calendar on a page
  // load and spend the 2/hour bucket (decisions § 977).
  const gate = SRC.indexOf('if (!isSync) {');
  const out = SRC.indexOf('await fetch(');
  const write = SRC.indexOf('syncProviderPayload(service');
  assert(gate !== -1, 'a sync runs without the caller asking for one');
  assert(out !== -1 && write !== -1);
  assert(gate < out, 'the opt-in must precede the outbound fetch');
  assert(gate < write, 'the opt-in must precede any write');
  assert(
    /if \(!isSync\) \{\s*return Response\.json\(\{ configured: true \}\);/.test(SRC),
    'a probe must answer the availability verdict, not a sync result',
  );
  // And it must sit BEHIND the UltraSignup credential gate, or an
  // unprovisioned deploy would report that leg configured.
  const cred = SRC.indexOf('if (credentialRequired && (!apiKey || !apiSecret))');
  assert(cred !== -1 && cred < gate, 'the probe answer must follow the credential gate');
});

Deno.test('a probe does not spend the sync bucket', () => {
  // Both web probes hit this function when the split was written, so charging
  // them to the sync's 2/hour free ceiling meant ONE page load exhausted it and
  // the next load 429'd — which `isProviderNotConfigured` fail-closes into
  // "provider unavailable" for a provider that is configured and working. The
  // separate bucket is what fixed it (decisions § 977); no probe reaches here
  // today, and it keeps a future one off the sync's allowance.
  assert(
    /checkRateLimitTiered\(supabase, user\.id, 'race-listings-sync', 2, 8, 3600/.test(SRC),
    'the sync ceiling moved',
  );
  assert(
    /checkRateLimitTiered\(supabase, user\.id, 'race-listings-sync:probe', \d+, \d+, 3600/.test(SRC),
    'the probe shares the sync bucket again',
  );
  const buckets = [...SRC.matchAll(/'race-listings-sync(:probe)?'/g)].length;
  assert(buckets >= 2, 'only one bucket name is present');
  // Both fail closed; the guard in _shared covers every call site, and this
  // states it here too because the two arms are chosen by a condition.
  assert(
    (SRC.match(/failClosed: true/g) ?? []).length >= 2,
    'one of the two arms falls open',
  );
});

Deno.test('the caller sync bounds its upstream request the way the sweep does', () => {
  // A feed that accepts the connection and never answers held the caller's
  // request until the runtime killed it; the sweep's handler.test.ts drives the
  // same bound behaviourally, and this pins that the caller path shares it.
  assert(SRC.includes('const signal = AbortSignal.timeout(UPSTREAM_TIMEOUT_MS);'), 'the bound is gone');
  assert(
    /await fetch\([\s\S]{0,400}?'RunApp\/1\.0' \}, signal \}/.test(SRC),
    'the signal must ride on the outbound fetch',
  );
  assert(/upstream timeout` \}, \{ status: 504 \}/.test(SRC), 'a timeout must answer 504');
});
