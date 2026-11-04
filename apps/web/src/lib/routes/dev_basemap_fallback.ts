/// Dev-only: swap a map off the local Protomaps style when the viewport leaves
/// the extract it serves, and back when it returns (issue #1285). Wired by
/// `maplibre.ts` under `import.meta.env.DEV` only, so a production build never
/// reaches this module. The coverage decision is `dev_basemap_coverage.ts`.
///
/// The fallback is the keyless OSM raster style every surface already falls
/// back to without a MapTiler key, so dev gains no new tile host. The flyover
/// video export (`interactive: false`) is left alone: it renders thousands of
/// tiles, which OSM's tile policy forbids (decisions § 2270).

import type * as engine from 'maplibre-gl';
import {
	basemapIds,
	carryOverlays,
	devBasemapStyle,
	tileJsonBounds,
	unionBounds,
	type Bbox,
} from './dev_basemap_coverage';
import { OSM_FALLBACK_STYLE_URL } from './map-style-url';

type Engine = typeof engine;
type StyleDoc = engine.StyleSpecification;

const styleDocs = new Map<string, Promise<StyleDoc | null>>();
const coverages = new Map<string, Promise<Bbox | null>>();

async function fetchJson(url: string): Promise<unknown> {
	const res = await fetch(url);
	if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
	return res.json();
}

function styleDoc(url: string): Promise<StyleDoc | null> {
	let doc = styleDocs.get(url);
	if (!doc) {
		doc = fetchJson(new URL(url, location.href).href).then(
			(d) => d as StyleDoc,
			(err) => {
				console.warn('[dev-basemap] could not read style', url, err);
				return null;
			},
		);
		styleDocs.set(url, doc);
	}
	return doc;
}

/// Union of the bounds every source of the local style declares, inline or
/// in the TileJSON its `url` names. tileserver-gl publishes the PMTiles
/// extract's bounds there, so the coverage follows whichever file is mounted.
function coverage(url: string): Promise<Bbox | null> {
	let cov = coverages.get(url);
	if (!cov) {
		cov = styleDoc(url).then(async (doc) => {
			if (!doc) return null;
			const boxes = await Promise.all(
				Object.values(doc.sources).map(async (src) => {
					const inline = tileJsonBounds(src);
					if (inline) return inline;
					const tileJsonUrl = (src as { url?: unknown }).url;
					if (typeof tileJsonUrl !== 'string' || !/^https?:/.test(tileJsonUrl)) return null;
					try {
						return tileJsonBounds(await fetchJson(tileJsonUrl));
					} catch (err) {
						console.warn('[dev-basemap] could not read TileJSON', tileJsonUrl, err);
						return null;
					}
				}),
			);
			return unionBounds(boxes);
		});
		coverages.set(url, cov);
	}
	return cov;
}

interface SwapState {
	shown: string | null;
	checking: boolean;
}

/// Patches `Map.prototype.setStyle` rather than exporting a subclass, so
/// `maplibre.ts` keeps re-exporting the engine namespace every surface's
/// `maplibregl.Map` type annotation depends on. MapLibre's constructor calls
/// `setStyle` with the initial style, so the patch sees every map from birth.
export function installDevBasemapFallback(maplibre: Engine, localStyleUrl: string): void {
	if (localStyleUrl === '' || localStyleUrl === OSM_FALLBACK_STYLE_URL) return;

	const proto = maplibre.Map.prototype;
	const originalSetStyle = proto.setStyle;
	const states = new WeakMap<engine.Map, SwapState>();

	async function check(map: engine.Map, state: SwapState): Promise<void> {
		const shown = state.shown;
		if (state.checking || (shown !== localStyleUrl && shown !== OSM_FALLBACK_STYLE_URL)) return;
		state.checking = true;
		try {
			const cov = await coverage(localStyleUrl);
			const b = map.getBounds();
			const want = devBasemapStyle({
				coverage: cov,
				viewport: [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()],
				localStyleUrl,
				fallbackStyleUrl: OSM_FALLBACK_STYLE_URL,
			});
			if (want === shown) return;
			const replacedDoc = await styleDoc(shown);
			if (!replacedDoc || state.shown !== shown) return;
			console.info(
				`[dev-basemap] viewport ${want === localStyleUrl ? 'inside' : 'outside'} the local tile extract; showing ${want}`,
			);
			state.shown = want;
			const replaced = basemapIds(replacedDoc);
			originalSetStyle.call(map, want, {
				transformStyle: (prev, next) => (prev ? carryOverlays(prev, next, replaced) : next),
			});
		} finally {
			state.checking = false;
		}
	}

	proto.setStyle = function (this: engine.Map, style, options) {
		// Only a URL is a basemap choice. MapLibre itself calls setStyle with a
		// snapshot object after a WebGL context loss and with null on remove();
		// neither changes which basemap is shown.
		// `_interactive` is false on the flyover video export's offscreen map,
		// which is left alone: it renders thousands of tiles, which OSM's tile
		// policy forbids (decisions § 2270).
		if (typeof style === 'string' && this._interactive !== false) {
			let state = states.get(this);
			if (!state) {
				const created: SwapState = { shown: style, checking: false };
				states.set(this, created);
				const onSettle = () => void check(this, created);
				this.on('load', onSettle);
				this.on('moveend', onSettle);
				state = created;
			} else {
				// A surface's own style change (RunMap on a preference change)
				// must not inherit the overlay-carrying transform a swap
				// installed: MapLibre reuses the last transformStyle when a call
				// names none, and the surface re-adds its own overlays, which
				// would then collide.
				state.shown = style;
				if (!options?.transformStyle) options = { ...options, transformStyle: (_prev, next) => next };
				const current = state;
				this.once('style.load', () => void check(this, current));
			}
		}
		return originalSetStyle.call(this, style, options);
	};
}
