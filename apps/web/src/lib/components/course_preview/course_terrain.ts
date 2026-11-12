import type { TerrainSource } from '#lib/routes/terrain_source.ts';

/// The terrain the 3D preview drapes the basemap over, and the hillshade drawn
/// from the same elevation tiles, set up the same way on the dialog's map and
/// on the offscreen map the video export records. The hillshade is what makes
/// a 20-30 m road climb visible from the chase camera on a basemap with no
/// relief shading of its own (#1283).
///
/// It is a second `raster-dem` source over the same tiles rather than the
/// terrain's own source, which MapLibre renders at a lower resolution when it
/// also drives the 3D mesh; the tiles are the same URLs, so the browser
/// fetches each once, from the host the consent gate already covers, and the
/// attribution control prints the identical credit once.

export const TERRAIN_SOURCE_ID = 'course-terrain';
export const HILLSHADE_SOURCE_ID = 'course-hillshade';
export const HILLSHADE_LAYER_ID = 'course-hillshade';

interface StyleLayer {
	id: string;
	type: string;
}

export interface HillshadeLayer {
	id: string;
	type: 'hillshade';
	source: string;
	paint: { 'hillshade-illumination-anchor': 'map'; 'hillshade-exaggeration': number };
}

/// The subset of `maplibregl.Map` this module drives, so it runs against a
/// recording fake in unit tests.
export interface TerrainTarget {
	addSource(id: string, source: { type: 'raster-dem' } & TerrainSource): unknown;
	addLayer(layer: HillshadeLayer, beforeId?: string): unknown;
	setTerrain(terrain: { source: string; exaggeration: number } | null): unknown;
	getStyle(): { layers?: readonly StyleLayer[] } | undefined;
	getLayer(id: string): unknown;
	removeLayer(id: string): unknown;
}

/// The first label layer, so the hillshade goes under every label (and, added
/// before the course layers, under the line). Undefined appends it, which on
/// a raster basemap with no labels is still under the course.
export function hillshadeBeforeId(layers: readonly StyleLayer[] | undefined): string | undefined {
	return layers?.find((l) => l.type === 'symbol')?.id;
}

/// A style that already shades its relief keeps its own, rather than being
/// shaded twice.
export function styleHasHillshade(layers: readonly StyleLayer[] | undefined): boolean {
	return layers?.some((l) => l.type === 'hillshade') ?? false;
}

/// Turns terrain on and adds the hillshade. Throws when the terrain itself
/// cannot be set, for the caller to fall back to the flat course; a hillshade
/// failure is logged and leaves the terrain standing.
export function addCourseTerrain(
	target: TerrainTarget,
	source: TerrainSource,
	opts: { exaggeration: number; darkBasemap: boolean },
): void {
	target.addSource(TERRAIN_SOURCE_ID, { type: 'raster-dem', ...source });
	target.setTerrain({ source: TERRAIN_SOURCE_ID, exaggeration: opts.exaggeration });
	try {
		const layers = target.getStyle()?.layers;
		if (styleHasHillshade(layers)) return;
		target.addSource(HILLSHADE_SOURCE_ID, { type: 'raster-dem', ...source });
		target.addLayer(
			{
				id: HILLSHADE_LAYER_ID,
				type: 'hillshade',
				source: HILLSHADE_SOURCE_ID,
				paint: {
					// Lit from the map's north-west whatever the camera bearing, so
					// the shading does not swing round as the flight turns.
					'hillshade-illumination-anchor': 'map',
					'hillshade-exaggeration': opts.darkBasemap ? 0.45 : 0.3,
				},
			},
			hillshadeBeforeId(layers),
		);
	} catch (e) {
		console.warn('course preview: hillshade unavailable', e);
	}
}

/// Takes the terrain and the hillshade off after a tile failure; each step is
/// separate, so one refusing does not keep the other on.
export function removeCourseTerrain(target: TerrainTarget): void {
	try {
		target.setTerrain(null);
	} catch (e) {
		console.warn('course preview: could not clear terrain', e);
	}
	try {
		if (target.getLayer(HILLSHADE_LAYER_ID)) target.removeLayer(HILLSHADE_LAYER_ID);
	} catch (e) {
		console.warn('course preview: could not clear hillshade', e);
	}
}
