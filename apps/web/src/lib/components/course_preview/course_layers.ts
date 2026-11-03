import type * as GeoJSON from 'geojson';
import type maplibregl from '#lib/routes/maplibre.ts';
import {
	mapClimbLine,
	mapLabelHalo,
	mapLabelInk,
	mapOverlayOutline,
	mapTrackLine,
} from '#lib/routes/basemap_contrast.ts';
import type { Climb } from '#lib/routes/course_climbs.ts';
import type { DistanceMarker, FlyoverPath } from '#lib/routes/flyover_path.ts';
import { sliceCourse } from './course_slice.ts';

/// The course line, its climbs and its distance markers, drawn the same way on
/// the dialog's map and on the offscreen map the video export records, so the
/// file shows what the dialog showed. Auxiliary: a failure leaves the basemap
/// (and terrain) standing.

export interface CourseLayerInput {
	path: FlyoverPath;
	climbs: readonly Climb[];
	markers: readonly DistanceMarker[];
	darkBasemap: boolean;
}

export function addCourseLayers(
	target: maplibregl.Map,
	{ path, climbs, markers, darkBasemap }: CourseLayerInput,
): void {
	const coords = path.points.map((p): [number, number] => [p.lng, p.lat]);
	try {
		target.addSource('course-line', {
			type: 'geojson',
			data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: coords } },
		});
		target.addLayer({
			id: 'course-line-casing',
			type: 'line',
			source: 'course-line',
			paint: { 'line-color': mapOverlayOutline(darkBasemap), 'line-width': 8, 'line-opacity': 0.3 },
			layout: { 'line-join': 'round', 'line-cap': 'round' },
		});
		target.addLayer({
			id: 'course-line',
			type: 'line',
			source: 'course-line',
			paint: { 'line-color': mapTrackLine(darkBasemap), 'line-width': 4 },
			layout: { 'line-join': 'round', 'line-cap': 'round' },
		});

		const climbLines: GeoJSON.FeatureCollection<GeoJSON.LineString> = {
			type: 'FeatureCollection',
			features: climbs
				.map((c) => sliceCourse(path, c.startM, c.endM))
				.filter((line) => line.length >= 2)
				.map((line) => ({
					type: 'Feature',
					properties: {},
					geometry: { type: 'LineString', coordinates: line },
				})),
		};
		if (climbLines.features.length > 0) {
			target.addSource('course-climbs', { type: 'geojson', data: climbLines });
			target.addLayer({
				id: 'course-climbs',
				type: 'line',
				source: 'course-climbs',
				paint: { 'line-color': mapClimbLine(darkBasemap), 'line-width': 6 },
				layout: { 'line-join': 'round', 'line-cap': 'round' },
			});
		}

		if (markers.length > 0) {
			target.addSource('course-markers', {
				type: 'geojson',
				data: {
					type: 'FeatureCollection',
					features: markers.map((mk) => ({
						type: 'Feature',
						properties: { label: String(mk.label) },
						geometry: { type: 'Point', coordinates: [mk.lng, mk.lat] },
					})),
				},
			});
			target.addLayer({
				id: 'course-marker-bg',
				type: 'circle',
				source: 'course-markers',
				paint: {
					'circle-radius': 11,
					'circle-color': mapLabelHalo(darkBasemap),
					'circle-stroke-color': mapTrackLine(darkBasemap),
					'circle-stroke-width': 2,
				},
			});
			target.addLayer({
				id: 'course-marker-text',
				type: 'symbol',
				source: 'course-markers',
				layout: {
					'text-field': ['get', 'label'],
					'text-size': 11,
					'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
					'text-allow-overlap': true,
				},
				paint: { 'text-color': mapLabelInk(darkBasemap) },
			});
		}
	} catch (e) {
		console.warn('course preview: overlay failed', e);
	}
}
