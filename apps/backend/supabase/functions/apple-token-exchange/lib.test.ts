import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { appleSubjectOf, clientIdFor, parseAppleTokenRequest } from './lib.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('a code carries the flow that issued it; a refresh token is always web', () => {
  assertEquals(parseAppleTokenRequest({ authorization_code: ' c0de ', client: 'native' }), {
    kind: 'code',
    code: 'c0de',
    flow: 'native',
  });
  assertEquals(parseAppleTokenRequest({ authorization_code: 'c', client: 'web' }), {
    kind: 'code',
    code: 'c',
    flow: 'web',
  });
  assertEquals(parseAppleTokenRequest({ refresh_token: 'r.tok' }), {
    kind: 'refresh_token',
    refreshToken: 'r.tok',
    flow: 'web',
  });
});

Deno.test('a code with no flow is refused rather than guessed', () => {
  // An Android code is issued to the Services ID; defaulting to the bundle id
  // is the bug that silently lost every Android user's revocation.
  for (const client of [undefined, '', 'ios', 42]) {
    assertEquals(parseAppleTokenRequest({ authorization_code: 'c', client }), null, String(client));
  }
});

Deno.test('both, neither, a blank, a non-string or an oversized credential is refused', () => {
  for (const body of [
    { authorization_code: 'c', refresh_token: 'r', client: 'native' },
    {},
    { authorization_code: '   ', client: 'native' },
    { refresh_token: 42 },
    { authorization_code: 'x'.repeat(2049), client: 'native' },
    null,
    'c0de',
    undefined,
  ]) {
    assertEquals(parseAppleTokenRequest(body), null, JSON.stringify(body));
  }
});

Deno.test('each flow maps to its own Apple client, and an unconfigured one to none', () => {
  const clients = { native: 'com.threkir.app', web: 'com.threkir.web' };
  assertEquals(clientIdFor({ kind: 'code', code: 'c', flow: 'native' }, clients), 'com.threkir.app');
  assertEquals(clientIdFor({ kind: 'code', code: 'c', flow: 'web' }, clients), 'com.threkir.web');
  assertEquals(clientIdFor({ kind: 'refresh_token', refreshToken: 'r', flow: 'web' }, clients), 'com.threkir.web');
  assertEquals(clientIdFor({ kind: 'code', code: 'c', flow: 'native' }, { native: null, web: 'w' }), null);
  assertEquals(clientIdFor({ kind: 'refresh_token', refreshToken: 'r', flow: 'web' }, { native: 'n', web: null }), null);
});

Deno.test("the account's Apple subject comes from its Apple identity only", () => {
  assertEquals(
    appleSubjectOf({
      identities: [
        { provider: 'google', id: 'g-1', identity_data: { sub: 'g-1' } },
        { provider: 'apple', id: 'a-1', identity_data: { sub: '001.apple.sub' } },
      ],
    }),
    '001.apple.sub',
  );
  assertEquals(appleSubjectOf({ identities: [{ provider: 'apple', id: 'a-2', identity_data: null }] }), 'a-2');
  assertEquals(appleSubjectOf({ identities: [{ provider: 'google', id: 'g' }] }), null);
  assertEquals(appleSubjectOf({}), null);
});

Deno.test('the handler checks identity, rate limit, config, then Apple, then the subject, before storing', () => {
  const order = [
    'appleSubjectOf(user)',
    'checkRateLimit(',
    'appleKeyConfigFromEnv()',
    'exchangeAppleCode(',
    'proven.sub !== appleSub',
    "rpc('set_apple_refresh_token'",
  ].map((needle) => {
    const at = SRC.indexOf(needle);
    assert(at !== -1, `index.ts no longer contains ${needle}`);
    return at;
  });
  assertEquals([...order].sort((a, b) => a - b), order, 'the checks moved out of order');
  assert(SRC.includes('verifyAppleRefreshToken('), 'a web refresh token must be proven with Apple, not trusted');
});
