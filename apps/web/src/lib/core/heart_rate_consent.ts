// Heart rate is kept only with health-data consent (decisions § 2513).
//
// The database strips the heart-rate keys from a run written by a runner
// without consent, but it cannot see inside the gzipped track, and the
// storage policy refuses the heart-rate sidecar outright. So every client
// that uploads a run strips it first with `stripHeartRate`: the run, its
// distance, its time and its track are all kept; only the heart rate goes.
//
// Twin of `packages/core_models/lib/src/heart_rate_consent.dart` — keep the
// key list, the rule and the test count in lockstep. The Dart side takes a
// `Run`; this side takes the save input's three heart-rate-bearing fields,
// which is where web holds them (`saveRun`'s `metadata`, `track`, `hrSeries`).

/** The `runs.metadata` keys that are heart rate. `hr_series_url` is a
 *  column on the server; mobile carries it in the bag, so both twins list it. */
export const HEART_RATE_METADATA_KEYS = ['avg_bpm', 'max_bpm', 'hr_coverage', 'hr_series_url'] as const;

export interface HeartRateBearing {
	metadata?: Record<string, unknown> | null;
	track?: ReadonlyArray<{ bpm?: number | null; [field: string]: unknown }>;
	hrSeries?: ReadonlyArray<unknown>;
}

/** Whether the input carries any heart rate: a heart-rate metadata key, a
 *  per-point bpm, or a heart-rate series. */
export function hasHeartRate(input: HeartRateBearing): boolean {
	const meta = input.metadata;
	if (meta && HEART_RATE_METADATA_KEYS.some((k) => k in meta)) return true;
	if (input.track?.some((p) => p.bpm != null)) return true;
	return (input.hrSeries?.length ?? 0) > 0;
}

/** The input without its heart rate, or the input itself when it has none.
 *  Never mutates the input. */
export function stripHeartRate<T extends HeartRateBearing>(input: T): T {
	if (!hasHeartRate(input)) return input;
	const out = { ...input };
	if (input.metadata) {
		const meta = { ...input.metadata };
		for (const k of HEART_RATE_METADATA_KEYS) delete meta[k];
		out.metadata = meta;
	}
	if (input.track) {
		out.track = input.track.map((p) => {
			if (p.bpm == null) return p;
			const { bpm: _bpm, ...rest } = p;
			return rest;
		});
	}
	if (input.hrSeries) delete out.hrSeries;
	return out;
}

/** A gzipped stored track with every point's `bpm` removed, or `bytes`
 *  itself when no point carries one. Used where a track is uploaded as
 *  stored bytes (a backup restore). Throws on bytes that are not a gzipped
 *  JSON array, so the caller reports the track rather than storing
 *  something it could not check. */
export async function trackBytesWithoutBpm(bytes: Uint8Array): Promise<Uint8Array> {
	const text = await new Response(
		new Blob([bytes as BlobPart]).stream().pipeThrough(new DecompressionStream('gzip')),
	).text();
	const points: unknown = JSON.parse(text);
	if (!Array.isArray(points)) throw new Error('track is not a list');
	const track = points as Array<{ bpm?: number | null; [field: string]: unknown }>;
	const stripped = stripHeartRate({ track }).track;
	if (stripped === track) return bytes;
	const gz = new Response(
		new Blob([JSON.stringify(stripped)]).stream().pipeThrough(new CompressionStream('gzip')),
	);
	return new Uint8Array(await gz.arrayBuffer());
}
