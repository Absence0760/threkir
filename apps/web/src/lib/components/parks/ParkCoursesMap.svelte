<script lang="ts">
	// Every course line of one park on one map (issue #1352), with each
	// distinct start area marked. Pointing at a course in the list beside it
	// (`highlightId`) draws that line in the accent colour over the rest.
	import { onDestroy, untrack } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv, mapStyleUrlFromEnv as mapStyleUrl } from '#lib/routes/map-style.svelte.ts';
	import {
		mapAccentColour,
		mapOverlayOutline,
		mapStartColour,
		mapTrackLine,
	} from '#lib/routes/basemap_contrast.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import { distinctStarts, type LatLng } from '#lib/parks/course_map.ts';

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';

	interface Props {
		courses: { id: string; points: LatLng[] }[];
		highlightId?: string | null;
		label: string;
		testid?: string;
	}

	let { courses, highlightId = null, label, testid }: Props = $props();

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDark);

	let consented = $state(untrack(() => hasAcceptedConsent()));
	let container: HTMLDivElement | undefined = $state();
	let map: maplibregl.Map | null = null;
	let ready = false;
	let stopResize: (() => void) | null = null;

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
		const id = highlightId ?? '';
		map.setFilter('park-course-highlight', ['==', ['get', 'id'], id]);
		map.setPaintProperty('park-course-lines', 'line-opacity', highlightId ? 0.45 : 0.9);
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
				id: 'park-course-highlight',
				type: 'line',
				source: 'park-courses',
				filter: ['==', ['get', 'id'], ''],
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapAccentColour(darkBasemap), 'line-width': 5 },
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

	function fit() {
		if (!map) return;
		let w = Infinity;
		let s = Infinity;
		let e = -Infinity;
		let n = -Infinity;
		for (const c of courses) {
			for (const p of c.points) {
				w = Math.min(w, p.lng);
				e = Math.max(e, p.lng);
				s = Math.min(s, p.lat);
				n = Math.max(n, p.lat);
			}
		}
		if (!Number.isFinite(w)) return;
		map.fitBounds([[w, s], [e, n]], { padding: 32, maxZoom: 16, duration: 0 });
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
		map.on('load', () => {
			ready = true;
			draw();
			fit();
		});
	});

	$effect(() => {
		void courses;
		untrack(() => {
			draw();
			fit();
		});
	});

	$effect(() => {
		void highlightId;
		untrack(paintHighlight);
	});

	onDestroy(() => {
		stopResize?.();
		map?.remove();
	});
</script>

{#if consented}
	<div class="park-courses-map" bind:this={container} role="img" aria-label={label} data-testid={testid}></div>
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
		min-height: 18rem;
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
