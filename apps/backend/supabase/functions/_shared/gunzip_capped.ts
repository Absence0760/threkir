/// Bounded gunzip for the gzipped JSON tracks the Edge Functions read out of
/// the `runs` bucket.
///
/// Capping the COMPRESSED size (5 MB in clip-public-track and export-data)
/// does not bound memory: gzip deflates a run of one byte about 1000:1, so a
/// 5 MB object a runner uploads as their own track inflates to ~5 GB before
/// `JSON.parse` — or the point-count cap behind it — ever sees it, and the
/// isolate (≈250 MB heap) dies first. clip-public-track serves any public run
/// to an anonymous caller, so one planted object is a repeatable crash. This
/// reads the inflated stream chunk by chunk and stops the moment it passes
/// the cap.

/// Ceiling on a track's inflated JSON. Both readers cap the point count at
/// 50,000 and a point serialises to well under 200 bytes, so a real track
/// tops out near 10 MB; 16 MiB leaves headroom without letting JSON.parse
/// build a heap-sized object graph.
export const MAX_TRACK_INFLATED_BYTES = 16 * 1024 * 1024;

export class InflateLimitError extends Error {
  constructor() {
    super('inflated size over the cap');
    this.name = 'InflateLimitError';
  }
}

/// Inflate `gz`, throwing `InflateLimitError` as soon as the output passes
/// `maxBytes` (an output of exactly `maxBytes` is accepted). A blob that is
/// not gzip rejects with the decompressor's own error.
export async function gunzipCapped(
  gz: Uint8Array<ArrayBuffer>,
  maxBytes: number = MAX_TRACK_INFLATED_BYTES,
): Promise<Uint8Array<ArrayBuffer>> {
  const ds = new (globalThis as { DecompressionStream: typeof DecompressionStream })
    .DecompressionStream('gzip');
  const reader = new Response(gz).body!.pipeThrough(ds).getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => {});
      throw new InflateLimitError();
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.byteLength;
  }
  return out;
}
