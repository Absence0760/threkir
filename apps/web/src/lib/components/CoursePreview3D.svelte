<script lang="ts">
	import type * as GeoJSON from 'geojson';
	import { untrack } from 'svelte';
	import Modal from './Modal.svelte';
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import {
		PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV,
		PUBLIC_TERRAIN_URL as PUBLIC_TERRAIN_URL_ENV,
	} from '$app/env/public';
	import { formatDistance, formatElevation } from '#lib/format/units.svelte.ts';
	import { formatDecimal } from '#lib/format/number.ts';
	import {
		basemapIsDarkFromEnv,
		mapStyleUrlFromEnv as mapStyleUrl,
	} from '#lib/routes/map-style.svelte.ts';
	import {
		mapAccentColour,
		mapClimbLine,
		mapLabelHalo,
		mapLabelInk,
		mapOverlayOutline,
		mapTrackLine,
	} from '#lib/routes/basemap_contrast.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import {
		buildFlyoverPath,
		cameraAt,
		DEFAULT_FLYOVER_SPEED_MPS,
		distanceMarkers,
		FLYOVER_SPEEDS,
		pointAtDistance,
		type PathPoint,
	} from '#lib/routes/flyover_path.ts';
	import { detectClimbs, elevationStrip } from '#lib/routes/course_climbs.ts';
	import {
		FLYOVER_PITCH,
		resolveTerrainSource,
		TERRAIN_EXAGGERATION,
	} from '#lib/routes/terrain_source.ts';
	import {
		detectFlyoverCapability,
		flyoverMode,
		type FlyoverMode,
	} from '#lib/routes/flyover_capability.ts';
	import { play, seek, tick, type Playback } from './course_preview/playback.ts';
	import { distanceAtStripOffset, stripGeometry, stripX } from './course_preview/strip_geometry.ts';
	import { sliceCourse } from './course_preview/course_slice.ts';

	interface Props {
		open: boolean;
		points: PathPoint[];
		unit: 'km' | 'mi';
		title: string;
		climbNames?: { dM: number; name: string }[];
		/// Elevation noise band for climb detection; a recorded run passes its
		/// altitude source's `minDeltaM`. Omitted, climbs use the default band.
		noiseBandM?: number;
		onclose: () => void;
	}

	let { open, points, unit, title, climbNames, noiseBandM, onclose }: Props = $props();

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';
	const PUBLIC_TERRAIN_URL = PUBLIC_TERRAIN_URL_ENV ?? '';
	const TERRAIN_SOURCE_ID = 'course-terrain';
	const FLIGHT_ZOOM = 14;
	const STRIP_SAMPLES = 240;
	const STRIP_W = 1000;
	const STRIP_H = 64;
	// A background tab or a dropped frame must not teleport the camera down
	// the course when the clock resumes.
	const MAX_FRAME_MS = 100;

	// Same gate as RunMap: tile and terrain hosts log the requester IP, so
	// nothing is requested before consent is on record or the viewer taps
	// Load. Re-read on every open so a banner accepted meanwhile counts.
	let mapConsented = $state(untrack(() => hasAcceptedConsent()));
	$effect(() => {
		if (open && hasAcceptedConsent()) mapConsented = true;
	});

	const prefersDark =
		typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = $derived(basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDark));

	const path = $derived(buildFlyoverPath(points));
	const hasPath = $derived(path.points.length >= 2 && path.totalM > 0);
	const markers = $derived(hasPath ? distanceMarkers(path, unit) : []);
	const climbs = $derived(hasPath ? detectClimbs(path, { names: climbNames, noiseBandM }) : []);
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

	const here = $derived(hasPath ? pointAtDistance(path, playback.dM) : null);
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

	function initMap(container: HTMLDivElement) {
		if (map || !hasPath) return;
		mode = flyoverMode(detectFlyoverCapability(window));
		terrainFailed = false;
		mapFailed = false;
		playback = { dM: 0, playing: false };
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
			if ((e as { sourceId?: string }).sourceId === TERRAIN_SOURCE_ID) dropTerrain();
		});
		created.on('load', () => {
			addTerrain(created);
			addOverlays(created);
			frameCourse(created);
			renderPosition();
			if (mode === 'flight') {
				playback = play(playback, path.totalM);
				startLoop();
			}
		});
	}

	function teardown() {
		stopLoop();
		stopResizeWatch?.();
		stopResizeWatch = null;
		positionMarker?.remove();
		positionMarker = undefined;
		map?.remove();
		map = undefined;
	}

	function courseBounds(): [[number, number], [number, number]] {
		let minLng = Infinity;
		let minLat = Infinity;
		let maxLng = -Infinity;
		let maxLat = -Infinity;
		for (const p of path.points) {
			if (p.lng < minLng) minLng = p.lng;
			if (p.lng > maxLng) maxLng = p.lng;
			if (p.lat < minLat) minLat = p.lat;
			if (p.lat > maxLat) maxLat = p.lat;
		}
		return [
			[minLng, minLat],
			[maxLng, maxLat],
		];
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
			target.addSource(TERRAIN_SOURCE_ID, {
				type: 'raster-dem',
				tiles: source.tiles,
				encoding: source.encoding,
				tileSize: source.tileSize,
				maxzoom: source.maxzoom,
				attribution: source.attribution,
			});
			target.setTerrain({ source: TERRAIN_SOURCE_ID, exaggeration: TERRAIN_EXAGGERATION });
		} catch (e) {
			console.warn('course preview: terrain unavailable', e);
			dropTerrain();
		}
	}

	function dropTerrain() {
		if (terrainFailed) return;
		terrainFailed = true;
		try {
			map?.setTerrain(null);
		} catch (e) {
			console.warn('course preview: could not clear terrain', e);
		}
	}

	function addOverlays(target: maplibregl.Map) {
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

	function frameCourse(target: maplibregl.Map) {
		if (mode === 'flight') {
			applyCamera(target, playback.dM);
			return;
		}
		target.fitBounds(courseBounds(), { padding: 48, animate: false });
		if (mode === 'static3d' && !terrainFailed) target.setPitch(FLYOVER_PITCH);
	}

	function applyCamera(target: maplibregl.Map, dM: number) {
		const pose = cameraAt(path, dM);
		target.jumpTo({ center: pose.center, bearing: pose.bearing, pitch: FLYOVER_PITCH, zoom: FLIGHT_ZOOM });
	}

	function renderPosition() {
		if (!map || !here) return;
		const at: [number, number] = [here.lng, here.lat];
		if (!positionMarker) {
			const el = document.createElement('div');
			el.className = 'course-preview-position';
			positionMarker = new maplibregl.Marker({ element: el }).setLngLat(at).addTo(map);
		} else {
			positionMarker.setLngLat(at);
		}
		if (mode === 'flight') applyCamera(map, playback.dM);
	}

	function frame(ts: number) {
		raf = 0;
		if (!playback.playing) return;
		const elapsed = lastTs == null ? 0 : Math.min(ts - lastTs, MAX_FRAME_MS);
		lastTs = ts;
		playback = tick(playback, elapsed, speed, path.totalM);
		renderPosition();
		if (playback.playing) raf = requestAnimationFrame(frame);
	}

	function startLoop() {
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
		playback = { ...playback, playing: false };
	}

	function togglePlay() {
		if (playback.playing) {
			pause();
			return;
		}
		playback = play(playback, path.totalM);
		startLoop();
	}

	function seekTo(dM: number) {
		stopLoop();
		playback = seek(dM, path.totalM);
		renderPosition();
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

	function climbLabel(i: number): string {
		const c = climbs[i];
		return m('coursePreview.climbSummary', {
			name: c.name ?? m('coursePreview.climbUnnamed', { n: i + 1 }),
			gain: formatElevation(c.gainM),
			grade: m('coursePreview.grade', { value: formatDecimal(c.avgGradePct, 1, currentLocale()) }),
		});
	}

	function handleClose() {
		pause();
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
	<div class="preview" data-flyover-mode={mode}>
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
								done: formatDistance(playback.dM),
								total: formatDistance(path.totalM),
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
						<span>{formatDistance(playback.dM)}</span>
						{#if here?.ele != null}<span>{formatElevation(here.ele)}</span>{/if}
					</p>
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
	:global(.course-preview-position) {
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: var(--map-accent);
		border: 3px solid var(--map-outline);
		pointer-events: none;
	}
</style>
