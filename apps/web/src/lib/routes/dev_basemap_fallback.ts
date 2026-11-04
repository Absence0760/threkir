/// Dev-only: swap a map off the local Protomaps style when the viewport leaves
/// the extract it serves, and back when it returns (issue #1285). `maplibre.ts`
/// imports this module dynamically inside an `import.meta.env.DEV` branch,
/// which a production build removes, so no chunk carries it;
/// `scripts/check_web_dev_only_code.mjs` fails `build-web` if one ever does,
/// by finding the `[dev-basemap]` log prefix in the client output. The
/// coverage decision is `dev_basemap_coverage.ts`.
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
	/// A settle arrived while a check was running. The running check read the
	/// viewport before it moved, so it runs once more when it finishes.
	dirty: boolean;
}

/// What an install leaves on the engine's `Map.prototype`: the setStyle it
/// wrapped, and the check every map's listeners call. A second install (a
/// `vite dev` hot update re-running `maplibre.ts`) wraps that same original
/// rather than the previous wrapper, and existing maps' listeners reach the
/// new check through it, so neither the wrapper nor the listeners stack.
interface Installed {
	originalSetStyle: engine.Map['setStyle'];
	check: (map: engine.Map, state: SwapState) => Promise<void>;
}

const INSTALLED = Symbol.for('threkir.devBasemapFallback.installed');
const MAP_STATE = Symbol.for('threkir.devBasemapFallback.state');

type Stamped<T> = T & { [INSTALLED]?: Installed; [MAP_STATE]?: SwapState };

/// Patches `Map.prototype.setStyle` rather than exporting a subclass, so
/// `maplibre.ts` keeps re-exporting the engine namespace every surface's
/// `maplibregl.Map` type annotation depends on. MapLibre's constructor calls
/// `setStyle` with the initial style, so the patch sees every map from birth.
/// Idempotent: installing again replaces the previous install.
export function installDevBasemapFallback(maplibre: Engine, localStyleUrl: string): void {
	const proto = maplibre.Map.prototype as Stamped<engine.Map>;
	const previous = proto[INSTALLED];
	if (previous) {
		proto.setStyle = previous.originalSetStyle;
		delete proto[INSTALLED];
	}
	if (localStyleUrl === '' || localStyleUrl === OSM_FALLBACK_STYLE_URL) return;

	const originalSetStyle = proto.setStyle;

	async function check(map: engine.Map, state: SwapState): Promise<void> {
		const shown = state.shown;
		if (shown !== localStyleUrl && shown !== OSM_FALLBACK_STYLE_URL) return;
		if (state.checking) {
			state.dirty = true;
			return;
		}
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
			if (state.dirty) {
				state.dirty = false;
				void check(map, state);
			}
		}
	}

	proto[INSTALLED] = { originalSetStyle, check };

	proto.setStyle = function (this: Stamped<engine.Map>, style, options) {
		// Only a URL is a basemap choice. MapLibre itself calls setStyle with a
		// snapshot object after a WebGL context loss and with null on remove();
		// neither changes which basemap is shown.
		// `_interactive` is false on the flyover video export's offscreen map,
		// which is left alone: it renders thousands of tiles, which OSM's tile
		// policy forbids (decisions § 2270).
		if (typeof style === 'string' && this._interactive !== false) {
			const settle = () => {
				const current = this[MAP_STATE];
				const installed = this[INSTALLED];
				if (current && installed) void installed.check(this, current);
			};
			let state = this[MAP_STATE];
			if (!state) {
				state = { shown: style, checking: false, dirty: false };
				this[MAP_STATE] = state;
				this.on('load', settle);
				this.on('moveend', settle);
			} else {
				// A surface's own style change (RunMap on a preference change)
				// must not inherit the overlay-carrying transform a swap
				// installed: MapLibre reuses the last transformStyle when a call
				// names none, and the surface re-adds its own overlays, which
				// would then collide.
				state.shown = style;
				if (!options?.transformStyle) options = { ...options, transformStyle: (_prev, next) => next };
				this.once('style.load', settle);
			}
		}
		return originalSetStyle.call(this, style, options);
	};
}
