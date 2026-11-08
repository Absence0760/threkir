<script lang="ts">
	// A course's start and finish lines on a map (#1305, decisions § 2390),
	// optionally over the course route, and optionally editable: with
	// `editWhich` set, that line gets a draggable centre and a draggable
	// direction handle, and `onedit` fires with the moved line on release.
	// Dragging is never the only way: the editor around this map has numeric
	// inputs for every value.
	import { onDestroy, untrack } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import maplibregl from '#lib/routes/maplibre.ts';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv, mapStyleUrlFromEnv as mapStyleUrl } from '#lib/routes/map-style.svelte.ts';
	import { mapTrackLine } from '#lib/routes/basemap_contrast.ts';
	import { watchMapResize } from '#lib/routes/map_resize.ts';
	import { hasAcceptedConsent } from '#lib/settings/consent.svelte.ts';
	import { addCourseGateLayers, courseGateBounds, type DrawnGate } from '#lib/races/course_gate_layers.ts';
	import { bearingTo, gateArrowTip, type GatePoint, type GateWhich } from '#lib/races/course_gates.ts';
	import type { Gate } from '#lib/geo/gate_crossing.ts';

	const PUBLIC_MAPTILER_KEY = PUBLIC_MAPTILER_KEY_ENV ?? '';

	interface Props {
		gates: DrawnGate[];
		route?: GatePoint[] | null;
		editWhich?: GateWhich | null;
		onedit?: (which: GateWhich, gate: Gate) => void;
		/// Lets the editor ask where the map is looking, to place a new line there.
		oncenter?: (getCenter: () => GatePoint | null) => void;
		label: string;
		testid?: string;
	}

	let { gates, route = null, editWhich = null, onedit, oncenter, label, testid }: Props = $props();

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const darkBasemap = basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY, prefersDark);

	let consented = $state(untrack(() => hasAcceptedConsent()));
	let container: HTMLDivElement | undefined = $state();
	let map: maplibregl.Map | null = null;
	let ready = $state(false);
	let stopResize: (() => void) | null = null;
	let centreMarker: maplibregl.Marker | null = null;
	let handleMarker: maplibregl.Marker | null = null;
	let draft: { which: GateWhich; gate: Gate } | null = null;

	function shownGates(): DrawnGate[] {
		if (!draft) return gates;
		const d = draft;
		return gates.map((g) => (g.which === d.which ? { ...g, gate: d.gate } : g));
	}

	function routeData(): GeoJSON.Feature<GeoJSON.LineString> {
		return {
			type: 'Feature',
			properties: {},
			geometry: { type: 'LineString', coordinates: (route ?? []).map((p) => [p.lng, p.lat]) }
		};
	}

	function fit() {
		if (!map) return;
		const box = courseGateBounds(gates);
		let [w, s, e, n] = box ?? [Infinity, Infinity, -Infinity, -Infinity];
		for (const p of route ?? []) {
			w = Math.min(w, p.lng);
			e = Math.max(e, p.lng);
			s = Math.min(s, p.lat);
			n = Math.max(n, p.lat);
		}
		if (!Number.isFinite(w)) return;
		map.fitBounds([[w, s], [e, n]], { padding: 40, maxZoom: 18, duration: 0 });
	}

	function draw() {
		if (!map || !ready) return;
		const src = map.getSource('course-route') as maplibregl.GeoJSONSource | undefined;
		if (src) src.setData(routeData());
		else {
			map.addSource('course-route', { type: 'geojson', data: routeData() });
			map.addLayer({
				id: 'course-route-line',
				type: 'line',
				source: 'course-route',
				layout: { 'line-cap': 'round', 'line-join': 'round' },
				paint: { 'line-color': mapTrackLine(darkBasemap), 'line-width': 4, 'line-opacity': 0.8 }
			});
		}
		addCourseGateLayers(map, 'course-gates', shownGates(), darkBasemap);
		placeMarkers();
	}

	function markerEl(kind: 'centre' | 'handle'): HTMLDivElement {
		const el = document.createElement('div');
		el.className = `gate-marker gate-marker-${kind}`;
		el.title = kind === 'centre' ? m('courseLines.dragCentre') : m('courseLines.dragRotate');
		el.setAttribute('data-testid', `course-gate-${kind}`);
		return el;
	}

	function placeMarkers() {
		if (!map) return;
		const target = editWhich ? shownGates().find((g) => g.which === editWhich) : undefined;
		if (!target) {
			centreMarker?.remove();
			handleMarker?.remove();
			centreMarker = null;
			handleMarker = null;
			return;
		}
		const gate = target.gate;
		const tip = gateArrowTip(gate);
		if (!centreMarker) {
			centreMarker = new maplibregl.Marker({ element: markerEl('centre'), draggable: true })
				.setLngLat([gate.lng, gate.lat])
				.addTo(map);
			centreMarker.on('drag', () => moveCentre(false));
			centreMarker.on('dragend', () => moveCentre(true));
		} else {
			centreMarker.setLngLat([gate.lng, gate.lat]);
		}
		if (!handleMarker) {
			handleMarker = new maplibregl.Marker({ element: markerEl('handle'), draggable: true })
				.setLngLat([tip.lng, tip.lat])
				.addTo(map);
			handleMarker.on('drag', () => rotate(false));
			handleMarker.on('dragend', () => rotate(true));
		} else {
			handleMarker.setLngLat([tip.lng, tip.lat]);
		}
	}

	function current(): Gate | null {
		if (!editWhich) return null;
		return shownGates().find((g) => g.which === editWhich)?.gate ?? null;
	}

	function moveCentre(done: boolean) {
		const gate = current();
		if (!gate || !centreMarker || !editWhich) return;
		const p = centreMarker.getLngLat();
		draft = { which: editWhich, gate: { ...gate, lat: p.lat, lng: p.lng } };
		draw();
		if (done) commit();
	}

	function rotate(done: boolean) {
		const gate = current();
		if (!gate || !handleMarker || !editWhich) return;
		const p = handleMarker.getLngLat();
		draft = {
			which: editWhich,
			gate: { ...gate, bearingDeg: Math.round(bearingTo(gate, { lat: p.lat, lng: p.lng })) % 360 }
		};
		draw();
		if (done) commit();
	}

	function commit() {
		const d = draft;
		if (!d) return;
		onedit?.(d.which, d.gate);
	}

	$effect(() => {
		if (!consented || !container || map) return;
		const first = gates[0]?.gate ?? route?.[0] ?? null;
		map = new maplibregl.Map({
			container,
			style: mapStyleUrl(PUBLIC_MAPTILER_KEY, prefersDark),
			center: first ? [first.lng, first.lat] : [0, 0],
			zoom: first ? 16 : 1
		});
		map.addControl(new maplibregl.NavigationControl(), 'top-right');
		stopResize = watchMapResize(container, map);
		map.on('load', () => {
			ready = true;
			draw();
			fit();
		});
		oncenter?.(() => {
			if (!map) return null;
			const c = map.getCenter();
			return { lat: c.lat, lng: c.lng };
		});
	});

	$effect(() => {
		void gates;
		void route;
		void editWhich;
		// A new set of lines from the server replaces any drag in progress.
		draft = null;
		untrack(draw);
	});

	onDestroy(() => {
		centreMarker?.remove();
		handleMarker?.remove();
		stopResize?.();
		map?.remove();
	});
</script>

{#if consented}
	<div class="course-lines-map" bind:this={container} role="img" aria-label={label} data-testid={testid}></div>
{:else}
	<!-- audit/cookie-consent: MapTiler logs the requester IP per tile fetch, so
	     the map waits for consent or an explicit "Load map", as RunMap does. -->
	<div class="course-lines-consent" data-testid={testid ? `${testid}-consent` : undefined}>
		<p>
			{m('runMap.consentPrefix')}<strong>MapTiler</strong>{m('runMap.consentMiddle')}<strong>{m('runMap.loadMap')}</strong>{m('runMap.consentBeforeLink')}<a href="/cookie-notice">{m('runMap.cookieNotice')}</a>{m('runMap.consentSuffix')}
		</p>
		<button type="button" class="btn btn-secondary btn-sm" onclick={() => (consented = true)}>
			{m('runMap.loadMap')}
		</button>
	</div>
{/if}

<style>
	.course-lines-map {
		width: 100%;
		height: 260px;
		border-radius: var(--radius-md, 8px);
		overflow: hidden;
	}
	.course-lines-consent {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-md);
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md, 8px);
	}
	.course-lines-consent p {
		margin: 0;
	}
	:global(.gate-marker) {
		width: 22px;
		height: 22px;
		border-radius: 50%;
		border: 3px solid var(--color-surface);
		box-shadow: 0 0 0 1px var(--color-border);
		cursor: grab;
		touch-action: none;
	}
	:global(.gate-marker-centre) {
		background: var(--color-primary);
	}
	:global(.gate-marker-handle) {
		background: var(--color-text);
		width: 16px;
		height: 16px;
	}
</style>
