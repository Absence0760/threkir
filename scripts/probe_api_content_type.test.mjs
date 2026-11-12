import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  API_PATH_PREFIX,
  MASKED_403,
  MODULE_FILE,
  PROBE_BODY,
  buildRequest,
  classify,
  derivationErrors,
  main,
  parseApiBehaviours,
  parseArgs,
  plannedRequests,
  probePath,
} from './probe_api_content_type.mjs';

// ─────────────────────────────── fixtures ───────────────────────────────

/** @param {string} blocks */
const distribution = (blocks) => `
resource "aws_cloudfront_distribution" "this" {
  enabled = true
  # A comment with an unbalanced { brace and a "/api/decoy*" in it.
  default_cache_behavior {
    target_origin_id = "s3-site"
  }
${blocks}
}
`;

/**
 * @param {string} pattern
 * @param {string} origin
 * @param {string[]} methods
 */
const behaviourBlock = (pattern, origin, methods) => `
  ordered_cache_behavior {
    path_pattern     = "${pattern}"
    target_origin_id = "${origin}"
    allowed_methods  = [${methods.map((m) => `"${m}"`).join(', ')}]
  }
`;

const ALL_METHODS = ['GET', 'HEAD', 'OPTIONS', 'PUT', 'POST', 'PATCH', 'DELETE'];

/** @param {{ status?: number, contentType?: string | null }} r */
const response = ({ status = 200, contentType = 'application/json' }) => ({
  status,
  headers: { get: (/** @type {string} */ k) => (k.toLowerCase() === 'content-type' ? contentType : null) },
});

/** @param {Record<string, { status?: number, contentType?: string | null }>} byKey */
function stubFetch(byKey) {
  /** @type {string[]} */
  const seen = [];
  /** @type {any} */
  const fn = async (/** @type {string} */ url, /** @type {RequestInit} */ init) => {
    const key = `${init.method} ${new URL(url).pathname}`;
    seen.push(key);
    return response(byKey[key] ?? {});
  };
  return { fn, seen };
}

/** @param {string[]} argv @param {any} deps */
async function run(argv, deps) {
  /** @type {string[]} */
  const out = [];
  /** @type {string[]} */
  const err = [];
  const code = await main(argv, { ...deps, log: (s) => out.push(s), errorLog: (s) => err.push(s) });
  return { code, out: out.join('\n'), err: err.join('\n') };
}

// ─────────────────────────── the live derivation ───────────────────────────

test('derives the API behaviours from the real web-stack module', () => {
  const behaviours = parseApiBehaviours(readFileSync(MODULE_FILE, 'utf-8'));
  assert.notEqual(behaviours, null, 'the module must yield a distribution');
  const patterns = /** @type {NonNullable<typeof behaviours>} */ (behaviours).map((b) => b.pattern);
  assert.ok(patterns.length > 0, 'the distribution must declare at least one /api/ behaviour');
  assert.ok(
    patterns.includes('/api/coach*'),
    `/api/coach* is the behaviour the masking was measured on; derived ${patterns.join(', ')}`,
  );
  assert.ok(
    patterns.every((p) => p.startsWith(API_PATH_PREFIX)),
    'only /api/ behaviours belong here — /share/* and /og/* answer HTML and PNG by design',
  );
});

test('every derived API behaviour on the real module is probeable', () => {
  const behaviours = parseApiBehaviours(readFileSync(MODULE_FILE, 'utf-8'));
  assert.deepEqual(derivationErrors(behaviours), []);
});

// ───────────────────────────────── parsing ─────────────────────────────────

test('reads pattern, origin and allowed methods off each behaviour', () => {
  const behaviours = parseApiBehaviours(
    distribution(behaviourBlock('/api/coach*', 'lambda-coach', ALL_METHODS)),
  );
  assert.deepEqual(behaviours, [
    { pattern: '/api/coach*', origin: 'lambda-coach', methods: ALL_METHODS },
  ]);
});

test('ignores behaviours that are not under /api/', () => {
  const behaviours = parseApiBehaviours(
    distribution(
      behaviourBlock('/share/run/*', 'lambda-share-run', ['GET', 'HEAD', 'OPTIONS']) +
        behaviourBlock('/og/run/*', 'lambda-share-run', ['GET', 'HEAD', 'OPTIONS']) +
        behaviourBlock('/api/routes/osrm*', 'lambda-osrm-proxy', ALL_METHODS),
    ),
  );
  assert.deepEqual(
    behaviours?.map((b) => b.pattern),
    ['/api/routes/osrm*'],
  );
});

test('distinguishes "no distribution" from "no API behaviours"', () => {
  assert.equal(parseApiBehaviours('resource "aws_s3_bucket" "site" {}'), null);
  assert.deepEqual(parseApiBehaviours(distribution('')), []);
});

test('probePath drops the trailing wildcard', () => {
  assert.equal(probePath('/api/coach*'), '/api/coach');
  assert.equal(probePath('/api/routes/generate*'), '/api/routes/generate');
  assert.equal(probePath('/api/routes/osrm'), '/api/routes/osrm');
});

test('plans only the methods the edge allows through', () => {
  assert.deepEqual(
    plannedRequests({ pattern: '/api/x*', origin: 'lambda-x', methods: ['GET', 'HEAD'] }).map(
      (r) => r.method,
    ),
    ['GET'],
  );
});

// ──────────────────────────── derivation errors ────────────────────────────

test('a module that yields no distribution is a failure, not an empty pass', () => {
  const [message] = derivationErrors(null);
  assert.match(message, /read nothing/);
  assert.match(message, /zero endpoints/);
});

test('an API behaviour allowing neither GET nor POST is reported, not skipped', () => {
  const [message] = derivationErrors([
    { pattern: '/api/weird*', origin: 'lambda-weird', methods: ['OPTIONS'] },
  ]);
  assert.match(message, /\/api\/weird\*/);
  assert.match(message, /nothing about it can be probed/);
});

// ──────────────────────────── request construction ────────────────────────────

test('a POST carries the sigv4 payload hash of its own body', () => {
  const { url, init } = buildRequest('example.test', { method: 'POST', path: '/api/coach' });
  assert.equal(url, 'https://example.test/api/coach');
  const headers = /** @type {Record<string, string>} */ (init.headers);
  assert.equal(
    headers['x-amz-content-sha256'],
    createHash('sha256').update(PROBE_BODY, 'utf8').digest('hex'),
  );
  assert.equal(init.body, PROBE_BODY);
});

test('a GET carries no body and no payload hash', () => {
  const { init } = buildRequest('example.test', { method: 'GET', path: '/api/coach' });
  const headers = /** @type {Record<string, string>} */ (init.headers);
  assert.equal(init.body, undefined);
  assert.equal(headers['x-amz-content-sha256'], undefined);
});

// ────────────────────────────── classification ──────────────────────────────

const BEHAVIOUR = { pattern: '/api/coach*', origin: 'lambda-coach', methods: ALL_METHODS };

/** @param {{ status?: number | null, contentType?: string | null, error?: string | null }} r */
const result = (r) => ({
  behaviour: BEHAVIOUR,
  method: 'POST',
  path: '/api/coach',
  status: r.status ?? 200,
  contentType: r.contentType ?? null,
  error: r.error ?? null,
});

test('a JSON answer passes whatever the status says', () => {
  for (const status of [200, 401, 405, 503]) {
    assert.equal(classify(result({ status, contentType: 'application/json' })).ok, true);
  }
});

test('200 text/html on an API path FAILS, naming the masked 403', () => {
  const { ok, message } = classify(
    result({ status: 200, contentType: 'text/html; charset=utf-8' }),
  );
  assert.equal(ok, false, 'a 200 that a status probe calls healthy must fail this one');
  assert.ok(message.includes(MASKED_403), message);
  assert.match(message, /403 -> 200 \/200\.html/);
  assert.match(message, /issue #590/);
  assert.match(message, /NOT a status-code fault/);
});

test('a content type that is neither JSON nor HTML fails on its own terms', () => {
  const { ok, message } = classify(result({ status: 200, contentType: 'image/png' }));
  assert.equal(ok, false);
  assert.ok(!message.includes(MASKED_403), 'only HTML earns the masked-403 diagnosis');
  assert.match(message, /every API handler in this tree answers application\/json/);
});

test('a missing content type fails rather than passing by absence', () => {
  const { ok, message } = classify(result({ status: 200, contentType: null }));
  assert.equal(ok, false);
  assert.match(message, /\(no content-type\)/);
});

test('a transport failure is reported as such', () => {
  const { ok, message } = classify(result({ status: null, error: 'getaddrinfo ENOTFOUND' }));
  assert.equal(ok, false);
  assert.match(message, /request failed — getaddrinfo ENOTFOUND/);
});

// ───────────────────────────────── end to end ─────────────────────────────────

const MODULE_FIXTURE = distribution(
  behaviourBlock('/api/coach*', 'lambda-coach', ALL_METHODS) +
    behaviourBlock('/api/routes/generate*', 'lambda-generate-route', ALL_METHODS),
);

test('probes every derived behaviour on both methods and passes when all answer JSON', async () => {
  const { fn, seen } = stubFetch({});
  const { code, out } = await run(['--host', 'example.test'], {
    readModule: () => MODULE_FIXTURE,
    fetchFn: fn,
  });
  assert.equal(code, 0, out);
  assert.deepEqual(seen, [
    'GET /api/coach',
    'POST /api/coach',
    'GET /api/routes/generate',
    'POST /api/routes/generate',
  ]);
  assert.match(out, /All 4 API probe\(s\) answered application\/json/);
});

test('one masked 403 among four healthy answers fails the whole probe', async () => {
  const { fn } = stubFetch({
    'POST /api/coach': { status: 200, contentType: 'text/html; charset=utf-8' },
  });
  const { code, err } = await run(['--host', 'example.test'], {
    readModule: () => MODULE_FIXTURE,
    fetchFn: fn,
  });
  assert.equal(code, 1);
  assert.match(err, /POST \/api\/coach/);
  assert.ok(err.includes(MASKED_403), err);
  assert.match(err, /1 of 4 API probe\(s\)/);
});

test('--derive reads the module and probes nothing', async () => {
  let fetched = false;
  const { code, out } = await run(['--derive'], {
    readModule: () => MODULE_FIXTURE,
    fetchFn: async () => {
      fetched = true;
      return response({});
    },
  });
  assert.equal(code, 0, out);
  assert.equal(fetched, false);
  assert.match(out, /2 API behaviour\(s\) derived/);
});

test('--derive fails when the module yields nothing to probe', async () => {
  const { code, err } = await run(['--derive'], {
    readModule: () => 'resource "aws_s3_bucket" "site" {}',
  });
  assert.equal(code, 1);
  assert.match(err, /read nothing/);
});

test('an unknown argument is refused rather than ignored', async () => {
  const { code, err } = await run(['--hosts', 'example.test'], {
    readModule: () => MODULE_FIXTURE,
  });
  assert.equal(code, 2);
  assert.match(err, /unknown argument: --hosts/);
});

test('parseArgs falls back to derive-only when no host is given', () => {
  assert.deepEqual(parseArgs([]), { host: null, deriveOnly: true, error: null });
  assert.deepEqual(parseArgs(['--host', 'a.test']), {
    host: 'a.test',
    deriveOnly: false,
    error: null,
  });
});
