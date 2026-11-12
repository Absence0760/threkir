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
import {
	START_FINISH_TEXT_SIZE,
	startFinishFill,
	startFinishImageId,
	startFinishInk,
	startFinishPillImage,
	type StartFinishKind,
	type StartFinishMarker,
} from './start_finish.ts';

/// The course line, its climbs, its distance markers and its start / finish
/// markers, drawn the same way on
/// the dialog's map and on the offscreen map the video export records, so the
/// file shows what the dialog showed. Auxiliary: a failure leaves the basemap
/// (and terrain) standing.

export interface CourseLayerInput {
	path: FlyoverPath;
	climbs: readonly Climb[];
	markers: readonly DistanceMarker[];
	/// `startFinishMarkers` of the same path: one for a loop, two otherwise.
	startFinish: readonly StartFinishMarker[];
	darkBasemap: boolean;
}

/// The layers `addCourseLayers` draws the start / finish markers with, in
/// paint order, above the km markers.
export const START_FINISH_LAYER_IDS = ['course-start-finish-dot', 'course-start-finish-label'] as const;

export function addCourseLayers(
	target: maplibregl.Map,
	{ path, climbs, markers, startFinish, darkBasemap }: CourseLayerInput,
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

		if (startFinish.length > 0) addStartFinish(target, startFinish, darkBasemap);
	} catch (e) {
		console.warn('course preview: overlay failed', e);
	}
}

/// A small dot on the exact start / finish point, and the label in a pill
/// above it, so the pill never covers the line's end or the position dot
/// sitting on it at the start of the flight.
function addStartFinish(
	target: maplibregl.Map,
	startFinish: readonly StartFinishMarker[],
	darkBasemap: boolean,
): void {
	const kinds = [...new Set(startFinish.map((s) => s.kind))];
	for (const kind of kinds) {
		const id = startFinishImageId(kind, darkBasemap);
		if (target.hasImage(id)) continue;
		const img = startFinishPillImage(kind, darkBasemap);
		target.addImage(
			id,
			{ width: img.width, height: img.height, data: img.data },
			{ pixelRatio: img.pixelRatio, stretchX: img.stretchX, stretchY: img.stretchY, content: img.content },
		);
	}
	target.addSource('course-start-finish', {
		type: 'geojson',
		data: {
			type: 'FeatureCollection',
			features: startFinish.map((s) => ({
				type: 'Feature',
				properties: { kind: s.kind, label: s.label, icon: startFinishImageId(s.kind, darkBasemap) },
				geometry: { type: 'Point', coordinates: [s.lng, s.lat] },
			})),
		},
	});
	const fillByKind = (kind: StartFinishKind) => startFinishFill(kind, darkBasemap);
	target.addLayer({
		id: START_FINISH_LAYER_IDS[0],
		type: 'circle',
		source: 'course-start-finish',
		paint: {
			'circle-radius': 5,
			'circle-color': ['match', ['get', 'kind'], 'finish', fillByKind('finish'), fillByKind('start')],
			'circle-stroke-color': mapOverlayOutline(darkBasemap),
			'circle-stroke-width': 2,
		},
	});
	target.addLayer({
		id: START_FINISH_LAYER_IDS[1],
		type: 'symbol',
		source: 'course-start-finish',
		layout: {
			'text-field': ['get', 'label'],
			'text-size': START_FINISH_TEXT_SIZE,
			'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
			'text-anchor': 'bottom',
			// 1.2 em lifts the pill's lower edge clear of the 7 px dot.
			'text-offset': [0, -1.2],
			'text-allow-overlap': true,
			'text-ignore-placement': true,
			'icon-image': ['get', 'icon'],
			'icon-text-fit': 'both',
			'icon-allow-overlap': true,
			'icon-ignore-placement': true,
		},
		paint: { 'text-color': startFinishInk(darkBasemap) },
	});
}
