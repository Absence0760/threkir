<script lang="ts">
	// Every course line of one park on one map (issue #1352), with each
	// distinct start area marked. Pointing at a course in the list beside it
	// (`highlightId`) draws that line in the accent colour over the rest; a
	// previewed course (`selectedId`) is drawn the same way, the others fade,
	// the map frames it and its start and finish are pinned.
	//
	// The camera frames the lines whenever the map's box changes size, until
	// the reader moves the map themselves: a fit taken against a box that was
	// still settling (the consent swap, a sticky column, a phone's toolbar)
	// otherwise kept the old zoom and left the park a squiggle in a corner.
	import { onDestroy, untrack } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv, mapStyleUrlFromEnv as mapStyleUrl } from '#lib/routes/map-style.svelte.ts';
	import {
		mapAccentColour,
		mapFinishColour,
		mapOverlayOutline,
		mapStartColour,
		mapTrackLine,
	} from '#lib/routes/basemap_contrast.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import { distinctStarts, type LatLng } from '#lib/parks/course_map.ts';
	import { boundsOf } from '#lib/parks/course_preview.ts';

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';

	interface Props {
		courses: { id: string; points: LatLng[] }[];
		highlightId?: string | null;
		/** The previewed course: framed, drawn over faded others, its ends pinned. */
		selectedId?: string | null;
		/** Where the previewed course starts and finishes; `finish` null when it is the start. */
		selectedEnds?: { start: LatLng; finish: LatLng | null } | null;
		label: string;
		testid?: string;
	}

	let { courses, highlightId = null, selectedId = null, selectedEnds = null, label, testid }: Props = $props();

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDark);

	let consented = $state(untrack(() => hasAcceptedConsent()));
	let container: HTMLDivElement | undefined = $state();
	let map: maplibregl.Map | null = null;
	let ready = false;
	let stopResize: (() => void) | null = null;
	// Set once the reader drags, zooms or rotates; from then on the camera is theirs.
	let readerMoved = false;
	let endMarkers: maplibregl.Marker[] = [];
	const reducedMotion =
		typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

	function linesData(): GeoJSON.FeatureCollection<GeoJSON.LineString, { id: string }> {
		return {
			type: 'FeatureCollection',
			features: courses
				.filter((c) => c.points.length >= 2)
				.map((c) => ({
					type: 'Feature',
					properties: { id: c.id },
					geometry: { type: 'LineString', coordinates: c.points.map((p) => [p.lng, p.lat]) },
				})),
		};
	}

	function startsData(): GeoJSON.FeatureCollection<GeoJSON.Point> {
		return {
			type: 'FeatureCollection',
			features: distinctStarts(courses.map((c) => c.points)).map((s) => ({
				type: 'Feature',
				properties: {},
				geometry: { type: 'Point', coordinates: [s.lng, s.lat] },
			})),
		};
	}

	function paintHighlight() {
		if (!map || !ready) return;
		const id = selectedId ?? highlightId ?? '';
		map.setFilter('park-course-highlight', ['==', ['get', 'id'], id]);
		map.setFilter('park-course-highlight-casing', ['==', ['get', 'id'], id]);
		map.setPaintProperty('park-course-lines', 'line-opacity', selectedId ? 0.3 : highlightId ? 0.45 : 0.9);
		map.setPaintProperty('park-course-casing', 'line-opacity', selectedId ? 0.15 : 0.35);
		map.setLayoutProperty('park-course-starts', 'visibility', selectedId ? 'none' : 'visible');
	}

	function pinEnds() {
		for (const marker of endMarkers) marker.remove();
		endMarkers = [];
		if (!map || !ready || !selectedId || !selectedEnds) return;
		const { start, finish } = selectedEnds;
		if (finish) {
			endMarkers.push(new maplibregl.Marker({ color: mapStartColour(darkBasemap) }).setLngLat([start.lng, start.lat]).addTo(map));
			endMarkers.push(new maplibregl.Marker({ color: mapFinishColour(darkBasemap) }).setLngLat([finish.lng, finish.lat]).addTo(map));
		} else {
			endMarkers.push(new maplibregl.Marker({ color: mapFinishColour(darkBasemap) }).setLngLat([start.lng, start.lat]).addTo(map));
		}
	}

	function draw() {
		if (!map || !ready) return;
		const lines = map.getSource('park-courses') as maplibregl.GeoJSONSource | undefined;
		const starts = map.getSource('park-course-starts') as maplibregl.GeoJSONSource | undefined;
		if (lines && starts) {
			lines.setData(linesData());
			starts.setData(startsData());
		} else {
			map.addSource('park-courses', { type: 'geojson', data: linesData() });
			map.addSource('park-course-starts', { type: 'geojson', data: startsData() });
			map.addLayer({
				id: 'park-course-casing',
				type: 'line',
				source: 'park-courses',
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapOverlayOutline(darkBasemap), 'line-width': 6, 'line-opacity': 0.35 },
			});
			map.addLayer({
				id: 'park-course-lines',
				type: 'line',
				source: 'park-courses',
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapTrackLine(darkBasemap), 'line-width': 3.5, 'line-opacity': 0.9 },
			});
			map.addLayer({
				id: 'park-course-highlight-casing',
				type: 'line',
				source: 'park-courses',
				filter: ['==', ['get', 'id'], ''],
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapOverlayOutline(darkBasemap), 'line-width': 9 },
			});
			map.addLayer({
				id: 'park-course-highlight',
				type: 'line',
				source: 'park-courses',
				filter: ['==', ['get', 'id'], ''],
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapAccentColour(darkBasemap), 'line-width': 5.5 },
			});
			map.addLayer({
				id: 'park-course-starts',
				type: 'circle',
				source: 'park-course-starts',
				paint: {
					'circle-radius': 7,
					'circle-color': mapStartColour(darkBasemap),
					'circle-stroke-color': mapOverlayOutline(darkBasemap),
					'circle-stroke-width': 2,
				},
			});
		}
		paintHighlight();
	}

	/** Frames the previewed course, or every course; animated only when the reader asked for it. */
	function frame(animate: boolean) {
		if (!map) return;
		const box = map.getContainer();
		if (box.clientWidth === 0 || box.clientHeight === 0) return;
		const picked = selectedId ? courses.filter((c) => c.id === selectedId) : [];
		const bounds = boundsOf((picked.length > 0 ? picked : courses).map((c) => c.points));
		if (!bounds) return;
		const pad = Math.max(12, Math.min(40, Math.round(Math.min(box.clientWidth, box.clientHeight) / 10)));
		map.fitBounds(bounds, { padding: pad, maxZoom: 16, duration: animate && !reducedMotion ? 600 : 0 });
	}

	$effect(() => {
		if (!consented || !container || map) return;
		map = new maplibregl.Map({
			container,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: [0, 0],
			zoom: 1,
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
		stopResize = watchMapResize(container, map);
		for (const kind of ['dragstart', 'zoomstart', 'rotatestart', 'pitchstart'] as const) {
			map.on(kind, (e: { originalEvent?: Event }) => {
				if (e.originalEvent) readerMoved = true;
			});
		}
		map.on('resize', () => {
			if (!readerMoved) frame(false);
		});
		map.on('load', () => {
			ready = true;
			draw();
			pinEnds();
			frame(false);
		});
	});

	$effect(() => {
		void courses;
		untrack(() => {
			draw();
			frame(false);
		});
	});

	$effect(() => {
		void highlightId;
		untrack(paintHighlight);
	});

	$effect(() => {
		void selectedId;
		void selectedEnds;
		untrack(() => {
			readerMoved = false;
			paintHighlight();
			pinEnds();
			frame(true);
		});
	});

	onDestroy(() => {
		stopResize?.();
		for (const marker of endMarkers) marker.remove();
		map?.remove();
	});
</script>

{#if consented}
	<div
		class="park-courses-map"
		bind:this={container}
		role="img"
		aria-label={label}
		data-testid={testid}
		data-selected={selectedId ?? undefined}
	></div>
{:else}
	<!-- audit/cookie-consent: MapTiler logs the requester IP per tile fetch, so
	     the map waits for consent or an explicit "Load map", as RunMap does. -->
	<div class="park-courses-consent" data-testid={testid ? `${testid}-consent` : undefined}>
		<p>
			{m('runMap.consentPrefix')}<strong>MapTiler</strong>{m('runMap.consentMiddle')}<strong>{m('runMap.loadMap')}</strong>{m('runMap.consentBeforeLink')}<a href="/cookie-notice">{m('runMap.cookieNotice')}</a>{m('runMap.consentSuffix')}
		</p>
		<button type="button" class="btn btn-secondary btn-sm" onclick={() => (consented = true)}>
			{m('runMap.loadMap')}
		</button>
	</div>
{/if}

<style>
	.park-courses-map {
		width: 100%;
		height: 100%;
		min-height: 14rem;
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.park-courses-consent {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
		min-height: 12rem;
		padding: var(--space-md);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
	}
	.park-courses-consent p {
		margin: 0;
	}
</style>
