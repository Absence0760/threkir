/// Pure helpers for webhook signature + replay protection. Extracted
/// from `revenuecat-webhook` and `strava-webhook` so they can be unit-
/// tested without booting the function host or the Supabase stack.
///
/// Keep this file pure — no `Deno.env`, no `serve`, no network. It must
/// stay importable from a `deno test` that runs in milliseconds.

/// HMAC-SHA256 over `body` with `secret`, returned as lowercase hex.
/// Uses the runtime's built-in Web Crypto API — replaces the
/// `deno.land/x/hmac@v2.0.1` library that revenuecat-webhook used to
/// pull (deno.land/x tags aren't immutable, so a tag rewrite would
/// silently substitute the digest). FIPS-aligned, zero supply-chain
/// surface. /audit/all edge-functions Medium 2026-05-07.
///
/// Accepts string or Uint8Array for both inputs. The string branch
/// UTF-8 encodes via TextEncoder (lossless round-trip for valid UTF-8
/// — every RevenueCat / Strava webhook body is JSON, so the string
/// path is correct for every production caller). Tests that need to
/// pin against byte-exact RFC reference vectors pass Uint8Array so
/// non-ASCII bytes like 0xcd don't get UTF-8-expanded into two bytes.
export async function hmacHex(
  secret: string | Uint8Array,
  body: string | Uint8Array,
): Promise<string> {
  const enc = new TextEncoder();
  // Force a fresh Uint8Array<ArrayBuffer> view rather than the
  // Uint8Array<ArrayBufferLike> TextEncoder returns, which fails strict
  // BufferSource type-checking under recent Deno/TS lib versions even
  // though the runtime accepts both. /audit/all round-7 2026-05-24.
  const keyBytes: BufferSource =
    typeof secret === 'string' ? enc.encode(secret) : new Uint8Array(secret);
  const bodyBytes: BufferSource =
    typeof body === 'string' ? enc.encode(body) : new Uint8Array(body);
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, bodyBytes);
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/// Header a sender may carry a shared webhook secret in, instead of the
/// URL query string. A query-string secret is recorded verbatim in the
/// platform's request log on every delivery; a header is not, so this is
/// the path to prefer wherever the sender can be configured to use it.
/// Kept here (rather than per-function) so the Edge Function and the Go
/// worker's twin endpoint cannot drift on the name.
export const WEBHOOK_SECRET_HEADER = 'x-webhook-secret';

/// Constant-time string compare. Returns false on length mismatch
/// without short-circuiting on content. The length check itself is
/// observable, but the digest length is fixed (sha256 hex = 64 chars,
/// URL secrets are a known length too) and is not new information.
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

/// Verify a `t=<unix-seconds>,v1=<hex hmac-sha256>` signature header.
///
/// Stripe (`Stripe-Signature`) and RevenueCat
/// (`X-RevenueCat-Webhook-Signature`) both sign this way: the signed payload
/// is the literal string `${t}.${rawBody}`, keyed by the endpoint's signing
/// secret. There can be several v1 values during a secret rotation, and a
/// `v0` for older schemes, which we ignore.
///
/// Verification runs on the RAW request bytes — NOT a JSON.parse'd and
/// re-stringified body, which won't round-trip whitespace/key-order and
/// would break every signature.
///
/// Two gates, both required:
///   1. signature — recompute HMAC over `${t}.${rawBody}`, constant-time
///      compare against each `v1` value (any match passes — covers the
///      dual-signature rotation window).
///   2. freshness — reject if `|now - t|` exceeds the tolerance (default
///      5 min, the default both providers recommend). `t` is stamped per
///      delivery attempt, so a provider retry carries a fresh one; the gate
///      is what makes a captured POST replayed later fail even though its
///      HMAC is valid.
export async function verifyTimestampedHmac(
  rawBody: string,
  sigHeader: string | null,
  secret: string,
  nowMs: number,
  toleranceSec = 300,
): Promise<boolean> {
  if (!sigHeader || !secret) return false;

  const parts = sigHeader.split(',');
  let timestamp: number | null = null;
  const v1Sigs: string[] = [];
  for (const part of parts) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();
    if (key === 't') {
      // Exactly an integer literal. `Number.parseInt` stops at the first
      // character it cannot read, so `t=1700000000junk` and `t=+1700000000`
      // both recovered the real timestamp and verified — and because the
      // signed payload is rebuilt from the PARSED integer rather than from
      // the header text, a change to sign the text instead would have been
      // invisible to every test, since a clean header round-trips. Requiring
      // the two to be the same string removes the distinction.
      if (!/^\d+$/.test(value)) continue;
      const n = Number.parseInt(value, 10);
      if (Number.isFinite(n)) timestamp = n;
    } else if (key === 'v1') {
      v1Sigs.push(value);
    }
  }

  if (timestamp === null || v1Sigs.length === 0) return false;

  // Freshness — reject a stale (replayed) or wildly future-dated event.
  const ageSec = Math.abs(nowMs / 1000 - timestamp);
  if (ageSec > toleranceSec) return false;

  const expected = await hmacHex(secret, `${timestamp}.${rawBody}`);
  for (const candidate of v1Sigs) {
    if (timingSafeEqual(candidate, expected)) return true;
  }
  return false;
}

export type FreshnessOutcome = 'ok' | 'too_old' | 'too_future';

/// Bound an event's wall-clock to a (REPLAY_WINDOW, CLOCK_SKEW) window.
///
/// Both webhooks need the same gate: a captured POST replayed weeks
/// later must be rejected even though its HMAC / URL-secret still
/// validates. The window has to be:
///   - wider than the upstream provider's retry envelope (Strava and
///     RevenueCat both retry for ~3 days), so a delivery that failed
///     for a long-ish outage still ingests cleanly,
///   - narrower than the dedupe-row TTL (30 days, set by the
///     cleanup-stale-webhook-events cron in 20260623_001), so a
///     replay can't slip past the dedupe table's pruning horizon.
///
/// Default 7 days threads both. CLOCK_SKEW handles a future-dated
/// event_timestamp from clock drift on the provider side.
export function validateFreshness(
  eventTsMs: number,
  nowMs: number,
  windowMs: number = 7 * 24 * 60 * 60 * 1000,
  clockSkewMs: number = 60 * 1000,
): FreshnessOutcome {
  // A timestamp that is not a number has no age, and every comparison
  // against NaN is false — so the two gates below both fell through to
  // 'ok' and the replay window opened for anything a caller could make
  // unparseable. Both live callers happen to type-check their field
  // first, which is why nothing had noticed; the gate itself must not
  // depend on that. `too_old` rather than a fourth outcome: the callers
  // answer 400 on anything but 'ok', and an unusable stamp is at least
  // as suspect as a stale one.
  if (!Number.isFinite(eventTsMs) || !Number.isFinite(nowMs)) return 'too_old';
  const ageMs = nowMs - eventTsMs;
  if (ageMs > windowMs) return 'too_old';
  if (ageMs < -clockSkewMs) return 'too_future';
  return 'ok';
}

/// RevenueCat assigns `$RCAnonymousID:<random>` to users who haven't
/// signed in. We can't map them to a Supabase profile until they alias,
/// at which point RC fires another event. Returning a 200-skipped here
/// stops RC from retrying.
export function isAnonymousAppUserId(s: string): boolean {
  return typeof s === 'string' && s.startsWith('$RCAnonymousID');
}

/// Whether a dispatched handler's response means the insert-first dedupe row
/// must be given back before returning.
///
/// The dedupe row is written BEFORE the side effect so two concurrent
/// deliveries of one event can't both act. The cost is that a handler which
/// fails owes the row back: every provider here retries on a non-2xx, and the
/// retry would otherwise hit the 23505 path, answer 200 `duplicate_event`, and
/// close the delivery permanently. For `checkout.session.completed` that
/// leaves a charged card with the order stuck `pending`, no seat issued, and no
/// corrective event coming — nothing sweeps a lapsed reservation. For a
/// RevenueCat `NON_RENEWING_PURCHASE` it leaves a paid-for lifetime tier
/// ungranted, and unlike a subscription there is no later renewal to correct
/// it.
///
/// Keyed on 5xx specifically: the handlers return 200 for every outcome that
/// is genuinely final (unknown donation, missing metadata, already-terminal
/// status, an anonymous app user), and reserve 5xx for "we could not complete
/// this — try again".
///
/// It lives beside `validateFreshness` rather than in one webhook's lib
/// because it is the same rule for all three insert-first dedupers, and the
/// one that did not have it is the one that grants a paid tier.
export function shouldReleaseDedupe(status: number): boolean {
  return status >= 500;
}
