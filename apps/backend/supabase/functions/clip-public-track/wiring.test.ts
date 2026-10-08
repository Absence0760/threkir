/// The privacy boundary this function exists to be, read off its source.
///
/// `clip-public-track` is the only anon-reachable path to another runner's
/// GPS trace, and it had no test file of its own: `verify_jwt_config.test.ts`
/// pins its `verify_jwt = false` posture, `param_validation_wiring.test.ts`
/// pins that the uuid gate precedes the IP bucket, and
/// `offline_worker_boot_guard.test.ts` pins its import specifier. None of
/// them reaches the thing that matters — WHOSE privacy zones the track is
/// clipped against.
///
/// The handler is a bare `Deno.serve` with no exports, so these are source
/// greps in the `delete-account/wiring.test.ts` idiom. Every negative is
/// paired with the positive it depends on, so an emptied file satisfies
/// neither.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/clip-public-track/wiring.test.ts`.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the clip is taken against the OWNER, never the viewer', () => {
  // `clip_track_for_user` redacts the points that fall inside a given user's
  // privacy zones. Passing the caller would clip a stranger's track against
  // the stranger's own zones — i.e. not at all — and publish the owner's
  // home. It is one identifier's difference and produces no error.
  const call = SRC.match(/clip_track_for_user',\s*\{\s*target_user_id:\s*([A-Za-z0-9_]+)/);
  assert(call, 'the clip RPC call is gone — has the redaction moved?');
  assert(
    call[1] === 'ownerId',
    `the clip must target the run's owner, got: ${call[1]}`,
  );
  assert(
    /const ownerId = run\.user_id;/.test(SRC),
    'ownerId must come from the row, not from the request',
  );
});

Deno.test('a row whose owner cannot be resolved is refused, not served', () => {
  // `public_runs` is a view, so Postgres cannot carry `runs.user_id`'s NOT
  // NULL through it and the generated type is nullable. A null owner would
  // build the Storage path `null/<id>.json.gz` and would reach the clip RPC
  // with no owner to redact against.
  assert(
    /if \(runErr \|\| !run \|\| run\.user_id === null\) \{/.test(SRC),
    'the row read must fail closed on a null owner',
  );
  const idx = SRC.indexOf('run.user_id === null');
  assert(idx !== -1);
  assert(
    idx < SRC.indexOf('const trackPath ='),
    'the null-owner refusal must precede the Storage path derivation',
  );
});

Deno.test('the owner bypass demands an identified caller', () => {
  // `callerId` is `string | null`. A future refactor normalising it to `''`
  // or a sentinel would make an anon caller compare equal to nothing, but the
  // explicit null test is what keeps that from ever reading as ownership.
  assert(
    /const isOwnerBypass = callerId !== null && callerId === ownerId;/.test(SRC),
    'the visibility bypass must require a non-null caller AND an owner match',
  );
  assert(
    /if \(!run\.is_public && !isOwnerBypass\) \{/.test(SRC),
    'a non-public row must be refused to everyone but its owner',
  );
});

Deno.test('the anon bucket is IP-derived and spent through the service role', () => {
  // The user-context guard from 20260616_001 rejects a rate-limit key that
  // does not match `auth.uid()`, and a synthetic IP-derived key never does —
  // so the anon branch must use the admin client or the only IP-level guard
  // on the abuse surface returns an error on every call.
  const anon = SRC.slice(SRC.indexOf('const anonKey = await ipBucketKey(req);'));
  assert(anon.length > 0, 'the anon rate-limit branch is gone');
  const call = anon.match(/checkRateLimit\(\s*([A-Za-z0-9_]+),/);
  assert(call, 'the anon branch no longer rate-limits');
  assert(call[1] === 'adminClient', `the anon bucket must be spent as the service role, got: ${call[1]}`);
  assert(
    /'clip-public-track:anon'[\s\S]{0,80}failClosed: true/.test(anon),
    'the anon bucket must fail closed — it is the abuse surface',
  );
});

Deno.test('an unreadable stored track answers 502, and the refusal is reachable', () => {
  // `DecompressionStream` on a non-gzip blob and `JSON.parse` on non-JSON
  // both throw. Thrown past the handler they became a 500 from withSentry,
  // which paged Sentry and made the `!Array.isArray` refusal below them dead
  // code for exactly the input it names.
  const decode = SRC.indexOf('trackBytes = await gunzip(gz);');
  assert(decode !== -1, 'the track decode is gone');
  assert(
    /async function gunzip\([\s\S]*?DecompressionStream\('gzip'\)/.test(SRC),
    'gunzip must still be the DecompressionStream inflate',
  );
  const tryAt = SRC.lastIndexOf('try {', decode);
  const catchAt = SRC.indexOf('} catch', decode);
  assert(tryAt !== -1 && catchAt !== -1 && tryAt < decode && catchAt > decode,
    'the decompress + parse must sit inside a try/catch');
  const arm = SRC.slice(catchAt, catchAt + 200);
  assert(
    /status: 502/.test(arm) && /'malformed track'/.test(arm),
    'the decode failure must answer 502 malformed track, not fall through to a 500',
  );
  assert(
    SRC.includes('if (!Array.isArray(points))'),
    'the array refusal must survive as the second half of the same gate',
  );
});

Deno.test('both amplification bounds are still in place, on the right quantities', () => {
  // The gzipped blob is capped before inflation and the inflated point count
  // is capped before the clip walk. They bound different quantities: dropping
  // either leaves the other unable to see the attack it covers.
  assert(
    /if \(gz\.byteLength > 5 \* 1024 \* 1024\) \{/.test(SRC),
    'the compressed blob must be capped before it is inflated',
  );
  assert(
    /if \(points\.length > 50_000\) \{/.test(SRC),
    'the inflated point count must be capped before the clip walk',
  );
  const gzCap = SRC.indexOf('gz.byteLength > 5 * 1024 * 1024');
  assert(gzCap < SRC.indexOf('trackBytes = await gunzip(gz);'), 'the size cap must precede inflation');
});

Deno.test('the smoothed sidecar is merged before the owner return AND before the clip', () => {
  // The job_worker's sidecar ({owner}/{run}.smoothed.json.gz) carries the
  // smoothed position a viewer's map draws for a watch or recomputed run.
  // Merged after the clip, a fix just outside a zone whose smoothed position
  // sits inside it would survive at either end of the line — the coordinate
  // decisions §33 withholds. Merged before, clip_track_for_user's
  // either-pair-in-zone rule (20270719000005) trims it.
  const merge = SRC.indexOf('const served = needsSmoothedSidecar(points)');
  assert(merge !== -1, 'the sidecar merge is gone');
  assert(merge < SRC.indexOf('if (callerId === ownerId) {'), 'the merge must precede the owner return');
  assert(merge < SRC.indexOf("'clip_track_for_user'"), 'the merge must precede the clip');
  assert(
    /\{ target_user_id: ownerId, points: served \}/.test(SRC),
    'the clip must receive the merged points',
  );
  assert(/return Response\.json\(\{ points: served \}\)/.test(SRC), 'the owner must receive the merged points');
  assert(
    /adminClient\.storage\s*\.from\('runs'\)\s*\.download\(smoothedSidecarPath\(ownerId, runId\)\)/.test(SRC),
    "the sidecar is the OWNER's, read by the service role (the caller may not be able to read it)",
  );
  assert(
    /scGz\.byteLength > 5 \* 1024 \* 1024/.test(SRC),
    'the sidecar blob is capped before inflation, like the track',
  );
  assert(
    /sha256: await sha256Hex\(trackBytes\)/.test(SRC),
    'the sidecar must be checked against the bytes of the track it is merged onto',
  );
});
