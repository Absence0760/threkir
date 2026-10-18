/// CORS for the Edge Functions the web app calls from the browser.
///
/// threkir.com calls https://<ref>.supabase.co/functions/v1/<name> with an
/// `Authorization` bearer and a JSON body, so every call is preceded by an
/// `OPTIONS` preflight. The hosted gateway forwards that preflight to the
/// function untouched (even under `verify_jwt = true`), and a handler that
/// answers it 405 — or reaches its auth check and answers 401 — makes the
/// browser report "Failed to fetch" for a function that works fine from
/// Dart, which sends no preflight (decisions § 2121).
///
/// Usage, outermost so even withSentry's 500 carries the header:
///
///   Deno.serve(withCors(withSentry('delete-account', async (req) => { ... })));
///
/// Origins are an allowlist, not `*`: a disallowed origin gets no
/// `Access-Control-Allow-Origin`, so its browser refuses to hand the page the
/// response. Loopback origins are admitted only when SUPABASE_URL names the
/// local stack; an unparsable or unexpected SUPABASE_URL counts as hosted.

export const PRODUCTION_ORIGINS: readonly string[] = [
  'https://threkir.com',
  'https://www.threkir.com',
  'https://preview.threkir.com',
];

/// Every header supabase-js 2.x `functions.invoke` can send (mirrors the
/// SDK's own `@supabase/supabase-js/cors` list) plus `x-region`, which it
/// adds when a region is pinned. A header missing here fails the preflight.
export const ALLOWED_HEADERS: readonly string[] = [
  'authorization',
  'x-client-info',
  'apikey',
  'content-type',
  'x-region',
  'x-retry-count',
  'traceparent',
  'tracestate',
  'baggage',
];

const LOCAL_HOSTNAMES = new Set(['kong', 'localhost', '127.0.0.1', 'host.docker.internal']);
const LOOPBACK_HOSTNAMES = new Set(['localhost', '127.0.0.1']);

export function isLocalRuntime(supabaseUrl: string | undefined): boolean {
  if (!supabaseUrl) return false;
  try {
    const u = new URL(supabaseUrl);
    return u.protocol === 'http:' && LOCAL_HOSTNAMES.has(u.hostname);
  } catch {
    return false;
  }
}

export function isAllowedOrigin(origin: string | null, local: boolean): boolean {
  if (!origin) return false;
  if (PRODUCTION_ORIGINS.includes(origin)) return true;
  if (!local) return false;
  try {
    const u = new URL(origin);
    return u.protocol === 'http:' && LOOPBACK_HOSTNAMES.has(u.hostname) && u.origin === origin;
  } catch {
    return false;
  }
}

export interface CorsOptions {
  methods?: readonly string[];
  /// Injected by tests; defaults to the runtime's SUPABASE_URL.
  supabaseUrl?: () => string | undefined;
}

export function withCors(
  handler: (req: Request) => Promise<Response> | Response,
  opts: CorsOptions = {},
): (req: Request) => Promise<Response> {
  const methods = [...(opts.methods ?? ['POST']), 'OPTIONS'].join(', ');
  const readUrl = opts.supabaseUrl ?? (() => Deno.env.get('SUPABASE_URL'));

  return async (req: Request) => {
    const origin = req.headers.get('Origin');
    const allowed = isAllowedOrigin(origin, isLocalRuntime(readUrl()));

    if (req.method === 'OPTIONS') {
      const headers = new Headers({ Vary: 'Origin' });
      if (allowed) {
        headers.set('Access-Control-Allow-Origin', origin!);
        headers.set('Access-Control-Allow-Methods', methods);
        headers.set('Access-Control-Allow-Headers', ALLOWED_HEADERS.join(', '));
        headers.set('Access-Control-Max-Age', '7200');
      }
      return new Response(null, { status: 204, headers });
    }

    const res = await handler(req);
    // A Response from fetch() has immutable headers, so copy before setting.
    const headers = new Headers(res.headers);
    const vary = headers.get('Vary');
    if (!vary) headers.set('Vary', 'Origin');
    else if (!/(^|,)\s*origin\s*(,|$)/i.test(vary)) headers.set('Vary', `${vary}, Origin`);
    if (allowed) headers.set('Access-Control-Allow-Origin', origin!);
    else headers.delete('Access-Control-Allow-Origin');
    return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
  };
}
