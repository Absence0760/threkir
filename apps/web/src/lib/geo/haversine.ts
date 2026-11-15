// Great-circle distance, kept in a module of its own so a caller that needs
// only this does not import run_stats.ts and, with it, module-level state the
// caller never reads. The Edge Function's segment matcher is bundled from the
// web tree (scripts/gen_edge_segment_matcher.mjs), and esbuild keeps every
// computed top-level constant of a module it includes, so importing this from
// run_stats.ts shipped the still-window constants as dead code. run_stats.ts
// re-exports it, and the parity contract stays on the `run_stats` pair's row,
// which names this file as where its `haversineMetres` is defined.

/**
 * Great-circle metres between two points. Exported so the `run_stats` pair's
 * contract on `haversineMetres` can be pinned on both sides — it was private,
 * which is why a divergence in it went unnoticed.
 */
export function haversineMetres(
	lat1: number,
	lng1: number,
	lat2: number,
	lng2: number
): number {
	const r = 6371000;
	const dLat = ((lat2 - lat1) * Math.PI) / 180;
	const dLng = ((lng2 - lng1) * Math.PI) / 180;
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const a =
		sinLat * sinLat +
		Math.cos((lat1 * Math.PI) / 180) *
			Math.cos((lat2 * Math.PI) / 180) *
			sinLng *
			sinLng;
	// Clamp before the arc. Rounding can push `a` a hair above 1 for a
	// near-antipodal pair, and then `Math.sqrt(1 - a)` is NaN — which propagates
	// silently through every consumer (moving time, splits, segment distances)
	// rather than throwing. The Dart twin clamps identically; an earlier pass
	// fixed only that side on the false belief that this one already did, which
	// left the pair divergent with the NaN moved here. Measured on
	// (-87.5, 0, 87.5, 180): unclamped NaN, clamped 20015086.796.
	const clamped = a > 1 ? 1 : a < 0 ? 0 : a;
	return r * 2 * Math.asin(Math.sqrt(clamped));
}
