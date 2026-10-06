import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { clientIdFor, hasAppleIdentity, parseAppleTokenRequest } from './lib.ts';

Deno.test('exactly one credential is accepted, trimmed', () => {
  assertEquals(parseAppleTokenRequest({ authorization_code: ' c0de ' }), { kind: 'code', code: 'c0de' });
  assertEquals(parseAppleTokenRequest({ refresh_token: 'r.tok' }), { kind: 'refresh_token', refreshToken: 'r.tok' });
});

Deno.test('both, neither, a blank, a non-string or an oversized credential is refused', () => {
  for (const body of [
    { authorization_code: 'c', refresh_token: 'r' },
    {},
    { authorization_code: '   ' },
    { refresh_token: 42 },
    { authorization_code: 'x'.repeat(2049) },
    null,
    'c0de',
    undefined,
  ]) {
    assertEquals(parseAppleTokenRequest(body), null, JSON.stringify(body));
  }
});

Deno.test('a native code belongs to the bundle id, a web token to the Services ID', () => {
  const clients = { native: 'com.threkir.app', web: 'com.threkir.web' };
  assertEquals(clientIdFor({ kind: 'code', code: 'c' }, clients), 'com.threkir.app');
  assertEquals(clientIdFor({ kind: 'refresh_token', refreshToken: 'r' }, clients), 'com.threkir.web');
});

Deno.test('an unconfigured client yields no client id, so nothing unrevocable is stored', () => {
  assertEquals(clientIdFor({ kind: 'code', code: 'c' }, { native: null, web: 'w' }), null);
  assertEquals(clientIdFor({ kind: 'refresh_token', refreshToken: 'r' }, { native: 'n', web: null }), null);
});

Deno.test('only an account with an Apple identity may store an Apple token', () => {
  assertEquals(hasAppleIdentity({ identities: [{ provider: 'email' }, { provider: 'apple' }] }), true);
  assertEquals(hasAppleIdentity({ identities: [], app_metadata: { providers: ['apple'] } }), true);
  assertEquals(hasAppleIdentity({ identities: [{ provider: 'google' }], app_metadata: { providers: ['google'] } }), false);
  assertEquals(hasAppleIdentity({}), false);
});
