/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/privacy_default.test.ts`.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import { importAudience, OWNER_ONLY, resolveImportAudience } from './privacy_default.ts';
import type { DbClient } from './database.ts';

Deno.test('public publishes', () => {
  assertEquals(importAudience({ privacy_default: 'public' }), { isPublic: true, followersOnly: false });
});

Deno.test('followers writes followers_only, never public', () => {
  assertEquals(importAudience({ privacy_default: 'followers' }), { isPublic: false, followersOnly: true });
});

Deno.test('an unset pref takes the registered private fallback', () => {
  assertEquals(importAudience({}), { isPublic: false, followersOnly: false });
  assertEquals(importAudience(null), { isPublic: false, followersOnly: false });
});

Deno.test('private and unknown values are owner-only', () => {
  // Positive first: the same function DOES widen for the values that ask it to.
  assertEquals(importAudience({ privacy_default: 'followers' }).followersOnly, true);
  for (const v of ['private', 'everyone', 7, true]) {
    assertEquals(importAudience({ privacy_default: v }), { isPublic: false, followersOnly: false });
  }
});

function client(answer: { data?: unknown; error?: unknown; throws?: boolean }): DbClient {
  const chain = {
    from: () => chain,
    select: () => chain,
    eq: () => chain,
    maybeSingle: () =>
      answer.throws
        ? Promise.reject(new Error('down'))
        : Promise.resolve({ data: answer.data ?? null, error: answer.error ?? null }),
  };
  return chain as unknown as DbClient;
}

Deno.test('resolveImportAudience reads the stored pref', async () => {
  assertEquals(
    await resolveImportAudience(client({ data: { prefs: { privacy_default: 'public' } } }), 'u1'),
    { isPublic: true, followersOnly: false },
  );
});

Deno.test('a failed settings read is owner-only, not the followers fallback', async () => {
  // An answered read with no row takes the followers fallback; a FAILED one
  // must not, so the two are asserted side by side.
  assertEquals(
    await resolveImportAudience(client({ data: null }), 'u1'),
    { isPublic: false, followersOnly: true },
  );
  const ownerOnly = { isPublic: false, followersOnly: false };
  assertEquals(await resolveImportAudience(client({ error: { message: 'x' } }), 'u1'), ownerOnly);
  assertEquals(await resolveImportAudience(client({ throws: true }), 'u1'), ownerOnly);
  assertEquals(OWNER_ONLY, ownerOnly);
});
