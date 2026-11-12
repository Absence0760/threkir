/// Start and finish markers for the 3D course preview and its video export
/// (decisions § 2423). Pure: which markers a course gets, and the pill image
/// MapLibre stretches behind each label, so both are testable without a map.
import { haversineMetres } from '#lib/runs/run_stats.ts';
import type { FlyoverPath } from '#lib/routes/flyover_path.ts';
import {
	mapFinishColour,
	mapLabelHalo,
	mapOverlayOutline,
	mapStartColour,
} from '#lib/routes/basemap_contrast.ts';

/// A course whose first and last points are this close is a loop: one
/// "Start / Finish" marker. An out-and-back ends where it began, so it is a
/// loop by this rule too. 50 m is wider than a GPS fix's error and the gap a
/// traced loop leaves between its ends, and narrower than any start and
/// finish a runner would walk between.
export const LOOP_CLOSE_M = 50;

export type StartFinishKind = 'start' | 'finish' | 'startFinish';

export interface StartFinishLabels {
	start: string;
	finish: string;
	startFinish: string;
}

export interface StartFinishMarker {
	kind: StartFinishKind;
	label: string;
	lat: number;
	lng: number;
}

/// Whether the course ends within `LOOP_CLOSE_M` of where it starts.
export function isLoopCourse(path: FlyoverPath, closeM: number = LOOP_CLOSE_M): boolean {
	const pts = path.points;
	if (pts.length < 2) return false;
	const a = pts[0];
	const b = pts[pts.length - 1];
	return haversineMetres(a.lat, a.lng, b.lat, b.lng) <= closeM;
}

/// One marker at the start of a loop, a Start and a Finish otherwise; none
/// for a path with no length.
export function startFinishMarkers(path: FlyoverPath, labels: StartFinishLabels): StartFinishMarker[] {
	const pts = path.points;
	if (pts.length < 2 || !(path.totalM > 0)) return [];
	const a = pts[0];
	const b = pts[pts.length - 1];
	if (isLoopCourse(path)) {
		return [{ kind: 'startFinish', label: labels.startFinish, lat: a.lat, lng: a.lng }];
	}
	return [
		{ kind: 'start', label: labels.start, lat: a.lat, lng: a.lng },
		{ kind: 'finish', label: labels.finish, lat: b.lat, lng: b.lng },
	];
}

/// The image id each kind's pill is registered under.
export function startFinishImageId(kind: StartFinishKind, darkBasemap: boolean): string {
	return `course-${kind}-pill-${darkBasemap ? 'dark' : 'light'}`;
}

/// The pill's fill: green for a start (a loop starts there too), red for a
/// finish, the app's start / finish cap colours.
export function startFinishFill(kind: StartFinishKind, darkBasemap: boolean): string {
	return kind === 'finish' ? mapFinishColour(darkBasemap) : mapStartColour(darkBasemap);
}

/// Label and flag ink: white on the deep light-basemap fills, near-black on
/// the bright dark-basemap ones, so the text holds AA on the pill itself.
export function startFinishInk(darkBasemap: boolean): string {
	return mapLabelHalo(darkBasemap);
}

/// Whether the pill carries the chequered flag: every marker where the
/// course finishes.
export function hasFinishFlag(kind: StartFinishKind): boolean {
	return kind !== 'start';
}

/// The label's type size, in CSS px. The km markers are 11; these are the
/// course's two landmarks and must read on a phone in the 1080x1920 export.
export const START_FINISH_TEXT_SIZE = 13;
/// Pill height, CSS px: one 13 px line (MapLibre's 1.2 line height) plus
/// 4 px above and below.
export const PILL_H = 24;
const OUTLINE = 1.5;
const PAD = 9;
const FLAG_W = 17;
const STRETCH = 2;

export interface PillImage {
	width: number;
	height: number;
	data: Uint8ClampedArray;
	pixelRatio: number;
	/// MapLibre's stretchable-image metadata, in image pixels: only the
	/// straight middle stretches, so the caps and the flag keep their shape.
	stretchX: [number, number][];
	stretchY: [number, number][];
	/// Where the label goes, in image pixels: `icon-text-fit` sizes the pill
	/// so this box holds the text.
	content: [number, number, number, number];
}

function rgb(hex: string): [number, number, number] {
	const n = Number.parseInt(hex.slice(1), 16);
	return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/// Distance from (x, y) to the stadium's spine, minus its radius: negative
/// inside.
function stadium(x: number, y: number, w: number, r: number): number {
	const cx = Math.min(Math.max(x, r), w - r);
	return Math.hypot(x - cx, y - r) - r;
}

/// The pill behind a start / finish label, as RGBA pixels: a stadium in the
/// kind's fill with the basemap's overlay outline, and, where the course
/// finishes, a chequered flag in the label's ink before the text.
export function startFinishPillImage(kind: StartFinishKind, darkBasemap: boolean, pixelRatio = 3): PillImage {
	const flag = hasFinishFlag(kind);
	const left = flag ? PAD + FLAG_W : PAD;
	const r = PILL_H / 2;
	const straight0 = Math.max(left, r);
	const wCss = straight0 + STRETCH + Math.max(PAD, r);
	const width = Math.round(wCss * pixelRatio);
	const height = Math.round(PILL_H * pixelRatio);
	const fill = rgb(startFinishFill(kind, darkBasemap));
	const ink = rgb(startFinishInk(darkBasemap));
	const edge = rgb(mapOverlayOutline(darkBasemap));
	// Flag, CSS px: a pole and a 4 x 3 chequer, centred on the pill's height.
	const sq = 2.5;
	const fx = PAD + 1;
	const fy = (PILL_H - 13) / 2;
	const poleW = 1.5;
	const chequerX = fx + poleW;
	const chequerY = fy;
	const inFlag = (x: number, y: number): boolean => {
		if (!flag) return false;
		if (x >= fx && x < fx + poleW && y >= fy && y < fy + 13) return true;
		if (x < chequerX || x >= chequerX + 4 * sq || y < chequerY || y >= chequerY + 3 * sq) return false;
		const col = Math.floor((x - chequerX) / sq);
		const row = Math.floor((y - chequerY) / sq);
		return (col + row) % 2 === 0;
	};
	// The chequer's other squares are the fill, so the flag needs a frame of
	// ink to read as a flag rather than as three dashes.
	const onChequerFrame = (x: number, y: number): boolean => {
		if (!flag) return false;
		const x1 = chequerX + 4 * sq;
		const y1 = chequerY + 3 * sq;
		if (x < chequerX || x >= x1 + 0.5 || y < chequerY - 0.5 || y >= y1 + 0.5) return false;
		return x >= x1 || y < chequerY || y >= y1;
	};

	const data = new Uint8ClampedArray(width * height * 4);
	const S = 4;
	for (let py = 0; py < height; py++) {
		for (let px = 0; px < width; px++) {
			let rr = 0;
			let gg = 0;
			let bb = 0;
			let n = 0;
			for (let sy = 0; sy < S; sy++) {
				for (let sx = 0; sx < S; sx++) {
					const x = (px + (sx + 0.5) / S) / pixelRatio;
					const y = (py + (sy + 0.5) / S) / pixelRatio;
					const d = stadium(x, y, wCss, r);
					if (d > 0) continue;
					const c = d > -OUTLINE ? edge : inFlag(x, y) || onChequerFrame(x, y) ? ink : fill;
					rr += c[0];
					gg += c[1];
					bb += c[2];
					n++;
				}
			}
			const i = (py * width + px) * 4;
			if (n === 0) continue;
			data[i] = Math.round(rr / n);
			data[i + 1] = Math.round(gg / n);
			data[i + 2] = Math.round(bb / n);
			data[i + 3] = Math.round((255 * n) / (S * S));
		}
	}

	const px = (v: number) => Math.round(v * pixelRatio);
	return {
		width,
		height,
		data,
		pixelRatio,
		stretchX: [[px(straight0), px(straight0 + STRETCH)]],
		stretchY: [[px(r - 1), px(r + 1)]],
		content: [px(left - 1), px(4), px(wCss - PAD + 2), px(PILL_H - 4)],
	};
}
