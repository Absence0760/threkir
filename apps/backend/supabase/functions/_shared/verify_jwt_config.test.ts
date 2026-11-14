// Architecture guard over ../../config.toml's verify_jwt posture.
//
// The platform's verify_jwt gate only accepts JWTs. Functions reached
// by callers WITHOUT a user session (webhooks, cron, logged-out
// spectators whose supabase-js sends the publishable API key as the
// bearer) must therefore carry an explicit `verify_jwt = false` and
// authorize in-handler. This test fails when one of those functions
// loses its override — a regression that would 401 every anonymous
// caller — and when a NEW function turns the gate off without being
// added to the allowlist here (turning it off silently widens the
// anonymous surface).

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const ANON_REACHABLE = [
  'auth-email',
  'clip-public-track',
  // pg_cron's hourly re-check, authorised in-handler by the CRON_SECRET bearer.
  'club-verification-recheck',
  'donations-checkout',
  'events-refund-sweep',
  // A subscribed calendar app sends no header at all; the 96-hex URL token
  // is checked in-handler against a stored SHA-256 (plan-calendar/handler.ts).
  'plan-calendar',
  // A signed-out land manager or runner reporting a park course; the handler
  // verifies a JWT when sent and files through a service-role-only RPC.
  'park-course-report',
  // pg_cron's daily NPS alerts read, authorised in-handler by the CRON_SECRET bearer.
  'park-closures-sweep',
  'race-listings-sweep',
  'refresh-tokens',
  'revenuecat-webhook',
  // The job worker's server key is not a JWT on new-format projects; the key is
  // compared in-handler against the project's own (segment-match/lib.ts).
  'segment-match',
  'strava-webhook',
  'stripe-events-webhook',
].sort()

function verifyJwtFalseSections(toml: string): string[] {
  const out: string[] = []
  const sections = toml.split(/^\[/m)
  for (const s of sections) {
    const m = s.match(/^functions\.([A-Za-z0-9_-]+)\]/)
    if (!m) continue
    if (/^\s*verify_jwt\s*=\s*false\s*$/m.test(s)) out.push(m[1])
  }
  return out.sort()
}

Deno.test('every anon-reachable function has an explicit verify_jwt = false', async () => {
  // Reason: losing an override 401s every anonymous caller of that
  // function the moment clients send non-JWT publishable keys.
  const toml = await Deno.readTextFile(new URL('../../config.toml', import.meta.url))
  const off = verifyJwtFalseSections(toml)
  for (const fn of ANON_REACHABLE) {
    assert(
      off.includes(fn),
      `${fn} is reachable without a user JWT but config.toml no longer sets verify_jwt = false for it`,
    )
  }
})

Deno.test('clip-public-track serves a header-less caller as anon, rate-limited', async () => {
  // Reason: a signed-out browser sends the publishable key as `apikey` and
  // no Authorization header, because the key is not a JWT. The handler used
  // to refuse that with 401, which took the track off every public share
  // page; the e2e never saw it because the local functions relay injects the
  // stack's anon key as Authorization. Refusing a missing header bought no
  // protection: the publishable key ships in every page, so a bot can send
  // it. The abuse control is the per-IP bucket on the anon path, so that is
  // what is pinned here.
  const src = await Deno.readTextFile(
    new URL('../clip-public-track/index.ts', import.meta.url),
  )
  assert(
    !src.includes("{ error: 'missing authorization' }, { status: 401 }"),
    'clip-public-track must not refuse a signed-out caller for sending no Authorization header',
  )
  assert(
    src.includes("'clip-public-track:anon', 60, 3600, { failClosed: true }"),
    'the anon path must keep its fail-closed per-IP rate limit',
  )
})

Deno.test('no function disables verify_jwt without being on the anon-reachable allowlist', async () => {
  // Reason: a silent verify_jwt=false widens the anonymous surface —
  // the flip must arrive together with a caller audit here.
  const toml = await Deno.readTextFile(new URL('../../config.toml', import.meta.url))
  assertEquals(
    verifyJwtFalseSections(toml),
    ANON_REACHABLE,
    'a function turned verify_jwt off — if intentional, add it here with a caller audit',
  )
})
