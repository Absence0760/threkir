// Keeps a revocable Sign in with Apple credential for the signed-in user, so
// delete-account can revoke it (App Store Guideline 5.1.1(v)). Called right
// after an Apple sign-in: iOS and Android post the one-time authorization
// code with the flow that issued it, which is exchanged here for a refresh
// token; web posts the refresh token from its OAuth session, which is proven
// by spending it once. Either way Apple's answer names the Apple user, and
// the token is kept only when that is the caller's own Apple identity. It
// goes into Vault via set_apple_refresh_token and never comes back out.
//
// Fail-closed: without the Apple key (APPLE_TEAM_ID / APPLE_KEY_ID /
// APPLE_PRIVATE_KEY) or the client id for the calling flow, it answers 503
// and stores nothing. Clients treat every failure as non-fatal; sign-in has
// already succeeded by the time they call.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import type { Database } from '../_shared/database.ts';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { publishableKey, secretKey } from '../_shared/api_keys.ts';
import {
  appleClientsFromEnv,
  appleKeyConfigFromEnv,
  exchangeAppleCode,
  verifyAppleRefreshToken,
} from '../_shared/apple_auth.ts';
import { appleSubjectOf, clientIdFor, parseAppleTokenRequest } from './lib.ts';

Deno.serve(withSentry('apple-token-exchange', async (req: Request) => {
  if (req.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const guarded = await readJsonWithLimit(req, 4 * 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;
  const request = parseAppleTokenRequest(guarded.body);
  if (!request) {
    return Response.json(
      { error: 'expected authorization_code with client native|web, or refresh_token' },
      { status: 400 },
    );
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });
  const userClient = createClient<Database>(
    Deno.env.get('SUPABASE_URL')!,
    publishableKey(),
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });
  const appleSub = appleSubjectOf(user);
  if (!appleSub) {
    return Response.json({ error: 'account has no Apple identity' }, { status: 403 });
  }

  const denied = await checkRateLimit(userClient, user.id, 'apple-token-exchange', 10, 3600, {
    failClosed: true,
  });
  if (denied) return denied;

  const cfg = appleKeyConfigFromEnv();
  const clientId = clientIdFor(request, appleClientsFromEnv());
  if (!cfg || !clientId) {
    return Response.json({ error: 'apple_not_configured' }, { status: 503 });
  }

  let proven: { refreshToken: string; sub: string } | { error: string };
  if (request.kind === 'code') {
    proven = await exchangeAppleCode({ cfg, clientId, code: request.code });
  } else {
    const verified = await verifyAppleRefreshToken({ cfg, clientId, refreshToken: request.refreshToken });
    proven = 'error' in verified ? verified : { refreshToken: request.refreshToken, sub: verified.sub };
  }
  if ('error' in proven) {
    console.error('apple-token-exchange: Apple refused the credential:', String(proven.error));
    return Response.json({ error: 'apple_exchange_failed' }, { status: 502 });
  }
  if (proven.sub !== appleSub) {
    console.error('apple-token-exchange: credential belongs to a different Apple user');
    return Response.json({ error: 'apple_subject_mismatch' }, { status: 403 });
  }

  const adminClient = createClient<Database>(Deno.env.get('SUPABASE_URL')!, secretKey());
  const { error } = await adminClient.rpc('set_apple_refresh_token', {
    p_user_id: user.id,
    p_client_id: clientId,
    p_refresh_token: proven.refreshToken,
  });
  if (error) {
    console.error('apple-token-exchange: store failed:', error.message);
    return Response.json({ error: 'store_failed' }, { status: 500 });
  }
  return new Response(null, { status: 204 });
}));
