// Drawing a course's start and finish lines on a MapLibre map (#1305,
// decisions § 2390): the line itself, and for the finish a direction arrow
// with a chevron head, so a runner reads which way the line is crossed. The
// GeoJSON is pure and tested; addCourseGateLayers only wires it to a map.

import type * as GeoJSON from 'geojson';
import type maplibregl from '#lib/routes/maplibre.ts';
import { mapFinishColour, mapOverlayOutline, mapStartColour } from '../routes/basemap_contrast';
import { gateArrowTip, gateLineEnds, offsetPoint, type GateWhich } from './course_gates';
import type { Gate } from '../geo/gate_crossing';

export interface DrawnGate {
	which: GateWhich;
	gate: Gate;
	/** Which course the line belongs to, so a multi-course map can tell them apart. */
	courseId: string;
}

export type GateFeatureKind = 'line' | 'arrow';

export interface GateFeatureProps {
	which: GateWhich;
	kind: GateFeatureKind;
	courseId: string;
}

/** Length of each side of the arrow's chevron head. */
const CHEVRON_M = 6;

/**
 * Every line as a LineString, and every finish line's arrow (centre to tip,
 * plus a chevron at the tip) as a MultiLineString. The start line carries no
 * arrow: a racer starts behind it and crosses it once.
 */
export function courseGateGeoJSON(
	gates: readonly DrawnGate[],
): GeoJSON.FeatureCollection<GeoJSON.LineString | GeoJSON.MultiLineString, GateFeatureProps> {
	const features: GeoJSON.Feature<GeoJSON.LineString | GeoJSON.MultiLineString, GateFeatureProps>[] = [];
	for (const { which, gate, courseId } of gates) {
		const [left, right] = gateLineEnds(gate);
		features.push({
			type: 'Feature',
			geometry: { type: 'LineString', coordinates: [[left.lng, left.lat], [right.lng, right.lat]] },
			properties: { which, kind: 'line', courseId },
		});
		if (which !== 'finish') continue;
		const tip = gateArrowTip(gate);
		const back = gate.bearingDeg + 180;
		const wingL = offsetPoint(tip, back - 35, CHEVRON_M);
		const wingR = offsetPoint(tip, back + 35, CHEVRON_M);
		features.push({
			type: 'Feature',
			geometry: {
				type: 'MultiLineString',
				coordinates: [
					[[gate.lng, gate.lat], [tip.lng, tip.lat]],
					[[wingL.lng, wingL.lat], [tip.lng, tip.lat], [wingR.lng, wingR.lat]],
				],
			},
			properties: { which, kind: 'arrow', courseId },
		});
	}
	return { type: 'FeatureCollection', features };
}

/** The [west, south, east, north] box around every line and arrow, or null. */
export function courseGateBounds(gates: readonly DrawnGate[]): [number, number, number, number] | null {
	let w = Infinity;
	let s = Infinity;
	let e = -Infinity;
	let n = -Infinity;
	for (const f of courseGateGeoJSON(gates).features) {
		const lines = f.geometry.type === 'LineString' ? [f.geometry.coordinates] : f.geometry.coordinates;
		for (const line of lines) {
			for (const [lng, lat] of line) {
				w = Math.min(w, lng);
				e = Math.max(e, lng);
				s = Math.min(s, lat);
				n = Math.max(n, lat);
			}
		}
	}
	return Number.isFinite(w) ? [w, s, e, n] : null;
}

/**
 * Add (or refresh) the lines on a loaded map under `sourceId`. Calling it again
 * after a style swap re-adds the layers; calling it with new gates on a map
 * that already has them only updates the data.
 */
export function addCourseGateLayers(
	map: maplibregl.Map,
	sourceId: string,
	gates: readonly DrawnGate[],
	darkBasemap: boolean,
): void {
	const data = courseGateGeoJSON(gates);
	const existing = map.getSource(sourceId) as maplibregl.GeoJSONSource | undefined;
	if (existing) {
		existing.setData(data);
		return;
	}
	map.addSource(sourceId, { type: 'geojson', data });
	const colour: maplibregl.ExpressionSpecification = [
		'case',
		['==', ['get', 'which'], 'start'],
		mapStartColour(darkBasemap),
		mapFinishColour(darkBasemap),
	];
	map.addLayer({
		id: `${sourceId}-casing`,
		type: 'line',
		source: sourceId,
		layout: { 'line-cap': 'round', 'line-join': 'round' },
		paint: { 'line-color': mapOverlayOutline(darkBasemap), 'line-width': 9 },
	});
	map.addLayer({
		id: `${sourceId}-line`,
		type: 'line',
		source: sourceId,
		layout: { 'line-cap': 'round', 'line-join': 'round' },
		paint: {
			'line-color': colour,
			'line-width': ['case', ['==', ['get', 'kind'], 'line'], 6, 3],
		},
	});
}
