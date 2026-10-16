import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import { isUpstreamTimeout, UPSTREAM_TIMEOUT_MS } from '../_shared/upstream_deadline.ts';
import { nearHintError, parseNearHint, providerRacesUrl } from './lib.ts';
import { parkrunEventsEnabled, PARKRUN_EVENTS_URL } from './parkrun.ts';
import { syncParkrunPayload, syncProviderPayload } from './write.ts';

// Pull a provider's upcoming races into race_listings.
//
// RunSignUp's listings feed is public, so its leg runs with or without
// `RUNSIGNUP_API_KEY` / `_SECRET`: they are sent when both are set and are not
// a gate (measured 2026-10-14 — `GET /Rest/races` answers 200 keyless). The
// UltraSignup leg stays GATED on its own key pair and returns 503 until one is
// provisioned, because its endpoint and field names are still unverified. The
// RunSignUp reader in ./lib.ts is built against the observed payload; the
// UltraSignup one keeps the optional-with-drop rule, so a payload shaped
// differently answers `synced: 0` with `unusable` equal to the row count rather
// than writing junk into a calendar every user reads (decisions § 977).
//
// The parkrun leg reads parkrun's public events file and is OFF unless
// `PARKRUN_EVENTS_ENABLED` is exactly `true`: listing parkrun's events waits on
// parkrun's written permission (#1148), so it answers 503 to a probe and a sync
// alike until an operator turns it on (decisions § 1958).
//
// It writes as the SERVICE ROLE, not as the caller: a provider race is
// `is_verified`, and the `race_listings_force_unverified` trigger forces false
// for every other role. The caller's own client is still what identifies them
// and spends their rate-limit bucket. The write itself — reading the payload,
// placing each race from its ZIP, reconciling — is ./write.ts, which the
// scheduled `race-listings-sweep` shares (decisions § 1902).

interface RequestBody {
  near?: unknown; // { postal_code?, lng?, lat?, radius_m? } region hint, see NearHint
  provider?: unknown; // 'runsignup' (default) | 'ultrasignup' | 'parkrun' — which leg to gate/sync
  sync?: unknown; // true to actually walk the feed; anything else is a credential probe
}

Deno.serve(withSentry('race-listings-sync', async (req: Request) => {
  const guarded = await readJsonWithLimit<RequestBody>(req, 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const supabase = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    publishableKey(),
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const body = (guarded.body ?? {}) as RequestBody;
  const isSync = body.sync === true;

  // Two buckets, because these are two different costs wearing one name.
  //
  // A SYNC walks a provider's upcoming-races feed on OUR credential and writes
  // the shared public calendar rather than the caller's own rows, so 2/hour free
  // is right and a limiter that disappears on an RPC blip drops the only bound
  // on how often one account can drive it (decisions § 974).
  //
  // A PROBE reads two env vars and returns. Charging it to the sync's bucket was
  // a live defect and web's own client comment describes the symptom without
  // naming the cause: both `isRunSignUpConfigured` and `isUltraSignUpConfigured`
  // hit this function back then, so ONE page load spent a free user's whole 2/hour
  // allowance and the next load 429s — which `isProviderNotConfigured` then
  // fail-closes into "provider unavailable" for a provider that is configured
  // and working (decisions § 977). Its own generous bucket costs nothing and
  // removes the false unavailability.
  const denied = isSync
    ? await checkRateLimitTiered(supabase, user.id, 'race-listings-sync', 2, 8, 3600, {
      failClosed: true,
    })
    : await checkRateLimitTiered(supabase, user.id, 'race-listings-sync:probe', 60, 240, 3600, {
      failClosed: true,
    });
  if (denied) return denied;

  // An unrecognised provider is refused, not silently read as the default.
  // Coercing it to RunSignUp gated the caller's request on a credential for a
  // provider they never asked for — a 503 when RunSignUp's key is missing, and
  // a `synced: 0` success once it lands, for a provider this function has
  // never heard of. `race-results-import` already answers 400 here and names
  // this the same class of bug as claiming an unconfigured leg is configured.
  const requested = body.provider ?? 'runsignup';
  if (requested !== 'runsignup' && requested !== 'ultrasignup' && requested !== 'parkrun') {
    return Response.json({ error: 'unknown_provider' }, { status: 400 });
  }
  const provider = requested;
  if (provider === 'parkrun' && !parkrunEventsEnabled(Deno.env.get('PARKRUN_EVENTS_ENABLED'))) {
    return Response.json({ error: 'provider_not_configured' }, { status: 503 });
  }
  const apiKey = provider === 'ultrasignup'
    ? Deno.env.get('ULTRASIGNUP_API_KEY')
    : Deno.env.get('RUNSIGNUP_API_KEY');
  const apiSecret = provider === 'ultrasignup'
    ? Deno.env.get('ULTRASIGNUP_API_SECRET')
    : Deno.env.get('RUNSIGNUP_API_SECRET');
  // UltraSignup fails closed on a missing key pair; RunSignUp's feed is public
  // and needs none, so its key is optional and never a gate.
  const credentialRequired = provider === 'ultrasignup';
  if (credentialRequired && (!apiKey || !apiSecret)) {
    return Response.json({ error: 'provider_not_configured' }, { status: 503 });
  }

  // A call that does not ask for a sync is a PROBE and gets the availability
  // verdict alone: walking the feed would write the shared calendar and spend
  // the 2/hour bucket on a page load. No client probes this function today —
  // web and mobile ask `race-results-import`, the leg their tiles gate
  // (decisions § 1041) — but the opt-in stays so one never triggers a sync by
  // accident (decisions § 977).
  if (!isSync) {
    return Response.json({ configured: true });
  }

  const nearHint = parseNearHint(body.near);
  if (!nearHint.ok) {
    return Response.json({ error: nearHint.error }, { status: 400 });
  }
  const nearError = nearHintError(provider, nearHint.near);
  if (nearError) {
    return Response.json({ error: nearError }, { status: 400 });
  }

  // One bound over the headers and the body, the sweep's (UPSTREAM_TIMEOUT_MS).
  const signal = AbortSignal.timeout(UPSTREAM_TIMEOUT_MS);
  const userAgent = (provider === 'parkrun' ? Deno.env.get('PARKRUN_USER_AGENT') : undefined) ||
    Deno.env.get('RACE_IMPORT_USER_AGENT');
  let upstream: Response;
  try {
    upstream = await fetch(
      provider === 'parkrun' ? PARKRUN_EVENTS_URL : providerRacesUrl({
        provider,
        apiKey: apiKey ?? null,
        apiSecret: apiSecret ?? null,
        near: nearHint.near,
      }),
      { headers: { 'User-Agent': userAgent || 'RunApp/1.0' }, signal },
    );
  } catch (err) {
    return isUpstreamTimeout(err)
      ? Response.json({ error: `${provider} upstream timeout` }, { status: 504 })
      : Response.json({ error: `${provider} upstream unreachable` }, { status: 502 });
  }
  if (!upstream.ok) {
    // Fail loud on a non-2xx rather than feeding an error page into the parser
    // and reporting `synced: 0`, which is indistinguishable from a region with
    // no races. Same rule as both sibling importers.
    return Response.json({ error: `${provider} upstream ${upstream.status}` }, { status: 502 });
  }
  let payload: unknown;
  try {
    payload = await upstream.json();
  } catch (err) {
    return isUpstreamTimeout(err)
      ? Response.json({ error: `${provider} upstream timeout` }, { status: 504 })
      : Response.json({ error: `${provider} upstream not JSON` }, { status: 502 });
  }

  const service = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());
  const point = nearHint.near?.point;
  const outcome = provider === 'parkrun'
    ? await syncParkrunPayload(
      service,
      payload,
      { kind: 'near', lat: point!.lat, lng: point!.lng, radiusM: nearHint.near!.radiusM },
      Date.now(),
    )
    : await syncProviderPayload(service, provider, payload);
  if (!outcome.ok) return Response.json({ error: outcome.error }, { status: outcome.status });
  return Response.json(outcome.summary);
}));
