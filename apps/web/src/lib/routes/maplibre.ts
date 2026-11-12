// Single entry point for maplibre-gl. Import the map engine from here,
// never straight from 'maplibre-gl', so the worker wiring below can't be
// skipped by a new call site.
//
// v6 resolves its own worker at runtime, off the module's own location:
//
//   new URL('./maplibre-gl-worker.mjs', import.meta.url)
//
// After bundling, `import.meta.url` is the emitting chunk's URL, so that
// resolves to a path inside _app/immutable/chunks/ that Vite never writes —
// the string is dynamic, so nothing marks the worker as an asset to emit.
// The worker then 404s, no tile is ever parsed, and the map sits there
// without firing `idle`: the map looks blank rather than broken. v5 never
// hit this because its UMD bundle carried the worker inline.
//
// `?worker&url` makes Vite bundle the worker as a real, self-contained
// asset (its sibling maplibre-gl-shared.mjs import gets bundled in, which a
// plain `?url` copy would leave dangling) and hands back the hashed URL.
//
// In `vite dev` only, maps pointed at the local Protomaps tileserver swap to
// the keyless fallback style while the viewport is outside the extract the
// tileserver serves (issue #1285, `dev_basemap_fallback.ts`). The import is
// dynamic and inside the `import.meta.env.DEV` branch, which a build replaces
// with `false` and removes, so no production chunk carries the module
// (`scripts/check_web_dev_only_code.mjs` asserts it on the build output). It
// is awaited at the top level so the patch is in place before any surface
// can construct a map from this module's export.
import { PUBLIC_TILE_STYLE_URL } from '$app/env/public';
import * as maplibregl from 'maplibre-gl';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
import { resolveStyleOverride } from './map-style-url';

maplibregl.setWorkerUrl(workerUrl);

if (import.meta.env.DEV) {
	const { installDevBasemapFallback } = await import('./dev_basemap_fallback');
	installDevBasemapFallback(maplibregl, resolveStyleOverride(() => PUBLIC_TILE_STYLE_URL));
}

export default maplibregl;
