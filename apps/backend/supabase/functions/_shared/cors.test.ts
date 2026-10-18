/// Run with `cd apps/backend && deno test --no-check supabase/functions/_shared/cors.test.ts`.
/// (Pure: the runtime URL is injected, so no env or net flag is needed.)

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { ALLOWED_HEADERS, isAllowedOrigin, isLocalRuntime, withCors } from './cors.ts';

const HOSTED = () => 'https://mcbgrgvegqcmdmtraikl.supabase.co';
const LOCAL = () => 'http://kong:8000';

let reached = 0;
const ok = withCors(() => {
  reached++;
  return Response.json({ ok: true });
}, { supabaseUrl: HOSTED });

function req(method: string, origin: string | null, url = 'https://x/functions/v1/delete-account') {
  const headers = new Headers();
  if (origin) headers.set('Origin', origin);
  if (method === 'OPTIONS') {
    headers.set('Access-Control-Request-Method', 'POST');
    headers.set('Access-Control-Request-Headers', 'authorization, content-type, apikey, x-client-info');
  }
  return new Request(url, { method, headers });
}

Deno.test('preflight from the production site gets 204 and every header supabase-js sends', async () => {
  const before = reached;
  const res = await ok(req('OPTIONS', 'https://threkir.com'));
  assertEquals(res.status, 204);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), 'https://threkir.com');
  assertEquals(res.headers.get('Vary'), 'Origin');
  const methods = res.headers.get('Access-Control-Allow-Methods')!.split(', ');
  assert(methods.includes('POST') && methods.includes('OPTIONS'));
  const allowed = res.headers.get('Access-Control-Allow-Headers')!.split(', ');
  for (const h of ['authorization', 'content-type', 'apikey', 'x-client-info']) {
    assert(allowed.includes(h), `preflight does not allow ${h}`);
  }
  assertEquals(reached, before, 'a preflight must never reach the handler (auth, body parsing)');
});

Deno.test('www and preview origins are admitted in production', async () => {
  for (const o of ['https://www.threkir.com', 'https://preview.threkir.com']) {
    const res = await ok(req('OPTIONS', o));
    assertEquals(res.headers.get('Access-Control-Allow-Origin'), o);
  }
});

Deno.test('a disallowed origin gets no ACAO on the preflight or the response', async () => {
  for (const o of ['https://evil.example', 'https://threkir.com.evil.example', 'http://threkir.com', 'null']) {
    const pre = await ok(req('OPTIONS', o));
    assertEquals(pre.status, 204);
    assertEquals(pre.headers.get('Access-Control-Allow-Origin'), null, o);
    assertEquals(pre.headers.get('Access-Control-Allow-Headers'), null, o);
    const res = await ok(req('POST', o));
    assertEquals(res.headers.get('Access-Control-Allow-Origin'), null, o);
    assertEquals(res.headers.get('Vary'), 'Origin');
  }
});

Deno.test('an allowed origin gets ACAO on 4xx and 5xx responses too', async () => {
  for (const status of [400, 401, 405, 500, 503]) {
    const h = withCors(() => Response.json({ error: 'x' }, { status }), { supabaseUrl: HOSTED });
    const res = await h(req('POST', 'https://threkir.com'));
    assertEquals(res.status, status);
    assertEquals(res.headers.get('Access-Control-Allow-Origin'), 'https://threkir.com', String(status));
    assertEquals(await res.json(), { error: 'x' });
  }
});

Deno.test('a handler-set wildcard ACAO is stripped for a disallowed origin', async () => {
  const h = withCors(
    () => new Response('x', { headers: { 'Access-Control-Allow-Origin': '*', Vary: 'Accept-Encoding' } }),
    { supabaseUrl: HOSTED },
  );
  const res = await h(req('POST', 'https://evil.example'));
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), null);
  assertEquals(res.headers.get('Vary'), 'Accept-Encoding, Origin');
});

Deno.test('an immutable fetch-style response still gets the header', async () => {
  const upstream = Response.redirect('https://threkir.com/x', 302);
  const h = withCors(() => upstream, { supabaseUrl: HOSTED });
  const res = await h(req('POST', 'https://threkir.com'));
  assertEquals(res.status, 302);
  assertEquals(res.headers.get('Access-Control-Allow-Origin'), 'https://threkir.com');
});

Deno.test('local dev origins are rejected in production and admitted on the local stack', async () => {
  const local = [
    'http://localhost:7777',
    'http://127.0.0.1:7777',
    'http://localhost:8888',
    'http://127.0.0.1:8888',
  ];
  const onLocal = withCors(() => new Response('ok'), { supabaseUrl: LOCAL });
  for (const o of local) {
    const prod = await ok(req('OPTIONS', o));
    assertEquals(prod.headers.get('Access-Control-Allow-Origin'), null, `${o} admitted in production`);
    const dev = await onLocal(req('OPTIONS', o));
    assertEquals(dev.headers.get('Access-Control-Allow-Origin'), o);
  }
  const lookalike = await onLocal(req('OPTIONS', 'http://localhost.evil.example:7777'));
  assertEquals(lookalike.headers.get('Access-Control-Allow-Origin'), null);
});

Deno.test('only an http loopback/kong SUPABASE_URL counts as local; anything else is hosted', () => {
  assert(isLocalRuntime('http://kong:8000'));
  assert(isLocalRuntime('http://127.0.0.1:24321'));
  assert(!isLocalRuntime('https://mcbgrgvegqcmdmtraikl.supabase.co'));
  assert(!isLocalRuntime('https://localhost:24321'));
  assert(!isLocalRuntime('https://api.threkir.com'));
  assert(!isLocalRuntime(undefined));
  assert(!isLocalRuntime('not a url'));
});

Deno.test('a missing Origin is never admitted', () => {
  // The allowed case is what a broken helper cannot satisfy; refusals alone
  // pass against one that admits nothing.
  assert(isAllowedOrigin('https://threkir.com', true));
  assert(!isAllowedOrigin(null, true));
  assert(!isAllowedOrigin('', true));
});

Deno.test('the allowed headers cover the supabase-js cors list', () => {
  for (const h of ['authorization', 'x-client-info', 'apikey', 'content-type', 'x-retry-count', 'traceparent', 'tracestate', 'baggage']) {
    assert(ALLOWED_HEADERS.includes(h), h);
  }
});

Deno.test('methods are configurable per function', async () => {
  const h = withCors(() => new Response('ok'), { methods: ['GET', 'POST'], supabaseUrl: HOSTED });
  const res = await h(req('OPTIONS', 'https://threkir.com'));
  assertEquals(res.headers.get('Access-Control-Allow-Methods'), 'GET, POST, OPTIONS');
});
