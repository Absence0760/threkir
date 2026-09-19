#!/usr/bin/env node
// Synthetic probe: every API behaviour on the distribution answers
// `application/json`. It asserts the CONTENT TYPE, not the status, and that is
// the entire point.
//
// The distribution maps `403 -> 200 /200.html` for every origin at once
// (`custom_error_response` is a member of `DistributionConfig`, not of
// `CacheBehavior` — CloudFront API reference, 2020-05-31, confirmed
// 2026-09-18 — so the API behaviours cannot opt out of it natively). The
// mapping is load-bearing: the site bucket grants `s3:GetObject` with no
// `s3:ListBucket`, so every SPA deep link arrives as a 403 and must be served
// the shell. Its cost is that a 403 from ANY origin, for ANY reason, reaches
// the caller as `200 text/html`.
//
// A status-code probe cannot tell that apart from a working endpoint. It is
// not that it is hard: a masked 403 and a healthy 200 are the same integer, so
// no threshold, retry or comparison over the status can separate them. In
// September 2026 that asymmetry read as a production outage convincingly
// enough to merge a fix for a bug that did not exist (#938, reverted by #941);
// the one signal that disagreed was `content-type`, which nothing looked at.
//
// So this probe looks at exactly that. Every API Lambda in this tree answers
// every response — 401, 405, 400, 503 — with `content-type: application/json`,
// including its refusals, so an unauthenticated request is a complete test:
// JSON back means the request reached the function, HTML back means it did
// not and something upstream refused it.
//
// The behaviour list is DERIVED from infra/modules/web-stack/main.tf rather
// than spelled here, so a fourth `/api/*` behaviour is probed the day it is
// added and nobody has to remember. `--derive` runs that half alone, offline,
// and fails when it reads nothing — a parser that stops matching would
// otherwise make this probe pass while probing zero endpoints, which is a
// source-reading tool's failure mode rather than a false negative.
//
// Both methods are probed per behaviour, because the two are not equivalent:
// a POST to a Lambda Function URL behind OAC requires the VIEWER to send the
// sigv4 payload hash in `x-amz-content-sha256` ("your users must compute the
// SHA256 of the body and include the payload hash value of the request body in
// the `x-amz-content-sha256` header when sending the request to CloudFront.
// Lambda doesn't support unsigned payloads" — CloudFront developer guide,
// "Restrict access to an AWS Lambda function URL origin"). Omitting it is a
// malformed request, answered 403 and laundered to the shell, and that is what
// made the GET/POST split look like "bodies are rejected at the origin". The
// probe sends the hash, so an HTML answer here is a real finding.
//
// Run: `node scripts/probe_api_content_type.mjs --host preview.example.com`
//      `node scripts/probe_api_content_type.mjs --derive` (offline)
// Operators reach it through `bin/preview-status.sh <env>`, which passes the
// public hostname it already resolved.
// CI:  the `infra-guards` job in .github/workflows/ci.yml runs `--derive` plus
//      the suite below; the network half needs a deployed env and does not run
//      there.
// Unit tests: `node --test scripts/probe_api_content_type.test.mjs`

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { hclResources, nestedBlocks, stripComments } from './hcl_lex.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const MODULE_FILE = join(REPO_ROOT, 'infra', 'modules', 'web-stack', 'main.tf');

/// What makes a behaviour an API behaviour: it serves the JSON API rather than
/// a document. `/share/*` and `/og/*` are Lambda-backed too, but they answer
/// HTML and PNG by design, so asserting JSON on them would be asserting a
/// falsehood — their masking is the SEO problem § 1036 solved, not this one.
export const API_PATH_PREFIX = '/api/';

/// The methods worth probing, and why each. GET carries no body, so it needs
/// no payload hash and isolates "did the request reach the function"; POST is
/// the method every API surface here actually uses in production and the one
/// the payload-hash requirement applies to.
export const PROBE_METHODS = ['GET', 'POST'];

export const PROBE_BODY = JSON.stringify({ probe: 'content-type' });

/** @param {string} body @param {string} key */
function attr(body, key) {
  return body.match(new RegExp(`^\\s*${key}\\s*=\\s*(.+?)\\s*$`, 'm'))?.[1] ?? null;
}

/** @param {string | null} raw @returns {string[]} */
function stringList(raw) {
  if (raw === null) return [];
  return [...raw.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
}

/**
 * @typedef {{ pattern: string, origin: string | null, methods: string[] }} ApiBehaviour
 */

/**
 * Every `/api/*` cache behaviour the module declares.
 * Null when no `aws_cloudfront_distribution` could be read at all — the caller
 * reports that rather than treating it as "no API to probe", which is how a
 * parser that stopped matching would otherwise pass while testing nothing.
 *
 * @param {string} raw
 * @returns {ApiBehaviour[] | null}
 */
export function parseApiBehaviours(raw) {
  const src = stripComments(raw);
  const distributions = hclResources(src, 'aws_cloudfront_distribution');
  if (distributions.length === 0) return null;
  /** @type {ApiBehaviour[]} */
  const out = [];
  for (const dist of distributions) {
    for (const block of nestedBlocks(dist.body, /ordered_cache_behavior\s*\{/g)) {
      const pattern = attr(block.body, 'path_pattern')?.replace(/^"|"$/g, '') ?? null;
      if (pattern === null || !pattern.startsWith(API_PATH_PREFIX)) continue;
      out.push({
        pattern,
        origin: attr(block.body, 'target_origin_id')?.replace(/^"|"$/g, '') ?? null,
        methods: stringList(attr(block.body, 'allowed_methods')),
      });
    }
  }
  return out;
}

/**
 * The concrete path to request for a behaviour's pattern. CloudFront path
 * patterns are glob-ish; trimming the trailing wildcard gives the prefix the
 * behaviour exists to route, which is a path each handler recognises.
 *
 * @param {string} pattern
 * @returns {string}
 */
export function probePath(pattern) {
  return pattern.replace(/\*+$/, '') || '/';
}

/**
 * The requests to issue for one behaviour: the probe methods the behaviour
 * actually allows at the edge. A method CloudFront refuses never reaches the
 * origin, so probing it would assert the edge's behaviour, not the API's.
 *
 * @param {ApiBehaviour} behaviour
 * @returns {{ method: string, path: string }[]}
 */
export function plannedRequests(behaviour) {
  return PROBE_METHODS.filter((m) => behaviour.methods.includes(m)).map((method) => ({
    method,
    path: probePath(behaviour.pattern),
  }));
}

/** @param {string} body @returns {string} */
export function payloadHash(body) {
  return createHash('sha256').update(body, 'utf8').digest('hex');
}

/**
 * @param {string} host
 * @param {{ method: string, path: string }} request
 * @returns {{ url: string, init: RequestInit }}
 */
export function buildRequest(host, request) {
  /** @type {Record<string, string>} */
  const headers = { accept: 'application/json' };
  const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
  if (hasBody) {
    headers['content-type'] = 'application/json';
    // Required of the VIEWER, not of an origin request policy: CloudFront
    // signs the origin request with sigv4 and Lambda rejects an unsigned
    // payload, so without this header the Function URL 403s before the
    // function runs and the 403 mapping serves that as the SPA shell. PR #938
    // tried to forward it from the origin side; CloudFront refuses (#941).
    headers['x-amz-content-sha256'] = payloadHash(PROBE_BODY);
  }
  return {
    url: `https://${host}${request.path}`,
    init: { method: request.method, redirect: 'manual', headers, ...(hasBody ? { body: PROBE_BODY } : {}) },
  };
}

/** @param {string | null} value @returns {boolean} */
export function isJson(value) {
  return value !== null && /^application\/(problem\+)?json\b/i.test(value.trim());
}

/** @param {string | null} value @returns {boolean} */
export function isHtml(value) {
  return value !== null && /^text\/html\b/i.test(value.trim());
}

/// The one finding this probe exists to produce, in the words someone
/// debugging needs. Kept as a constant so the test asserts the message the
/// operator reads rather than a paraphrase of it.
export const MASKED_403 =
  'a masked 403. The distribution maps 403 -> 200 /200.html for EVERY origin ' +
  '(custom_error_response is per-distribution, not per-cache-behaviour), so an HTML body on ' +
  'an API path means the Function URL refused the request before the Lambda ran and the ' +
  'refusal was rewritten into the SPA shell. Check both CloudFront invoke grants on the ' +
  'function (lambda:InvokeFunctionUrl AND lambda:InvokeFunction, issue #590) and that the ' +
  'origin is AWS_IAM-authed behind its OAC. This is NOT a status-code fault — the status is ' +
  '200 and always will be.';

/**
 * @typedef {{ behaviour: ApiBehaviour, method: string, path: string,
 *             status: number | null, contentType: string | null,
 *             error: string | null }} ProbeResult
 */

/**
 * @param {ProbeResult} r
 * @returns {{ ok: boolean, message: string }}
 */
export function classify(r) {
  const where = `${r.method} ${r.path} (${r.behaviour.pattern} -> ${r.behaviour.origin})`;
  if (r.error !== null) {
    return { ok: false, message: `${where}: request failed — ${r.error}` };
  }
  if (isJson(r.contentType)) {
    return { ok: true, message: `${where}: ${r.status} ${r.contentType}` };
  }
  if (isHtml(r.contentType)) {
    return {
      ok: false,
      message: `${where}: ${r.status} ${r.contentType} — ${MASKED_403}`,
    };
  }
  return {
    ok: false,
    message:
      `${where}: ${r.status} ${r.contentType ?? '(no content-type)'} — every API handler in ` +
      'this tree answers application/json, including its refusals, so anything else came from ' +
      'somewhere other than the handler.',
  };
}

/**
 * @param {string} host
 * @param {ApiBehaviour[]} behaviours
 * @param {typeof fetch} fetchFn
 * @returns {Promise<ProbeResult[]>}
 */
export async function probe(host, behaviours, fetchFn) {
  /** @type {ProbeResult[]} */
  const out = [];
  for (const behaviour of behaviours) {
    for (const request of plannedRequests(behaviour)) {
      const { url, init } = buildRequest(host, request);
      try {
        const res = await fetchFn(url, init);
        out.push({
          behaviour,
          method: request.method,
          path: request.path,
          status: res.status,
          contentType: res.headers.get('content-type'),
          error: null,
        });
      } catch (e) {
        out.push({
          behaviour,
          method: request.method,
          path: request.path,
          status: null,
          contentType: null,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
  }
  return out;
}

/**
 * @param {ApiBehaviour[] | null} behaviours
 * @returns {string[]} the reasons the derivation cannot be probed against
 */
export function derivationErrors(behaviours) {
  if (behaviours === null) {
    return [
      'no `aws_cloudfront_distribution` found in the web-stack module — this probe read nothing, ' +
        'so it would have reported success having tested zero endpoints.',
    ];
  }
  if (behaviours.length === 0) {
    return [
      `no ordered_cache_behavior with a path_pattern under ${API_PATH_PREFIX} — either every API ` +
        'behaviour was removed from the distribution, or the parse stopped matching. Both make ' +
        'this probe vacuous.',
    ];
  }
  /** @type {string[]} */
  const errors = [];
  for (const b of behaviours) {
    if (plannedRequests(b).length === 0) {
      errors.push(
        `${b.pattern} allows none of ${PROBE_METHODS.join(', ')} at the edge (${b.methods.join(', ') || 'no allowed_methods read'}), ` +
          'so nothing about it can be probed. Teach this script the method it does allow.',
      );
    }
  }
  return errors;
}

/**
 * @param {string[]} argv
 * @returns {{ host: string | null, deriveOnly: boolean, error: string | null }}
 */
export function parseArgs(argv) {
  let host = null;
  let deriveOnly = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--derive') deriveOnly = true;
    else if (argv[i] === '--host') {
      host = argv[++i] ?? null;
      if (host === null) return { host, deriveOnly, error: '--host needs a hostname' };
    } else return { host, deriveOnly, error: `unknown argument: ${argv[i]}` };
  }
  if (host === null) deriveOnly = true;
  return { host, deriveOnly, error: null };
}

/**
 * @param {string[]} argv
 * @param {{ readModule?: () => string, fetchFn?: typeof fetch,
 *           log?: (s: string) => void, errorLog?: (s: string) => void }} [deps]
 * @returns {Promise<number>}
 */
export async function main(argv, deps = {}) {
  const readModule = deps.readModule ?? (() => readFileSync(MODULE_FILE, 'utf-8'));
  const fetchFn = deps.fetchFn ?? fetch;
  const log = deps.log ?? ((s) => console.log(s));
  const errorLog = deps.errorLog ?? ((s) => console.error(s));

  const args = parseArgs(argv);
  if (args.error !== null) {
    errorLog(`[FAIL] ${args.error}`);
    return 2;
  }

  const behaviours = parseApiBehaviours(readModule());
  const derivation = derivationErrors(behaviours);
  if (derivation.length > 0) {
    for (const line of derivation) errorLog(`[FAIL] ${line}`);
    errorLog(`\n  module: ${MODULE_FILE}\n`);
    return 1;
  }
  const derived = /** @type {ApiBehaviour[]} */ (behaviours);

  for (const b of derived) {
    log(`[DERIVED] ${b.pattern} -> ${b.origin} (probing ${plannedRequests(b).map((r) => r.method).join(', ')})`);
  }
  if (args.deriveOnly || args.host === null) {
    log(`\n${derived.length} API behaviour(s) derived; no --host given, so nothing was probed.`);
    return 0;
  }

  const results = await probe(args.host, derived, fetchFn);
  let failures = 0;
  for (const r of results) {
    const { ok, message } = classify(r);
    if (ok) log(`[OK] ${message}`);
    else {
      failures++;
      errorLog(`[FAIL] ${message}`);
    }
  }

  if (failures > 0) {
    errorLog(`\n${failures} of ${results.length} API probe(s) did not answer application/json.\n`);
    return 1;
  }
  log(`\nAll ${results.length} API probe(s) answered application/json on ${args.host}.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exit(await main(process.argv.slice(2)));
}
