/// Run with `cd apps/backend && deno test --no-check --allow-read supabase/functions/_shared/cors_wiring.test.ts`.
///
/// Source guard for decisions § 2121. Every Edge Function the web app
/// fetches from the browser is cross-origin and preflighted, and none of
/// that is visible locally or in the e2e lanes (see the backend CLAUDE.md
/// gotcha), so the set is derived from the call sites in apps/web/src and
/// each one's index.ts must hand its handler to withCors outermost. The
/// converse is pinned too: a webhook, cron sweep or auth hook has no browser
/// caller, and CORS on it would only widen who may read its answers.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const FUNCTIONS_DIR = new URL('../', import.meta.url);
const WEB_SRC = new URL('../../../../web/src/', import.meta.url);

/// Matched by the call-site scan but never fetch()ed by a browser.
const EXEMPT: Record<string, string> = {
  'plan-calendar':
    'the URL is handed to a calendar app as a subscription (webcal://); the browser navigates to it at most, which is not a CORS request',
};

const SERVER_ONLY = /(^|\/)(\+[a-z.]*server\.ts|hooks\.server\.ts|server\/)/;

function walk(dir: URL, rel: string, out: string[]) {
  for (const e of Deno.readDirSync(dir)) {
    const r = `${rel}${e.name}`;
    if (e.isDirectory) walk(new URL(`${e.name}/`, dir), `${r}/`, out);
    else if (/\.(ts|svelte)$/.test(e.name) && !/\.(test|spec)\.ts$/.test(e.name) && !SERVER_ONLY.test(r)) {
      out.push(r);
    }
  }
}

function browserCalledFunctions(): Set<string> {
  const files: string[] = [];
  walk(WEB_SRC, '', files);
  const found = new Set<string>();
  const patterns = [
    /functions\.invoke\(\s*['"`]([a-z0-9-]+)['"`]/g,
    /functions\/v1\/([a-z0-9-]+)/g,
  ];
  for (const f of files) {
    const src = Deno.readTextFileSync(new URL(f, WEB_SRC));
    for (const p of patterns) for (const m of src.matchAll(p)) found.add(m[1]);
  }
  return found;
}

function functionDirs(): string[] {
  const out: string[] = [];
  for (const e of Deno.readDirSync(FUNCTIONS_DIR)) {
    if (!e.isDirectory || e.name.startsWith('_')) continue;
    try {
      Deno.statSync(new URL(`${e.name}/index.ts`, FUNCTIONS_DIR));
      out.push(e.name);
    } catch {
      // not a function
    }
  }
  return out.sort();
}

const indexSrc = (fn: string) => Deno.readTextFileSync(new URL(`${fn}/index.ts`, FUNCTIONS_DIR));

const called = browserCalledFunctions();
const browser = [...called].filter((f) => !(f in EXEMPT)).sort();

Deno.test('the call-site scan still finds the browser callers it was written against', () => {
  // Reason: a scan that silently matches nothing would pass every case below.
  for (const fn of ['delete-account', 'parkrun-import', 'export-data', 'clip-public-track']) {
    assert(browser.includes(fn), `call-site scan no longer finds ${fn}; fix the scan, not the list`);
  }
});

Deno.test('every browser-called function exists and routes through withCors outermost', () => {
  const dirs = functionDirs();
  for (const fn of browser) {
    assert(dirs.includes(fn), `apps/web/src calls ${fn}, which has no supabase/functions/${fn}/index.ts`);
    const src = indexSrc(fn);
    assert(
      /from '\.\.\/_shared\/cors\.ts'/.test(src) && /Deno\.serve\(\s*withCors\(/.test(src),
      `${fn} is fetched from the browser but its index.ts does not serve through withCors(...) outermost; ` +
        'the preflight will 405/401 and the browser will report "Failed to fetch"',
    );
  }
});

Deno.test('no function without a browser caller serves CORS', () => {
  const withCorsFns = functionDirs().filter((fn) => /from '\.\.\/_shared\/cors\.ts'/.test(indexSrc(fn)));
  assertEquals(
    withCorsFns,
    browser,
    'CORS is on a function apps/web/src does not fetch (or off one it does); server-to-server functions stay CORS-free',
  );
});

Deno.test('every exemption is still a live call site', () => {
  for (const fn of Object.keys(EXEMPT)) {
    assert(called.has(fn), `${fn} is exempt but apps/web/src no longer references it; drop the exemption`);
  }
});
