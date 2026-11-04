/// Pure half of the dev-only basemap coverage fallback (issue #1285). A local
/// Protomaps extract covers one region; a map pointed at a course outside it
/// renders an empty ground. These helpers decide, from the bounds the local
/// tileserver publishes in its TileJSON, whether a viewport is covered — the
/// MapLibre glue that acts on the answer is `dev_basemap_fallback.ts`, which
/// `maplibre.ts` only wires under `import.meta.env.DEV`.

/// `[west, south, east, north]` in degrees, the TileJSON `bounds` order.
export type Bbox = [number, number, number, number];

/// The `bounds` a TileJSON (or an inline style source) declares, or null when
/// it declares none or a malformed one. Null means "coverage unknown", which
/// [viewportCovered] treats as covered: a tileserver that does not say where
/// its data is gets the benefit of the doubt rather than a style swap.
export function tileJsonBounds(doc: unknown): Bbox | null {
	if (doc == null || typeof doc !== 'object') return null;
	const raw = (doc as { bounds?: unknown }).bounds;
	if (!Array.isArray(raw) || raw.length !== 4) return null;
	if (!raw.every((v) => typeof v === 'number' && Number.isFinite(v))) return null;
	const [w, s, e, n] = raw as Bbox;
	if (s > n || w > e) return null;
	return [w, s, e, n];
}

/// The smallest box holding every source's bounds, or null when none declared
/// any. A style with several vector sources is covered wherever any of them is
/// — approximated by their union, which is exact for the one-source style
/// `bin/protomaps-dev.sh` writes.
export function unionBounds(boxes: readonly (Bbox | null)[]): Bbox | null {
	const known = boxes.filter((b): b is Bbox => b !== null);
	if (known.length === 0) return null;
	return [
		Math.min(...known.map((b) => b[0])),
		Math.min(...known.map((b) => b[1])),
		Math.max(...known.map((b) => b[2])),
		Math.max(...known.map((b) => b[3])),
	];
}

/// Whether [viewport] lies entirely inside [coverage]. A viewport that only
/// straddles the edge counts as NOT covered: half a blank map is the defect
/// being fixed, not a reason to keep the local style.
///
/// MapLibre reports a world-copied viewport with longitudes outside ±180, so
/// the viewport is shifted back by whole turns before comparing. One that
/// still crosses the antimeridian, or is wider than the world, is covered
/// only by a coverage spanning every longitude.
export function viewportCovered(coverage: Bbox | null, viewport: Bbox): boolean {
	if (coverage === null) return true;
	let [w, s, e, n] = viewport;
	const [cw, cs, ce, cn] = coverage;
	const fullLongitude = cw <= -180 && ce >= 180;
	if (e - w >= 360) return fullLongitude && s >= cs && n <= cn;
	const turns = Math.floor((w + 180) / 360);
	w -= turns * 360;
	e -= turns * 360;
	if (e > 180) return fullLongitude && s >= cs && n <= cn;
	return w >= cw && e <= ce && s >= cs && n <= cn;
}

/// The style a dev map should show: the local one when it covers the
/// viewport, the keyless fallback otherwise.
export function devBasemapStyle(opts: {
	coverage: Bbox | null;
	viewport: Bbox;
	localStyleUrl: string;
	fallbackStyleUrl: string;
}): string {
	return viewportCovered(opts.coverage, opts.viewport) ? opts.localStyleUrl : opts.fallbackStyleUrl;
}

/// The source and layer ids a basemap style document declares — what a swap
/// replaces. Everything else on the map is an overlay a surface added.
export interface BasemapIds {
	sources: ReadonlySet<string>;
	layers: ReadonlySet<string>;
}

interface StyleLike {
	sources?: Record<string, unknown>;
	layers?: readonly { id: string }[];
	glyphs?: unknown;
	sprite?: unknown;
	terrain?: unknown;
	sky?: unknown;
	projection?: unknown;
}

export function basemapIds(doc: StyleLike): BasemapIds {
	return {
		sources: new Set(Object.keys(doc.sources ?? {})),
		layers: new Set((doc.layers ?? []).map((l) => l.id)),
	};
}

/// The style a swap commits: [next]'s basemap with every overlay source and
/// layer [previous] carried on top, plus the terrain / sky / projection a
/// surface set on the map. Without this the swap would drop the course line,
/// markers and terrain the surface drew, and only some surfaces re-add theirs
/// after a style change.
///
/// Glyphs and sprite fall back to [previous]'s when [next] declares none, so
/// an overlay symbol layer keeps the font it was drawn with.
export function carryOverlays<N extends StyleLike>(previous: StyleLike, next: N, replaced: BasemapIds): N {
	const overlaySources = Object.fromEntries(
		Object.entries(previous.sources ?? {}).filter(([id]) => !replaced.sources.has(id)),
	);
	const overlayLayers = (previous.layers ?? []).filter((l) => !replaced.layers.has(l.id));
	const out: N = {
		...next,
		sources: { ...next.sources, ...overlaySources },
		layers: [...(next.layers ?? []), ...overlayLayers],
	};
	const carried: StyleLike = out;
	for (const key of ['terrain', 'sky', 'projection'] as const) {
		if (previous[key] !== undefined) carried[key] = previous[key];
	}
	// Spelled out rather than looped over a key list: the quoted key is an
	// icon ligature to the font subsetter, which would ship a glyph nothing draws.
	if (next.glyphs === undefined && previous.glyphs !== undefined) carried.glyphs = previous.glyphs;
	if (next.sprite === undefined && previous.sprite !== undefined) carried.sprite = previous.sprite;
	return out;
}
