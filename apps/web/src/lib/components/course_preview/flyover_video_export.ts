/// Browser glue for the flyover video export (decisions § 2259): an offscreen
/// MapLibre map framed like the phone preview and drawn at the video's size
/// (`videoMapViewport`), stepped frame by frame by the pure
/// clock in `video_timeline.ts`, composited with the overlays
/// `video_overlay.ts` places, and encoded through the shared sink in
/// `#lib/video/encode_video.ts`. Everything that can be decided without a
/// browser is decided in those modules; this file only drives the APIs.
import maplibregl from '#lib/routes/maplibre.ts';
import type { Climb, StripSample } from '#lib/routes/course_climbs.ts';
import {
	distanceMarkers,
	pointAtDistance,
	type FlyoverPath,
} from '#lib/routes/flyover_path.ts';
import { FLYOVER_PITCH, type TerrainSource } from '#lib/routes/terrain_source.ts';
import { basemapIsDarkFromEnv, mapStyleUrlFromEnv } from '#lib/routes/map-style.svelte.ts';
import { mapAccentColour, mapOverlayOutline } from '#lib/routes/basemap_contrast.ts';
import { OG_CARD_DARK } from '#lib/share/og_card_palette.ts';
import { addCourseLayers } from './course_layers.ts';
import { addCourseTerrain } from './course_terrain.ts';
import { stripGeometry, stripX } from './strip_geometry.ts';
import { flightCamera } from './flight_frame.ts';
import type { VideoEncoderPlan } from '#lib/video/video_encoder.ts';
import { VIDEO_HEIGHT, VIDEO_WIDTH } from '#lib/video/frame_clock.ts';
import { createFrameSink, videoAbortError, type FrameSink } from '#lib/video/encode_video.ts';
import { VIDEO_FINALE, videoFlightSpeedMps, videoFrame, videoTimeline, type VideoFrame } from './video_timeline.ts';
import {
	finaleCamera,
	OVERVIEW_PITCH,
	overviewPose,
	pathBounds,
	type CameraPose,
} from './overview.ts';
import {
	climbIndexAt,
	endCardAlpha,
	videoAttribution,
	videoOverlayLayout,
	type TextSlot,
	type VideoOverlayLayout,
} from './video_overlay.ts';
import { videoMapViewport, videoOverviewPadding, type VideoMapViewport } from './video_viewport.ts';

const FLIGHT_ZOOM = 14;
const SETTLE_TIMEOUT_MS = 4000;
const SETTLE_NUDGE_MS = 100;
const FONT = 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';
// The end card and the type are the share cards' dark palette, so a reel and
// a share image from the same run look like one product.
const INK = OG_CARD_DARK.hero;
const END_BG = OG_CARD_DARK.bg;
const BRAND = OG_CARD_DARK.brand;
const CLIMB_FILL = 'rgba(219, 39, 119, 0.85)';

export interface FlyoverVideoText {
	title: string;
	distanceAt: (dM: number) => string;
	ofTotal: string;
	elevationAt: (ele: number) => string;
	climbLabel: (index: number) => string;
	endLines: readonly string[];
	url: string;
}

export interface FlyoverVideoInput {
	path: FlyoverPath;
	unit: 'km' | 'mi';
	/// The route's official distance; scales the km markers (`distanceMarkers`).
	officialDistanceM?: number | null;
	climbs: readonly Climb[];
	strip: readonly StripSample[];
	/// The key the export may use, already passed through the video gate
	/// (`flyoverVideoMaptilerKey`): empty means the keyless basemap.
	maptilerKey: string;
	terrain: TerrainSource | null;
	/// `terrainExaggeration` of the recorded line's relief, as the dialog uses.
	exaggeration: number;
	text: FlyoverVideoText;
	plan: VideoEncoderPlan;
	signal: AbortSignal;
	onprogress: (fraction: number) => void;
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
	return new Promise((resolve) => {
		const img = new Image();
		img.onload = () => resolve(img);
		img.onerror = () => resolve(null);
		img.src = src;
	});
}

function waitForLoad(map: maplibregl.Map, signal: AbortSignal): Promise<void> {
	return new Promise((resolve, reject) => {
		if (map.loaded()) return resolve();
		const onAbort = () => reject(videoAbortError());
		signal.addEventListener('abort', onAbort, { once: true });
		map.once('load', () => {
			signal.removeEventListener('abort', onAbort);
			resolve();
		});
		map.once('error', (e) => {
			if ((e as { sourceId?: string }).sourceId) return;
			signal.removeEventListener('abort', onAbort);
			reject(e.error ?? new Error('map failed to load'));
		});
	});
}

/// Resolves once the frame is drawn with every visible tile in, or after a
/// bound: a tile that never arrives costs that frame its detail, not the
/// whole export.
///
/// `idle` fires only from a render, and a tile the host answers 404 (MapLibre
/// reads that as "no data here", the DEM over open water) settles silently,
/// scheduling none. When that tile was the last one out, the map is loaded
/// with no render coming, and the frame used to wait out the whole bound.
/// So while it waits, a loaded, still map is asked for the render that fires
/// `idle`; a map still loading is left alone.
function settle(map: maplibregl.Map, move: () => void): Promise<void> {
	return new Promise((resolve) => {
		let done = false;
		const finish = () => {
			if (done) return;
			done = true;
			clearTimeout(timer);
			clearInterval(nudge);
			map.off('idle', finish);
			resolve();
		};
		const timer = setTimeout(finish, SETTLE_TIMEOUT_MS);
		const nudge = setInterval(() => {
			if (map.loaded() && !map.isMoving()) map.triggerRepaint();
		}, SETTLE_NUDGE_MS);
		map.on('idle', finish);
		move();
		map.triggerRepaint();
	});
}

function fitText(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string {
	if (ctx.measureText(text).width <= maxWidth) return text;
	let s = text;
	while (s.length > 1 && ctx.measureText(`${s}…`).width > maxWidth) s = s.slice(0, -1);
	return `${s.trimEnd()}…`;
}

function drawText(
	ctx: CanvasRenderingContext2D,
	text: string,
	slot: TextSlot,
	opts: { weight?: number; align?: CanvasTextAlign; color?: string } = {},
) {
	ctx.font = `${opts.weight ?? 700} ${slot.size}px ${FONT}`;
	ctx.textAlign = opts.align ?? 'left';
	ctx.textBaseline = 'alphabetic';
	ctx.fillStyle = opts.color ?? INK;
	ctx.fillText(fitText(ctx, text, slot.maxWidth), slot.x, slot.y);
}

/// The licence credits wrap onto a second line rather than being cut: a
/// truncated attribution is a missing one.
function drawAttribution(ctx: CanvasRenderingContext2D, text: string, slot: TextSlot) {
	ctx.font = `500 ${slot.size}px ${FONT}`;
	ctx.textAlign = 'left';
	ctx.fillStyle = 'rgba(255,255,255,0.88)';
	const words = text.split(' ');
	const lines: string[] = [];
	let line = '';
	for (const w of words) {
		const next = line ? `${line} ${w}` : w;
		if (line && ctx.measureText(next).width > slot.maxWidth) {
			lines.push(line);
			line = w;
		} else {
			line = next;
		}
	}
	if (line) lines.push(line);
	lines.forEach((l, i) => ctx.fillText(l, slot.x, slot.y + i * (slot.size + 6)));
}

interface Scene {
	input: FlyoverVideoInput;
	darkBasemap: boolean;
	layout: VideoOverlayLayout;
	viewport: VideoMapViewport;
	attribution: string;
	mark: HTMLImageElement | null;
	strip: { line: Path2D | null; area: Path2D | null; climbs: { x0: number; x1: number }[] };
}

function composeFrame(
	ctx: CanvasRenderingContext2D,
	scene: Scene,
	mapCanvas: HTMLCanvasElement,
	map: maplibregl.Map,
	frame: VideoFrame,
) {
	const { input, layout: L } = scene;
	const W = L.width;
	const H = L.height;
	ctx.globalAlpha = 1;
	ctx.drawImage(mapCanvas, 0, 0, W, H);

	const top = ctx.createLinearGradient(0, 0, 0, L.topScrim);
	top.addColorStop(0, 'rgba(0,0,0,0.6)');
	top.addColorStop(1, 'rgba(0,0,0,0)');
	ctx.fillStyle = top;
	ctx.fillRect(0, 0, W, L.topScrim);
	const bottom = ctx.createLinearGradient(0, H - L.bottomScrim, 0, H);
	bottom.addColorStop(0, 'rgba(0,0,0,0)');
	bottom.addColorStop(1, 'rgba(0,0,0,0.75)');
	ctx.fillStyle = bottom;
	ctx.fillRect(0, H - L.bottomScrim, W, L.bottomScrim);

	const here = pointAtDistance(input.path, frame.dM);
	// `project` answers in the map's CSS pixels; the frame is video pixels.
	const at = map.project([here.lng, here.lat]);
	const k = scene.viewport.pixelRatio;
	ctx.beginPath();
	ctx.arc(at.x * k, at.y * k, 14, 0, Math.PI * 2);
	ctx.fillStyle = mapAccentColour(scene.darkBasemap);
	ctx.fill();
	ctx.lineWidth = 5;
	ctx.strokeStyle = mapOverlayOutline(scene.darkBasemap);
	ctx.stroke();

	drawText(ctx, input.text.title, L.title, { weight: 800 });
	if (scene.mark) ctx.drawImage(scene.mark, L.mark.x, L.mark.y, L.mark.size, L.mark.size);

	const climb = climbIndexAt(input.climbs, frame.dM);
	if (climb >= 0 && frame.phase === 'flight') {
		const label = input.text.climbLabel(climb);
		ctx.font = `700 ${L.climb.size}px ${FONT}`;
		const w = Math.min(ctx.measureText(label).width, L.climb.maxWidth - 40) + 40;
		ctx.fillStyle = CLIMB_FILL;
		ctx.beginPath();
		ctx.roundRect(L.climb.x, L.climb.y - L.climb.size - 6, w, L.climb.size + 28, 999);
		ctx.fill();
		drawText(ctx, label, { ...L.climb, x: L.climb.x + 20, y: L.climb.y + 4, maxWidth: w - 40 });
	}

	drawText(ctx, input.text.ofTotal, L.distanceLabel, { weight: 600, color: 'rgba(255,255,255,0.85)' });
	drawText(ctx, input.text.distanceAt(frame.dM), L.distance, { weight: 900 });
	if (here.ele != null) drawText(ctx, input.text.elevationAt(here.ele), L.elevation, { align: 'right', weight: 800 });

	const S = L.strip;
	ctx.save();
	ctx.translate(S.x, S.y);
	ctx.fillStyle = 'rgba(219, 39, 119, 0.3)';
	for (const c of scene.strip.climbs) ctx.fillRect(c.x0, 0, Math.max(c.x1 - c.x0, 2), S.h);
	if (scene.strip.area) {
		ctx.fillStyle = 'rgba(255,255,255,0.22)';
		ctx.fill(scene.strip.area);
	}
	if (scene.strip.line) {
		ctx.strokeStyle = INK;
		ctx.lineWidth = 4;
		ctx.lineJoin = 'round';
		ctx.stroke(scene.strip.line);
	}
	const cx = stripX(frame.dM, input.path.totalM, S.w);
	ctx.strokeStyle = BRAND;
	ctx.lineWidth = 5;
	ctx.beginPath();
	ctx.moveTo(cx, 0);
	ctx.lineTo(cx, S.h);
	ctx.stroke();
	ctx.restore();

	drawAttribution(ctx, scene.attribution, L.attribution);

	if (frame.phase === 'end') {
		ctx.globalAlpha = endCardAlpha(frame.progress);
		ctx.fillStyle = END_BG;
		ctx.fillRect(0, 0, W, H);
		const E = L.end;
		if (scene.mark) ctx.drawImage(scene.mark, E.mark.x, E.mark.y, E.mark.size, E.mark.size);
		drawText(ctx, 'Threkir', E.wordmark, { align: 'center', weight: 900 });
		input.text.endLines.forEach((line, i) => {
			const slot = E.lines[i];
			if (slot) drawText(ctx, line, slot, { align: 'center', weight: i === 0 ? 800 : 600 });
		});
		drawText(ctx, input.text.url, E.url, { align: 'center', weight: 700, color: BRAND });
		// The credits stay on the end card too: it is still a frame of the map.
		drawAttribution(ctx, scene.attribution, L.attribution);
		ctx.globalAlpha = 1;
	}
}

/// The whole-course overview in the video's map, or null when the map cannot
/// fit the bounds (the video then holds the finish, as it used to).
function overviewTarget(
	map: maplibregl.Map,
	path: FlyoverPath,
	layout: VideoOverlayLayout,
	viewport: VideoMapViewport,
): CameraPose | null {
	try {
		// Clear of the title and the counter, strip and credits under the scrims.
		const fit = map.cameraForBounds(pathBounds(path), {
			padding: videoOverviewPadding(layout, viewport.pixelRatio),
			bearing: 0,
			pitch: OVERVIEW_PITCH,
		});
		if (!fit?.center || fit.zoom == null) return null;
		const c = maplibregl.LngLat.convert(fit.center);
		return overviewPose({ center: [c.lng, c.lat], zoom: fit.zoom });
	} catch (e) {
		console.warn('flyover video: overview unavailable', e);
		return null;
	}
}

export async function renderFlyoverVideo(input: FlyoverVideoInput): Promise<Blob> {
	const { path, signal } = input;
	if (signal.aborted) throw videoAbortError();
	const t = videoTimeline(path.totalM);
	const layout = videoOverlayLayout(VIDEO_WIDTH, VIDEO_HEIGHT);
	const viewport = videoMapViewport(VIDEO_WIDTH, VIDEO_HEIGHT);
	const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = basemapIsDarkFromEnv(input.maptilerKey, prefersDark);

	const host = document.createElement('div');
	host.setAttribute('aria-hidden', 'true');
	host.style.cssText = `position:fixed;left:0;top:0;width:${viewport.cssWidth}px;height:${viewport.cssHeight}px;transform:translateX(-300vw);pointer-events:none;`;
	document.body.appendChild(host);

	const out = document.createElement('canvas');
	out.width = VIDEO_WIDTH;
	out.height = VIDEO_HEIGHT;
	const ctx = out.getContext('2d');
	let map: maplibregl.Map | null = null;
	let sink: FrameSink | null = null;
	try {
		if (!ctx) throw new Error('no 2D canvas');
		const speedMps = videoFlightSpeedMps(t, path.totalM);
		const flightView = { pitch: FLYOVER_PITCH, zoom: FLIGHT_ZOOM };
		const first = flightCamera(path, 0, flightView, speedMps);
		map = new maplibregl.Map({
			container: host,
			style: mapStyleUrlFromEnv(input.maptilerKey, prefersDark),
			center: first.center,
			bearing: first.bearing,
			pitch: FLYOVER_PITCH,
			zoom: FLIGHT_ZOOM,
			pixelRatio: viewport.pixelRatio,
			interactive: false,
			attributionControl: false,
			fadeDuration: 0,
			maxPitch: 85,
			canvasContextAttributes: { preserveDrawingBuffer: true, antialias: true },
		});
		const m = map;
		const [mark] = await Promise.all([loadImage('/logo-mark.svg'), waitForLoad(m, signal)]);
		if (input.terrain) {
			try {
				addCourseTerrain(m, input.terrain, { exaggeration: input.exaggeration, darkBasemap });
			} catch (e) {
				console.warn('flyover video: terrain unavailable', e);
			}
		}
		addCourseLayers(m, {
			path,
			climbs: input.climbs,
			markers: distanceMarkers(path, input.unit, input.officialDistanceM),
			darkBasemap,
		});

		const styleCredits = Object.values(m.getStyle().sources ?? {}).map(
			(s) => (s as { attribution?: string }).attribution,
		);
		const geom = stripGeometry(input.strip, input.climbs, path.totalM, layout.strip.w, layout.strip.h);
		const scene: Scene = {
			input,
			darkBasemap,
			layout,
			viewport,
			attribution: videoAttribution([...styleCredits, input.terrain?.attribution]),
			mark,
			strip: {
				line: geom.line ? new Path2D(geom.line) : null,
				area: geom.area ? new Path2D(geom.area) : null,
				climbs: geom.climbs,
			},
		};

		const finish = flightCamera(path, path.totalM, flightView, speedMps);
		const from: CameraPose = { center: finish.center, bearing: finish.bearing, pitch: FLYOVER_PITCH, zoom: FLIGHT_ZOOM };
		const overview = overviewTarget(m, path, layout, viewport);

		sink = createFrameSink(input.plan, out, t.fps);
		const mapCanvas = m.getCanvas();
		for (let i = 0; i < t.totalFrames; i++) {
			if (signal.aborted) throw videoAbortError();
			const frame = videoFrame(t, i, path.totalM);
			if (frame.phase === 'flight') {
				const cam = flightCamera(path, frame.dM, flightView, speedMps);
				await settle(m, () => m.jumpTo(cam));
			} else if (frame.phase === 'overview' && overview) {
				const cam = finaleCamera(from, overview, frame.tMs, VIDEO_FINALE);
				await settle(m, () => m.jumpTo(cam));
			}
			composeFrame(ctx, scene, mapCanvas, m, frame);
			await sink.push(out, i);
			input.onprogress((i + 1) / t.totalFrames);
		}
		const blob = await sink.finish();
		sink = null;
		return blob;
	} finally {
		sink?.abort();
		map?.remove();
		host.remove();
	}
}
