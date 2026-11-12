/// Which elevation tiles the 3D course preview drapes the basemap over.
///
/// Precedence mirrors `styleUrlForSlug` in `map-style-url.ts`: the
/// `PUBLIC_TERRAIN_URL` override wins outright (local / offline /
/// self-hosted), then MapTiler's keyed terrain when `PUBLIC_MAPTILER_KEY` is
/// set, then the keyless AWS Open Data Terrain Tiles so the preview still has
/// relief on a deploy with no MapTiler key. Every rung is a third-party fetch
/// that logs the requester IP, so a caller must sit behind the same cookie
/// consent gate as the 2D maps (`consent_guards.test.ts`).

export interface TerrainSource {
	tiles: string[];
	encoding: 'mapbox' | 'terrarium';
	tileSize: 256 | 512;
	maxzoom: number;
	attribution: string;
}

export const TERRAIN_EXAGGERATION = 1.5;

/// A course whose own relief (highest less lowest height) is under this is
/// drawn with more exaggeration, in inverse proportion, so its hills read
/// from the chase camera: 1.5x at 100 m, 2x at 75 m.
export const LOW_RELIEF_M = 100;

/// The bound on that scaling. At 3x a 30 m climb stands like a 90 m one, and
/// a mountain course never gets past `TERRAIN_EXAGGERATION`.
export const MAX_TERRAIN_EXAGGERATION = 3;

/// The terrain exaggeration for a course with `reliefM` metres of relief; an
/// unknown relief (no elevation on the line) keeps the base.
export function terrainExaggeration(reliefM: number | null): number {
	if (reliefM == null || !Number.isFinite(reliefM) || reliefM <= 0) return TERRAIN_EXAGGERATION;
	const scaled = (TERRAIN_EXAGGERATION * LOW_RELIEF_M) / reliefM;
	return Math.min(MAX_TERRAIN_EXAGGERATION, Math.max(TERRAIN_EXAGGERATION, scaled));
}
export const FLYOVER_PITCH = 60;

/// MapTiler's own TileJSON (`/tiles/terrain-rgb-v2/tiles.json`) declares this
/// template, `maxzoom` 14 and `scale` 2, i.e. 512 px WebP tiles in the
/// Mapbox Terrain-RGB encoding.
function maptilerTerrainSource(key: string): TerrainSource {
	return {
		tiles: [
			`https://api.maptiler.com/tiles/terrain-rgb-v2/{z}/{x}/{y}?key=${encodeURIComponent(key)}`,
		],
		encoding: 'mapbox',
		tileSize: 512,
		maxzoom: 14,
		attribution:
			'<a href="https://www.maptiler.com/copyright/" target="_blank" rel="noopener noreferrer">&copy; MapTiler</a> ' +
			'<a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">&copy; OpenStreetMap contributors</a>',
	};
}

/// The virtual-hosted bucket name, not the path-style
/// `s3.amazonaws.com/elevation-tiles-prod/…` form: the CSP can then allow
/// this one bucket instead of every bucket on `s3.amazonaws.com`, which would
/// make `connect-src` an exfiltration channel to any S3 bucket. The full
/// per-source credit (USGS, Copernicus EU-DEM, Geoscience Australia, …) lives
/// on /settings/licenses; the on-map line links to the upstream list.
export const AWS_TERRAIN_TILES_HOST = 'elevation-tiles-prod.s3.amazonaws.com';

export const AWS_TERRAIN_SOURCE: TerrainSource = {
	tiles: [`https://${AWS_TERRAIN_TILES_HOST}/terrarium/{z}/{x}/{y}.png`],
	encoding: 'terrarium',
	tileSize: 256,
	maxzoom: 15,
	attribution:
		'<a href="https://github.com/tilezen/joerd/blob/master/docs/attribution.md" target="_blank" rel="noopener noreferrer">Terrain Tiles: Mapzen, USGS and others</a>',
};

/// An override's encoding can't be read from the bytes until they arrive, so
/// it is classified by its URL, the same substring test `basemapIsDarkForSlug`
/// applies to a self-hosted style: a template naming `terrarium` gets the
/// AWS-shaped source, anything else the MapTiler-shaped one.
function overrideSource(url: string): TerrainSource {
	const terrarium = url.toLowerCase().includes('terrarium');
	return {
		tiles: [url],
		encoding: terrarium ? 'terrarium' : 'mapbox',
		tileSize: terrarium ? 256 : 512,
		maxzoom: terrarium ? 15 : 14,
		attribution: '',
	};
}

export function resolveTerrainSource(opts: { maptilerKey: string; override: string }): TerrainSource {
	const override = opts.override.trim();
	if (override.length > 0) return overrideSource(override);
	const key = opts.maptilerKey.trim();
	if (key.length > 0) return maptilerTerrainSource(key);
	return AWS_TERRAIN_SOURCE;
}
