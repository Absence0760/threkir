import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { gunzipCapped, InflateLimitError, MAX_TRACK_INFLATED_BYTES } from './gunzip_capped.ts';

async function gzip(bytes: Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const cs = new (globalThis as { CompressionStream: typeof CompressionStream })
    .CompressionStream('gzip');
  const stream = new Response(bytes).body!.pipeThrough(cs);
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

Deno.test('gunzipCapped — round-trips a payload under the cap byte for byte', async () => {
  const text = JSON.stringify([{ lat: 51.5, lng: -0.1, t: 0 }, { lat: 51.51, lng: -0.11, t: 1 }]);
  const out = await gunzipCapped(await gzip(new TextEncoder().encode(text)), 1024);
  assertEquals(new TextDecoder().decode(out), text);
});

Deno.test('gunzipCapped — an output of exactly the cap is accepted, one byte more is refused', async () => {
  const cap = 4096;
  const exact = await gunzipCapped(await gzip(new Uint8Array(cap).fill(0x20)), cap);
  assertEquals(exact.byteLength, cap);
  await assertRejects(
    async () => { await gunzipCapped(await gzip(new Uint8Array(cap + 1).fill(0x20)), cap); },
    InflateLimitError,
  );
});

// The threat the compressed cap cannot see: a few KB that inflate past the
// isolate's heap. 24 MiB of one byte gzips to roughly 24 KB, comfortably under
// the 5 MB compressed cap both readers apply.
Deno.test('gunzipCapped — a small gzip bomb is refused at the default cap', async () => {
  const bomb = await gzip(new Uint8Array(24 * 1024 * 1024).fill(0x20));
  assert(bomb.byteLength < 5 * 1024 * 1024, 'the bomb passes the compressed cap');
  await assertRejects(() => gunzipCapped(bomb), InflateLimitError);
  assert(MAX_TRACK_INFLATED_BYTES < 24 * 1024 * 1024);
});

Deno.test('gunzipCapped — bytes that are not gzip reject with the decompressor error, not the cap', async () => {
  const err = await gunzipCapped(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8])).then(
    () => null,
    (e: unknown) => e,
  );
  assert(err !== null, 'not gzip must reject');
  assert(!(err instanceof InflateLimitError), 'and must not read as an oversize track');
});
