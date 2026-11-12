<script lang="ts">
	import { untrack } from 'svelte';
	import Modal from './Modal.svelte';
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import {
		PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV,
		PUBLIC_TERRAIN_URL as PUBLIC_TERRAIN_URL_ENV,
		PUBLIC_TILE_STYLE_URL,
	} from '$app/env/public';
	import { formatDistance, formatElevation } from '#lib/format/units.svelte.ts';
	import { formatDecimal } from '#lib/format/number.ts';
	import {
		basemapIsDarkFromEnv,
		mapStyleUrlFromEnv as mapStyleUrl,
	} from '#lib/routes/map-style.svelte.ts';
	import { mapAccentColour, mapOverlayOutline } from '#lib/routes/basemap_contrast.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import {
		buildFlyoverPath,
		DEFAULT_FLYOVER_SPEED_MPS,
		distanceMarkers,
		FLYOVER_SPEEDS,
		pointAtDistance,
		type PathPoint,
	} from '#lib/routes/flyover_path.ts';
	import { courseDistanceScale } from '#lib/routes/official_distance.ts';
	import {
		courseReliefM,
		detectClimbs,
		elevationStrip,
		type Climb,
		type ClimbSource,
	} from '#lib/routes/course_climbs.ts';
	import {
		FLYOVER_PITCH,
		resolveTerrainSource,
		terrainExaggeration,
		type TerrainSource,
	} from '#lib/routes/terrain_source.ts';
	import { flyoverVideoMaptilerKey } from '#lib/routes/flyover_video_flag.ts';
	import { videoBasemapPermitted } from '#lib/routes/flyover_video_source.ts';
	import {
		detectFlyoverCapability,
		flyoverMode,
		type FlyoverMode,
	} from '#lib/routes/flyover_capability.ts';
	import { play, seek, tick, type Playback } from './course_preview/playback.ts';
	import { distanceAtStripOffset, stripGeometry, stripX } from './course_preview/strip_geometry.ts';
	import { addCourseLayers } from './course_preview/course_layers.ts';
	import { startFinishMarkers, type StartFinishLabels } from './course_preview/start_finish.ts';
	import {
		addCourseTerrain,
		HILLSHADE_SOURCE_ID,
		removeCourseTerrain,
		TERRAIN_SOURCE_ID,
	} from './course_preview/course_terrain.ts';
	import { drawFlightFrame, flightCamera } from './course_preview/flight_frame.ts';
	import {
		finaleCamera,
		finaleDurationMs,
		finalePlan,
		OVERVIEW_PADDING_PX,
		OVERVIEW_PITCH,
		overviewPose,
		pathBounds,
		type CameraPose,
		type FinalePlan,
	} from './course_preview/overview.ts';
	import { motion } from '#lib/motion/motion.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { loadMascotShown, peekMascotShown } from '#lib/mascot/mascot_pref.ts';
	import {
		advanceTrot,
		headingWindowM,
		mascotHeadingDeg,
		mascotPhase,
		mascotWanted,
		screenYawDeg,
	} from './course_preview/mascot/mascot_motion.ts';
	import type { MascotRenderer } from './course_preview/mascot/mascot_renderer.ts';
	import type { VideoEncoderPlan } from '#lib/video/video_encoder.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { DEFAULT_SITE_URL } from '#lib/core/site_url.ts';

	interface Props {
		open: boolean;
		points: PathPoint[];
		unit: 'km' | 'mi';
		title: string;
		climbNames?: { dM: number; name: string }[];
		/// Elevation noise band for climb detection; a recorded run passes its
		/// altitude source's `minDeltaM`. Omitted, climbs use the default band.
		noiseBandM?: number;
		/// A recorded run's altitude keeps the watch's noise-tolerant climb
		/// rule; a route or race course is read by the planned rule.
		climbSource: ClimbSource;
		/// The line the video export records. It leaves the page, so it must be
		/// a privacy-clipped source (`shareCardTrack`, `clip-public-track`,
		/// `clip_route_for_viewer`); null means the clip cannot be made yet and
		/// the export refuses. Omitted, the dialog offers no export.
		videoSource?: () => Promise<{ points: PathPoint[]; noiseBandM?: number } | null>;
		/// The end card's headline (the run's own distance and time, formatted
		/// as the page formats them); the drawn line's length otherwise.
		videoSummary?: string;
		/// Ask for the per-view "Load preview" tap even when the cookie banner
		/// was accepted, as `RunMap` does on the anonymous share pages.
		requireExplicitConsent?: boolean;
		/// The route's official distance. Set, every distance the dialog
		/// shows and every km marker is scaled from the drawn line to it.
		officialDistanceM?: number | null;
		onclose: () => void;
	}

	let {
		open,
		points,
		unit,
		title,
		climbNames,
		noiseBandM,
		climbSource,
		videoSource,
		videoSummary,
		requireExplicitConsent = false,
		officialDistanceM = null,
		onclose,
	}: Props = $props();

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';
	const PUBLIC_TERRAIN_URL = PUBLIC_TERRAIN_URL_ENV ?? '';
	const FLIGHT_ZOOM = 14;
	const FLIGHT_VIEW = { pitch: FLYOVER_PITCH, zoom: FLIGHT_ZOOM };
	const STRIP_SAMPLES = 240;
	const STRIP_W = 1000;
	const STRIP_H = 64;
	// A background tab or a dropped frame must not teleport the camera down
	// the course when the clock resumes.
	const MAX_FRAME_MS = 100;

	// Same gate as RunMap: tile and terrain hosts log the requester IP, so
	// nothing is requested before consent is on record or the viewer taps
	// Load. Re-read on every open so a banner accepted meanwhile counts,
	// except where the caller asks for the tap regardless.
	let mapConsented = $state(untrack(() => (requireExplicitConsent ? false : hasAcceptedConsent())));
	$effect(() => {
		if (open && !requireExplicitConsent && hasAcceptedConsent()) mapConsented = true;
	});

	const prefersDark =
		typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = $derived(basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDark));

	const path = $derived(buildFlyoverPath(points));
	const hasPath = $derived(path.points.length >= 2 && path.totalM > 0);
	const markers = $derived(hasPath ? distanceMarkers(path, unit, officialDistanceM) : []);
	const startFinishLabels = (): StartFinishLabels => ({
		start: m('coursePreview.markerStart'),
		finish: m('coursePreview.markerFinish'),
		startFinish: m('coursePreview.markerStartFinish'),
	});
	const courseScale = $derived(courseDistanceScale(path.totalM, officialDistanceM));
	const climbs = $derived(hasPath ? detectClimbs(path, { source: climbSource, names: climbNames, noiseBandM }) : []);
	const strip = $derived(hasPath ? elevationStrip(path, STRIP_SAMPLES) : []);
	const geometry = $derived(stripGeometry(strip, climbs, path.totalM, STRIP_W, STRIP_H));
	const hasElevation = $derived(geometry.line !== '');

	let mode = $state<FlyoverMode>('flat2d');
	let playback = $state<Playback>({ dM: 0, playing: false });
	let speed = $state(DEFAULT_FLYOVER_SPEED_MPS);
	let terrainFailed = $state(false);
	let mapFailed = $state(false);

	let mapContainer = $state<HTMLDivElement>();
	let map: maplibregl.Map | undefined;
	let positionMarker: maplibregl.Marker | undefined;
	let stopResizeWatch: (() => void) | null = null;
	let raf = 0;
	let lastTs: number | null = null;
	// The ending's own clock: the overview ease and orbit after the finish.
	let finaleRaf = 0;
	let finale: { from: CameraPose; to: CameraPose; plan: FinalePlan; startTs: number | null } | null = null;
	let atOverview = $state(false);

	// Grisnir in place of the dot (decisions § 2458): the viewer's universal
	// `show_mascot`, read when the dialog opens (null until it lands, so a
	// viewer who hid him never sees him flash in), and his own WebGL canvas,
	// loaded only once the map is up. Auxiliary: any failure keeps the dot.
	let showMascot = $state<boolean | null>(null);
	let mascot: MascotRenderer | null = null;
	let mascotLoading = false;
	let mascotFailed = false;
	let mascotBoxPx = 0;
	let positionKind = $state<'dot' | 'mascot'>('dot');
	let trotPhase = 0;
	let mapLoaded = $state(false);
	// Set by the viewer's own Play, Pause or seek. The style's `load` can land
	// after any of those on a slow device, and must not restart a flight the
	// viewer already moved, or cancel the ending of one that already finished.
	let viewerDrove = false;

	const here = $derived(hasPath ? pointAtDistance(path, playback.dM) : null);

	// The export never uses a MapTiler key until the operator has confirmed
	// the plan allows MapTiler in published video (decisions § 2259).
	const videoKey = flyoverVideoMaptilerKey(PUBLIC_MAPTILER_KEY);
	const videoBasemapOk = videoBasemapPermitted(videoKey, PUBLIC_TILE_STYLE_URL);
	type VideoState =
		| { step: 'idle' }
		| { step: 'rendering'; progress: number }
		| { step: 'ready'; blob: Blob };
	let encoderPlan = $state<VideoEncoderPlan | null>(null);
	let video = $state<VideoState>({ step: 'idle' });
	let videoAbort: AbortController | null = null;
	const canExportVideo = $derived(
		videoBasemapOk && !!videoSource && mode !== 'flat2d' && !mapFailed && encoderPlan !== null,
	);
	const cursorX = $derived(stripX(playback.dM, path.totalM, STRIP_W));

	$effect(() => {
		const container = mapContainer;
		if (!open || !mapConsented || !container) return;
		untrack(() => initMap(container));
		return () => untrack(teardown);
	});

	$effect(() => {
		if (!open) return;
		const onVisibility = () => {
			if (document.hidden) pause();
		};
		document.addEventListener('visibilitychange', onVisibility);
		return () => document.removeEventListener('visibilitychange', onVisibility);
	});

	$effect(() => {
		if (!open) return;
		const signedIn = auth.user != null;
		untrack(() => void readShowMascot(signedIn));
	});

	// A logged-out viewer has no setting, and his default is on. A signed-in
	// one whose settings cannot be read at all keeps the dot.
	async function readShowMascot(signedIn: boolean) {
		if (!signedIn) {
			showMascot = true;
			return;
		}
		showMascot = peekMascotShown();
		showMascot = (await loadMascotShown()) ?? false;
	}

	$effect(() => {
		if (!open || !mapLoaded || showMascot === null) return;
		const want = mascotWanted(showMascot, mode);
		untrack(() => {
			if (want) void startMascot();
			else useDot();
		});
	});

	async function startMascot() {
		if (mascot || mascotLoading || mascotFailed) {
			if (mascot) useMascot();
			return;
		}
		mascotLoading = true;
		try {
			const { loadMascot, MASCOT_BOX_CSS_PX } = await import('./course_preview/mascot/mascot_renderer.ts');
			const canvas = document.createElement('canvas');
			mascotBoxPx = MASCOT_BOX_CSS_PX;
			canvas.style.width = canvas.style.height = `${MASCOT_BOX_CSS_PX}px`;
			const loaded = await loadMascot(canvas);
			if (!loaded) {
				mascotFailed = true;
				return;
			}
			if (!map || !open) {
				loaded.dispose();
				return;
			}
			// dispose() loses the context on purpose, and the event lands after
			// teardown has moved on; only a loss on the live renderer is a failure.
			canvas.addEventListener('webglcontextlost', () => {
				if (mascot !== loaded) return;
				mascotFailed = true;
				useDot();
			});
			mascot = loaded;
			useMascot();
		} catch (e) {
			console.warn('course preview: Grisnir unavailable, keeping the dot', e);
			mascotFailed = true;
		} finally {
			mascotLoading = false;
		}
	}

	function useMascot() {
		const el = positionMarker?.getElement();
		if (!mascot || !el || !showMascot) return;
		if (!el.contains(mascot.canvas)) el.appendChild(mascot.canvas);
		// classList, not className: MapLibre's own marker classes position it.
		el.classList.replace('course-preview-position', 'course-preview-mascot');
		positionKind = 'mascot';
		drawMascot();
	}

	function useDot() {
		const el = positionMarker?.getElement();
		mascot?.canvas.remove();
		el?.classList.replace('course-preview-mascot', 'course-preview-position');
		positionKind = 'dot';
	}

	// Drawn on every map render, so his heading follows the camera's bearing
	// in the flight, the ending's orbit and a viewer's own drag alike.
	function drawMascot() {
		if (positionKind !== 'mascot' || !mascot || !map || !hasPath) return;
		try {
			if (!mascot.usable) throw new Error('WebGL context lost');
			const heading = mascotHeadingDeg(path, playback.dM, headingWindowM(speed));
			mascot.setSize(mascotBoxPx * (window.devicePixelRatio || 1));
			mascot.draw({
				yawDeg: screenYawDeg(heading, map.getBearing()),
				pitchDeg: map.getPitch(),
				phase: mascotPhase(mode, playback.playing, trotPhase),
			});
		} catch (e) {
			console.warn('course preview: Grisnir frame failed, keeping the dot', e);
			mascotFailed = true;
			useDot();
		}
	}

	function initMap(container: HTMLDivElement) {
		if (map || !hasPath) return;
		mode = flyoverMode(detectFlyoverCapability(window));
		if (videoBasemapOk && videoSource && mode !== 'flat2d') void probeEncoder();
		terrainFailed = false;
		mapFailed = false;
		playback = { dM: 0, playing: false };
		viewerDrove = false;
		mapLoaded = false;
		trotPhase = 0;
		try {
			map = new maplibregl.Map({
				container,
				style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
				bounds: courseBounds(),
				fitBoundsOptions: { padding: 48 },
				keyboard: false,
				maxPitch: 85,
			});
		} catch (e) {
			console.warn('course preview: map failed to start', e);
			mapFailed = true;
			return;
		}
		const created = map;
		// The canvas sits under an aria-hidden container; the dialog's own
		// controls are the keyboard path, so the canvas stays out of the Tab ring.
		created.getCanvas().tabIndex = -1;
		stopResizeWatch = watchMapResize(container, created);
		created.on('webglcontextlost', () => {
			pause();
			mapFailed = true;
		});
		created.on('error', (e) => {
			const sourceId = (e as { sourceId?: string }).sourceId;
			if (sourceId === TERRAIN_SOURCE_ID || sourceId === HILLSHADE_SOURCE_ID) dropTerrain();
		});
		created.on('render', drawMascot);
		created.on('load', () => {
			addTerrain(created);
			addCourseLayers(created, {
				path,
				climbs,
				markers,
				startFinish: startFinishMarkers(path, startFinishLabels()),
				darkBasemap,
			});
			frameCourse(created);
			renderPosition();
			mapLoaded = true;
			if (mode === 'flight' && !viewerDrove) {
				playback = play(playback, path.totalM);
				startLoop();
			}
		});
	}

	function teardown() {
		cancelVideo();
		stopLoop();
		stopFinale();
		stopResizeWatch?.();
		stopResizeWatch = null;
		mapLoaded = false;
		const disposing = mascot;
		mascot = null;
		disposing?.dispose();
		positionKind = 'dot';
		positionMarker?.remove();
		positionMarker = undefined;
		map?.remove();
		map = undefined;
	}

	function courseBounds(): [[number, number], [number, number]] {
		return pathBounds(path);
	}

	// Terrain is an auxiliary layer: any failure to add it, or a tile error
	// after, drops back to the flat course rather than taking the map down.
	function addTerrain(target: maplibregl.Map) {
		if (mode === 'flat2d') return;
		try {
			const source = resolveTerrainSource({
				maptilerKey: PUBLIC_MAPTILER_KEY,
				override: PUBLIC_TERRAIN_URL,
			});
			addCourseTerrain(target, source, {
				exaggeration: terrainExaggeration(courseReliefM(path)),
				darkBasemap,
			});
		} catch (e) {
			console.warn('course preview: terrain unavailable', e);
			dropTerrain();
		}
	}

	function dropTerrain() {
		if (terrainFailed) return;
		terrainFailed = true;
		if (map) removeCourseTerrain(map);
	}

	function frameCourse(target: maplibregl.Map) {
		if (mode === 'flight') {
			applyCamera(target, playback.dM);
			return;
		}
		target.fitBounds(courseBounds(), { padding: 48, animate: false });
		if (mode === 'static3d' && !terrainFailed) target.setPitch(FLYOVER_PITCH);
	}

	function applyCamera(target: maplibregl.Map, dM: number) {
		target.jumpTo(flightCamera(path, dM, FLIGHT_VIEW, speed));
	}

	function renderPosition(inAnimationFrame = false) {
		if (!map || !here) return;
		const at: [number, number] = [here.lng, here.lat];
		if (!positionMarker) {
			const el = document.createElement('div');
			el.className = 'course-preview-position';
			el.dataset.testid = 'course-preview-position';
			// Without it MapLibre rounds the dot to whole pixels, flipping it on half-pixel centres.
			positionMarker = new maplibregl.Marker({ element: el, subpixelPositioning: true })
				.setLngLat(at)
				.addTo(map);
		}
		if (mode === 'flight') {
			drawFlightFrame(map, positionMarker, path, playback.dM, FLIGHT_VIEW, speed, inAnimationFrame);
		} else {
			positionMarker.setLngLat(at);
		}
	}

	function frame(ts: number) {
		raf = 0;
		if (!playback.playing) return;
		const elapsed = lastTs == null ? 0 : Math.min(ts - lastTs, MAX_FRAME_MS);
		lastTs = ts;
		playback = tick(playback, elapsed, speed, path.totalM);
		trotPhase = advanceTrot(trotPhase, elapsed, speed);
		renderPosition(true);
		if (playback.playing) raf = requestAnimationFrame(frame);
		else if (playback.dM >= path.totalM) startFinale();
	}

	// Auxiliary to the flight: a failure here leaves the camera at the finish.
	function startFinale() {
		if (!map || !here) return;
		try {
			const fit = map.cameraForBounds(courseBounds(), {
				padding: OVERVIEW_PADDING_PX,
				bearing: 0,
				pitch: OVERVIEW_PITCH,
			});
			if (!fit?.center || fit.zoom == null) return;
			const c = maplibregl.LngLat.convert(fit.center);
			finale = {
				from: flightCamera(path, path.totalM, FLIGHT_VIEW, speed),
				to: overviewPose({ center: [c.lng, c.lat], zoom: fit.zoom }),
				plan: finalePlan(motion.reduced),
				startTs: null,
			};
			finaleRaf = requestAnimationFrame(finaleFrame);
		} catch (e) {
			console.warn('course preview: overview unavailable', e);
			stopFinale();
		}
	}

	function finaleFrame(ts: number) {
		finaleRaf = 0;
		const f = finale;
		if (!f || !map) return;
		f.startTs ??= ts;
		const t = ts - f.startTs;
		try {
			map.jumpTo(finaleCamera(f.from, f.to, t, f.plan));
			map.redraw();
		} catch (e) {
			console.warn('course preview: overview frame failed', e);
			stopFinale();
			return;
		}
		if (t >= finaleDurationMs(f.plan)) {
			finale = null;
			atOverview = true;
			return;
		}
		finaleRaf = requestAnimationFrame(finaleFrame);
	}

	// A hidden tab or a close mid-ending lands on the ending's last pose
	// rather than freezing half way out.
	function settleFinale() {
		const f = finale;
		if (!f) return;
		stopFinale();
		try {
			map?.jumpTo(finaleCamera(f.from, f.to, finaleDurationMs(f.plan), f.plan));
			atOverview = true;
		} catch (e) {
			console.warn('course preview: overview frame failed', e);
		}
	}

	function stopFinale() {
		if (finaleRaf) cancelAnimationFrame(finaleRaf);
		finaleRaf = 0;
		finale = null;
		atOverview = false;
	}

	function startLoop() {
		stopFinale();
		if (raf) return;
		lastTs = null;
		raf = requestAnimationFrame(frame);
	}

	function stopLoop() {
		if (raf) cancelAnimationFrame(raf);
		raf = 0;
		lastTs = null;
	}

	function pause() {
		stopLoop();
		settleFinale();
		playback = { ...playback, playing: false };
		drawMascot();
	}

	function togglePlay() {
		viewerDrove = true;
		if (playback.playing) {
			pause();
			return;
		}
		playback = play(playback, path.totalM);
		startLoop();
	}

	function seekTo(dM: number) {
		viewerDrove = true;
		stopLoop();
		stopFinale();
		playback = seek(dM, path.totalM);
		renderPosition();
		drawMascot();
	}

	let stripEl = $state<SVGSVGElement>();
	let dragging = false;

	function scrubFromPointer(e: PointerEvent) {
		if (!stripEl) return;
		const rect = stripEl.getBoundingClientRect();
		seekTo(distanceAtStripOffset(e.clientX - rect.left, rect.width, path.totalM));
	}

	function speedFactor(mps: number): string {
		const f = mps / DEFAULT_FLYOVER_SPEED_MPS;
		return m('coursePreview.speedOption', {
			factor: formatDecimal(f, Number.isInteger(f) ? 0 : 1, currentLocale()),
		});
	}

	function climbLabel(i: number, list: readonly Climb[] = climbs): string {
		const c = list[i];
		return m('coursePreview.climbSummary', {
			name: c.name ?? m('coursePreview.climbUnnamed', { n: i + 1 }),
			gain: formatElevation(c.gainM),
			grade: m('coursePreview.grade', { value: formatDecimal(c.avgGradePct, 1, currentLocale()) }),
		});
	}

	async function probeEncoder() {
		try {
			const { pickVideoEncoder } = await import('#lib/video/encode_video.ts');
			encoderPlan = await pickVideoEncoder();
		} catch (e) {
			console.warn('course preview: no video encoder', e);
			encoderPlan = null;
		}
	}

	function videoTerrain(): TerrainSource | null {
		if (mode === 'flat2d' || terrainFailed) return null;
		try {
			return resolveTerrainSource({ maptilerKey: videoKey, override: PUBLIC_TERRAIN_URL });
		} catch (e) {
			console.warn('course preview: video terrain unavailable', e);
			return null;
		}
	}

	async function exportVideo() {
		const plan = encoderPlan;
		if (!plan || !videoSource || video.step === 'rendering') return;
		pause();
		const abort = new AbortController();
		videoAbort = abort;
		video = { step: 'rendering', progress: 0 };
		try {
			const source = await videoSource();
			if (!source) {
				showToast(m('coursePreview.videoZonesUnknown'), 'error');
				video = { step: 'idle' };
				return;
			}
			const vPath = buildFlyoverPath(source.points);
			if (vPath.points.length < 2 || !(vPath.totalM > 0)) {
				showToast(m('coursePreview.videoNoLine'), 'error');
				video = { step: 'idle' };
				return;
			}
			const vClimbs = detectClimbs(vPath, {
				source: climbSource,
				names: climbNames,
				noiseBandM: source.noiseBandM ?? noiseBandM,
			});
			const vScale = courseDistanceScale(vPath.totalM, officialDistanceM);
			const { renderFlyoverVideo } = await import('./course_preview/flyover_video_export.ts');
			const blob = await renderFlyoverVideo({
				path: vPath,
				unit,
				officialDistanceM,
				climbs: vClimbs,
				strip: elevationStrip(vPath, STRIP_SAMPLES),
				maptilerKey: videoKey,
				terrain: videoTerrain(),
				exaggeration: terrainExaggeration(courseReliefM(vPath)),
				text: {
					title,
					distanceAt: (dM) => formatDistance(dM * vScale),
					ofTotal: m('coursePreview.videoOfTotal', { total: formatDistance(vPath.totalM * vScale) }),
					elevationAt: (ele) => formatElevation(ele),
					climbLabel: (i) => climbLabel(i, vClimbs),
					startFinish: startFinishLabels(),
					endLines: [videoSummary ?? formatDistance(vPath.totalM * vScale), title],
					url: new URL(DEFAULT_SITE_URL).host,
				},
				showMascot: showMascot === true,
				plan,
				signal: abort.signal,
				onprogress: (f) => {
					if (videoAbort === abort) video = { step: 'rendering', progress: f };
				},
			});
			if (videoAbort !== abort) return;
			video = { step: 'ready', blob };
		} catch (e) {
			if (videoAbort !== abort) return;
			video = { step: 'idle' };
			if ((e as { name?: string })?.name === 'AbortError') return;
			console.error('course preview: video export failed', e);
			showToast(m('coursePreview.videoFailed'), 'error');
		} finally {
			if (videoAbort === abort) videoAbort = null;
		}
	}

	function cancelVideo() {
		videoAbort?.abort();
		videoAbort = null;
		video = { step: 'idle' };
	}

	async function saveVideo() {
		if (video.step !== 'ready') return;
		const { blob } = video;
		try {
			const { deliverVideo } = await import('#lib/video/encode_video.ts');
			const how = await deliverVideo(blob, title, title);
			if (how === 'downloaded') showToast(m('coursePreview.videoSaved'), 'success');
		} catch (e) {
			if ((e as { name?: string })?.name === 'AbortError') return;
			console.error('course preview: video share failed', e);
			showToast(m('coursePreview.videoFailed'), 'error');
		}
	}

	function handleClose() {
		pause();
		cancelVideo();
		onclose();
	}
</script>

<Modal
	{open}
	onclose={handleClose}
	title={m('coursePreview.dialogTitle', { title })}
	fullscreen
	data-testid="course-preview-3d"
>
	<div
		class="preview"
		data-flyover-mode={mode}
		data-flyover-overview={atOverview ? '' : undefined}
		data-position-marker={positionKind}
	>
		{#if !hasPath}
			<p class="preview-empty">{m('coursePreview.noTrack')}</p>
		{:else if !mapConsented}
			<div class="preview-consent">
				<div class="preview-consent-card">
					<h3>{m('coursePreview.consentTitle')}</h3>
					<p>
						{m('coursePreview.consentBody')}<a href="/cookie-notice">{m('coursePreview.consentLink')}</a>{m(
							'coursePreview.consentSuffix',
						)}
					</p>
					<button
						type="button"
						class="btn btn-primary"
						data-testid="course-preview-load"
						onclick={() => (mapConsented = true)}
					>
						{m('coursePreview.loadMap')}
					</button>
				</div>
			</div>
		{:else}
			<div
				class="preview-map-wrap"
				role="region"
				aria-label={m('coursePreview.mapLabel')}
				style:--map-accent={mapAccentColour(darkBasemap)}
				style:--map-outline={mapOverlayOutline(darkBasemap)}
			>
				<div bind:this={mapContainer} class="preview-map" aria-hidden="true"></div>
				{#if mapFailed}
					<p class="preview-note preview-note-error" role="status">{m('coursePreview.mapFailed')}</p>
				{:else if terrainFailed}
					<p class="preview-note" role="status">{m('coursePreview.terrainFailed')}</p>
				{:else if mode === 'static3d'}
					<p class="preview-note" role="status">{m('coursePreview.reducedMotion')}</p>
				{:else if mode === 'flat2d'}
					<p class="preview-note" role="status">{m('coursePreview.flatFallback')}</p>
				{/if}
			</div>

			<div class="preview-panel">
				{#if hasElevation}
					<svg
						bind:this={stripEl}
						class="preview-strip"
						viewBox="0 0 {STRIP_W} {STRIP_H}"
						preserveAspectRatio="none"
						role="img"
						aria-label={m('coursePreview.stripLabel')}
						data-testid="course-preview-strip"
						onpointerdown={(e) => {
							dragging = true;
							stripEl?.setPointerCapture(e.pointerId);
							scrubFromPointer(e);
						}}
						onpointermove={(e) => {
							if (dragging) scrubFromPointer(e);
						}}
						onpointerup={() => (dragging = false)}
						onpointercancel={() => (dragging = false)}
					>
						{#each geometry.climbs as c, i (i)}
							<rect class="strip-climb" x={c.x0} y="0" width={Math.max(c.x1 - c.x0, 1)} height={STRIP_H} />
						{/each}
						<path class="strip-area" d={geometry.area} />
						<path class="strip-line" d={geometry.line} vector-effect="non-scaling-stroke" />
						<line
							class="strip-cursor"
							x1={cursorX}
							x2={cursorX}
							y1="0"
							y2={STRIP_H}
							vector-effect="non-scaling-stroke"
						/>
					</svg>
				{/if}

				<div class="preview-controls">
					{#if mode === 'flight'}
						<button
							type="button"
							class="btn btn-primary preview-play"
							data-testid="course-preview-play"
							onclick={togglePlay}
							disabled={mapFailed}
						>
							<span class="material-symbols" aria-hidden="true">{playback.playing ? 'pause' : 'play_arrow'}</span>
							{playback.playing ? m('coursePreview.pause') : m('coursePreview.play')}
						</button>
					{/if}
					<label class="preview-scrub">
						<span class="visually-hidden">{m('coursePreview.scrubLabel')}</span>
						<input
							type="range"
							min="0"
							max={path.totalM}
							step="any"
							dir="ltr"
							value={playback.dM}
							aria-valuetext={m('coursePreview.scrubValue', {
								done: formatDistance(playback.dM * courseScale),
								total: formatDistance(path.totalM * courseScale),
							})}
							data-testid="course-preview-scrub"
							oninput={(e) => seekTo(Number(e.currentTarget.value))}
						/>
					</label>
					{#if mode === 'flight'}
						<label class="preview-speed">
							<span>{m('coursePreview.speedLabel')}</span>
							<select bind:value={speed} data-testid="course-preview-speed">
								{#each FLYOVER_SPEEDS as s (s)}
									<option value={s}>{speedFactor(s)}</option>
								{/each}
							</select>
						</label>
					{/if}
					<p class="preview-readout" data-testid="course-preview-readout">
						<span>{formatDistance(playback.dM * courseScale)}</span>
						{#if here?.ele != null}<span>{formatElevation(here.ele)}</span>{/if}
					</p>
					{#if canExportVideo}
						{#if video.step === 'idle'}
							<button
								type="button"
								class="btn btn-outline btn-sm preview-video"
								data-testid="course-preview-export-video"
								onclick={exportVideo}
							>
								<span class="material-symbols" aria-hidden="true">movie</span>
								{m('coursePreview.exportVideo')}
							</button>
						{:else if video.step === 'rendering'}
							<p class="preview-video-status" role="status" data-testid="course-preview-video-progress">
								{m('coursePreview.videoRendering', { percent: Math.floor(video.progress * 100) })}
							</p>
							<button type="button" class="btn btn-outline btn-sm" onclick={cancelVideo}>
								{m('coursePreview.videoCancel')}
							</button>
						{:else}
							<p class="preview-video-status" role="status">{m('coursePreview.videoReady')}</p>
							<button
								type="button"
								class="btn btn-primary btn-sm preview-video"
								data-testid="course-preview-save-video"
								onclick={saveVideo}
							>
								<span class="material-symbols" aria-hidden="true">ios_share</span>
								{m('coursePreview.videoSave')}
							</button>
							<button type="button" class="btn btn-outline btn-sm" onclick={cancelVideo}>
								{m('coursePreview.videoDismiss')}
							</button>
						{/if}
					{/if}
				</div>

				{#if climbs.length > 0}
					<section class="preview-climbs" aria-labelledby="course-preview-climbs-heading">
						<h3 id="course-preview-climbs-heading">{m('coursePreview.climbsHeading')}</h3>
						<ul>
							{#each climbs as c, i (c.startM)}
								<li>
									<button
										type="button"
										class="preview-climb"
										data-testid="course-preview-climb"
										onclick={() => seekTo(c.startM)}
									>
										{climbLabel(i)}
									</button>
								</li>
							{/each}
						</ul>
					</section>
				{/if}
			</div>
		{/if}
	</div>
</Modal>

<style>
	.preview {
		display: flex;
		flex-direction: column;
		height: 100%;
		min-height: 0;
	}
	.preview-empty {
		margin: auto;
		padding: var(--space-lg);
		color: var(--color-text-secondary);
	}
	.preview-consent {
		display: flex;
		flex: 1;
		align-items: center;
		justify-content: center;
		padding: var(--space-md);
		background: var(--color-bg);
	}
	.preview-consent-card {
		max-width: 30rem;
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.preview-consent-card h3 {
		margin: 0 0 var(--space-sm);
		font-size: 1.05rem;
	}
	.preview-consent-card p {
		margin: 0 0 var(--space-md);
		color: var(--color-text-secondary);
		line-height: 1.5;
		font-size: 0.92rem;
	}
	.preview-map-wrap {
		position: relative;
		flex: 1;
		min-height: 12rem;
	}
	.preview-map {
		position: absolute;
		inset: 0;
	}
	.preview-note {
		position: absolute;
		top: var(--space-sm);
		inset-inline-start: var(--space-sm);
		max-width: min(28rem, calc(100% - 2 * var(--space-sm)));
		margin: 0;
		padding: var(--space-xs) var(--space-sm);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		color: var(--color-text);
		font-size: 0.82rem;
		line-height: 1.4;
	}
	.preview-note-error {
		color: var(--color-danger-text);
	}
	.preview-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md) var(--space-md);
		border-top: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.preview-strip {
		display: block;
		width: 100%;
		height: 4rem;
		cursor: pointer;
		touch-action: none;
	}
	.strip-area {
		fill: color-mix(in srgb, var(--color-primary) 18%, transparent);
	}
	.strip-line {
		fill: none;
		stroke: var(--color-primary);
		stroke-width: 2;
	}
	.strip-climb {
		fill: color-mix(in srgb, var(--color-accent-pink) 22%, transparent);
	}
	.strip-cursor {
		stroke: var(--color-text);
		stroke-width: 2;
	}
	.preview-controls {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
	}
	.preview-play {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.preview-scrub {
		flex: 1 1 12rem;
		display: flex;
	}
	.preview-scrub input {
		width: 100%;
		accent-color: var(--color-primary);
	}
	.preview-speed {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.preview-readout {
		display: flex;
		gap: var(--space-sm);
		margin: 0;
		font-size: 0.9rem;
		font-variant-numeric: tabular-nums;
		color: var(--color-text);
	}
	.preview-video {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.preview-video-status {
		margin: 0;
		font-size: 0.85rem;
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
	}
	.preview-climbs h3 {
		margin: 0 0 var(--space-xs);
		font-size: var(--font-size-section-label);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-secondary);
	}
	.preview-climbs ul {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.preview-climb {
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-accent-pink);
		border-radius: 999px;
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.82rem;
		cursor: pointer;
	}
	.preview-climb:hover {
		background: var(--color-bg-tertiary);
	}
	:global(.course-preview-mascot) {
		pointer-events: none;
		line-height: 0;
	}
	:global(.course-preview-position) {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: var(--map-accent);
		border: 3px solid var(--map-outline);
		pointer-events: none;
	}
</style>
