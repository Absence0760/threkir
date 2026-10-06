import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  type AppleKeyConfig,
  appleClientSecret,
  appleClientsFromEnv,
  appleKeyConfigFromEnv,
  exchangeAppleCode,
  revokeAppleToken,
} from './apple_auth.ts';

async function testKey(): Promise<{ cfg: AppleKeyConfig; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let bin = '';
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`;
  return {
    cfg: { teamId: 'TEAM123456', keyId: 'KEY1234567', privateKeyPem: pem },
    publicKey: pair.publicKey,
  };
}

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  return Uint8Array.from(atob(pad), (c) => c.charCodeAt(0));
}

const env = (vars: Record<string, string>) => (k: string) => vars[k];

Deno.test('the key config is fail-closed: any missing piece means no config', () => {
  const full = { APPLE_TEAM_ID: 't', APPLE_KEY_ID: 'k', APPLE_PRIVATE_KEY: 'p' };
  assertEquals(appleKeyConfigFromEnv(env(full)), { teamId: 't', keyId: 'k', privateKeyPem: 'p' });
  for (const missing of Object.keys(full)) {
    const partial = { ...full, [missing]: '  ' };
    assertEquals(appleKeyConfigFromEnv(env(partial)), null, missing);
  }
});

Deno.test('client ids are read per flow and blank means absent', () => {
  assertEquals(
    appleClientsFromEnv(env({ APPLE_NATIVE_CLIENT_ID: 'com.threkir.app', APPLE_WEB_CLIENT_ID: '' })),
    { native: 'com.threkir.app', web: null },
  );
});

Deno.test('the client secret is an ES256 JWT Apple can verify, scoped to the client', async () => {
  const { cfg, publicKey } = await testKey();
  const jwt = await appleClientSecret(cfg, 'com.threkir.app', 1_800_000_000);
  const [h, p, s] = jwt.split('.');
  const dec = new TextDecoder();
  assertEquals(JSON.parse(dec.decode(b64urlDecode(h))), { alg: 'ES256', kid: 'KEY1234567' });
  assertEquals(JSON.parse(dec.decode(b64urlDecode(p))), {
    iss: 'TEAM123456',
    iat: 1_800_000_000,
    exp: 1_800_000_300,
    aud: 'https://appleid.apple.com',
    sub: 'com.threkir.app',
  });
  const ok = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    publicKey,
    b64urlDecode(s),
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert(ok, 'signature must verify against the key that signed it');
});

Deno.test('a PEM whose newlines were flattened to literal \\n still signs', async () => {
  const { cfg } = await testKey();
  const flattened = { ...cfg, privateKeyPem: cfg.privateKeyPem.replace(/\n/g, '\\n') };
  assertEquals((await appleClientSecret(flattened, 'x')).split('.').length, 3);
});

type Call = { url: string; form: URLSearchParams };
function fakeFetch(status: number, body: unknown, calls: Call[]) {
  return (url: string, init: RequestInit) => {
    calls.push({ url, form: init.body as URLSearchParams });
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
}

Deno.test('the code exchange posts the code and returns the refresh token', async () => {
  const { cfg } = await testKey();
  const calls: Call[] = [];
  const r = await exchangeAppleCode({
    cfg,
    clientId: 'com.threkir.app',
    code: 'c0de',
    fetchFn: fakeFetch(200, { refresh_token: 'r.tok', access_token: 'a' }, calls),
  });
  assertEquals(r, { refreshToken: 'r.tok' });
  assertEquals(calls[0].url, APPLE_TOKEN_URL);
  assertEquals(calls[0].form.get('grant_type'), 'authorization_code');
  assertEquals(calls[0].form.get('code'), 'c0de');
  assertEquals(calls[0].form.get('client_id'), 'com.threkir.app');
  assertEquals(calls[0].form.get('client_secret')?.split('.').length, 3);
});

Deno.test('an exchange Apple refuses, or answers without a refresh token, is an error', async () => {
  const { cfg } = await testKey();
  const refused = await exchangeAppleCode({
    cfg,
    clientId: 'x',
    code: 'used',
    fetchFn: fakeFetch(400, { error: 'invalid_grant' }, []),
  });
  assertEquals(refused, { error: 'apple token 400: invalid_grant' });
  const empty = await exchangeAppleCode({ cfg, clientId: 'x', code: 'c', fetchFn: fakeFetch(200, {}, []) });
  assert('error' in empty);
});

Deno.test('revocation posts the refresh token with its type hint', async () => {
  const { cfg } = await testKey();
  const calls: Call[] = [];
  assert(await revokeAppleToken({ cfg, clientId: 'svc.id', token: 'r.tok', fetchFn: fakeFetch(200, {}, calls) }));
  assertEquals(calls[0].url, APPLE_REVOKE_URL);
  assertEquals(calls[0].form.get('token'), 'r.tok');
  assertEquals(calls[0].form.get('token_type_hint'), 'refresh_token');
  assertEquals(calls[0].form.get('client_id'), 'svc.id');
  assertEquals(
    await revokeAppleToken({ cfg, clientId: 'svc.id', token: 't', fetchFn: fakeFetch(400, {}, []) }),
    false,
  );
});
