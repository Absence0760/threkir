// Drawing a course's start and finish lines on a MapLibre map (#1305,
// decisions § 2390): the line itself, and for the finish a direction arrow
// with a chevron head, so a runner reads which way the line is crossed. The
// GeoJSON is pure and tested; addCourseGateLayers only wires it to a map.

import type * as GeoJSON from 'geojson';
import type maplibregl from '#lib/routes/maplibre.ts';
import {
	MAP_ARROW_OUTLINE,
	MAP_ZONE_FILL_OPACITY,
	mapFinishColour,
	mapBoxInk,
	mapFinishZoneColour,
	mapOverlayOutline,
	mapStartColour,
	mapStartZoneColour,
} from '../routes/basemap_contrast';
import {
	gateArrowTip,
	gateBoxParts,
	gateLineEnds,
	offsetPoint,
	type GatePoint,
	type GateWhich,
} from './course_gates';
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
		features.push({
			type: 'Feature',
			geometry: arrowGeometry(gate, gateArrowTip(gate), gate.bearingDeg),
			properties: { which, kind: 'arrow', courseId },
		});
	}
	return { type: 'FeatureCollection', features };
}

/** A shaft from `from` to `tip` with a chevron head at the tip. */
function arrowGeometry(from: GatePoint, tip: GatePoint, bearingDeg: number): GeoJSON.MultiLineString {
	const back = bearingDeg + 180;
	const wingL = offsetPoint(tip, back - 35, CHEVRON_M);
	const wingR = offsetPoint(tip, back + 35, CHEVRON_M);
	return {
		type: 'MultiLineString',
		coordinates: [
			[[from.lng, from.lat], [tip.lng, tip.lat]],
			[[wingL.lng, wingL.lat], [tip.lng, tip.lat], [wingR.lng, wingR.lat]],
		],
	};
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

export type GateBoxFeatureKind = 'area' | 'edge';

export interface GateBoxFeatureProps {
	which: GateWhich;
	kind: GateBoxFeatureKind;
}

/**
 * A course's start and finish boxes (decisions § 2582), from gateBoxParts:
 * each box as a Polygon and its edge on the stored line as a LineString.
 * The flags and names go on as DOM markers, so they keep their size at any
 * zoom (gateFlagSvg).
 */
export function courseGateBoxGeoJSON(
	start: Gate | null,
	finish: Gate | null,
): GeoJSON.FeatureCollection<GeoJSON.Polygon | GeoJSON.LineString, GateBoxFeatureProps> {
	const features: GeoJSON.Feature<GeoJSON.Polygon | GeoJSON.LineString, GateBoxFeatureProps>[] = [];
	const ring = (pts: GatePoint[]) => [...pts, pts[0]].map((p) => [p.lng, p.lat]);
	const { parts } = gateBoxParts(start, finish);
	for (const p of parts) {
		features.push({
			type: 'Feature',
			geometry: { type: 'Polygon', coordinates: [ring(p.box)] },
			properties: { which: p.which, kind: 'area' },
		});
	}
	for (const p of parts) {
		features.push({
			type: 'Feature',
			geometry: { type: 'LineString', coordinates: p.line.map((q) => [q.lng, q.lat]) },
			properties: { which: p.which, kind: 'edge' },
		});
	}
	return { type: 'FeatureCollection', features };
}

/**
 * Add (or refresh) the boxes on a loaded map under `sourceId`: a translucent
 * fill, a full-strength outline, and the edge on the stored line, cased, solid
 * for the start and chequered for the finish, so the two never differ by hue
 * alone.
 */
export function addCourseGateBoxLayers(
	map: maplibregl.Map,
	sourceId: string,
	start: Gate | null,
	finish: Gate | null,
	darkBasemap: boolean,
): void {
	const data = courseGateBoxGeoJSON(start, finish);
	const existing = map.getSource(sourceId) as maplibregl.GeoJSONSource | undefined;
	if (existing) {
		existing.setData(data);
		return;
	}
	map.addSource(sourceId, { type: 'geojson', data });
	const colour: maplibregl.ExpressionSpecification = [
		'case',
		['==', ['get', 'which'], 'start'],
		mapStartZoneColour(darkBasemap),
		mapFinishZoneColour(darkBasemap),
	];
	const kindIs = (k: GateBoxFeatureKind): maplibregl.ExpressionSpecification => ['==', ['get', 'kind'], k];
	map.addLayer({
		id: `${sourceId}-fill`,
		type: 'fill',
		source: sourceId,
		filter: kindIs('area'),
		paint: { 'fill-color': colour, 'fill-opacity': MAP_ZONE_FILL_OPACITY },
	});
	map.addLayer({
		id: `${sourceId}-outline`,
		type: 'line',
		source: sourceId,
		filter: kindIs('area'),
		layout: { 'line-join': 'round' },
		paint: { 'line-color': colour, 'line-width': 2 },
	});
	map.addLayer({
		id: `${sourceId}-edge-casing`,
		type: 'line',
		source: sourceId,
		filter: kindIs('edge'),
		layout: { 'line-cap': 'round' },
		paint: { 'line-color': mapOverlayOutline(darkBasemap), 'line-width': 8 },
	});
	map.addLayer({
		id: `${sourceId}-edge`,
		type: 'line',
		source: sourceId,
		filter: kindIs('edge'),
		layout: { 'line-cap': 'round' },
		paint: { 'line-color': colour, 'line-width': 5 },
	});
	map.addLayer({
		id: `${sourceId}-chequer`,
		type: 'line',
		source: sourceId,
		filter: ['all', kindIs('edge'), ['==', ['get', 'which'], 'finish']],
		paint: { 'line-color': MAP_ARROW_OUTLINE, 'line-width': 5, 'line-dasharray': [1, 1] },
	});
}

/**
 * The flag on a box's name tag, in the tag's ink: a plain flag for the start,
 * a chequered one for the finish, both for a box they share. Static markup
 * from the palette only; the name is set as text beside it.
 */
export function gateFlagSvg(which: GateWhich | 'both', darkBasemap: boolean): string {
	const ink = mapBoxInk(darkBasemap);
	const flag = (x: number, chequered: boolean) => {
		const cloth = chequered
			? `<rect x="${x + 3}" y="3" width="12" height="8" fill="none" stroke="${ink}" stroke-width="1"/>` +
				[0, 1, 2]
					.flatMap((c) => [0, 1].map((r) => [c, r]))
					.filter(([c, r]) => (c + r) % 2 === 0)
					.map(([c, r]) => `<rect x="${x + 3 + c * 4}" y="${3 + r * 4}" width="4" height="4" fill="${ink}"/>`)
					.join('')
			: `<rect x="${x + 3}" y="3" width="12" height="8" fill="${ink}"/>`;
		return `<rect x="${x + 1}" y="2" width="2" height="16" fill="${ink}"/>` + cloth;
	};
	const parts = which === 'both' ? [flag(0, false), flag(16, true)] : [flag(0, which === 'finish')];
	const width = which === 'both' ? 32 : 16;
	return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} 20" width="${width}" height="20" aria-hidden="true" focusable="false">${parts.join('')}</svg>`;
}

/** The U-turn on an out-and-back's turn-around tag, in the tag's ink. */
export function turnaroundSvg(ink: string): string {
	return (
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="20" height="20" aria-hidden="true" focusable="false">` +
		`<path d="M6 18V8a4 4 0 0 1 8 0v6" fill="none" stroke="${ink}" stroke-width="2.4" stroke-linecap="round"/>` +
		`<path d="M10.5 11.5L14 15l3.5-3.5" fill="none" stroke="${ink}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>` +
		`</svg>`
	);
}
