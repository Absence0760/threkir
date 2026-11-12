<script lang="ts" module>
	export type ParkMapLegendKind =
		| 'start'
		| 'finish'
		| 'startFinish'
		| 'checkpoint'
		| 'distance'
		| 'direction'
		| 'line'
		| 'focusedLine'
		| 'trailhead';

	export interface ParkMapLegendItem {
		kind: ParkMapLegendKind;
		label: string;
	}
</script>

<script lang="ts">
	// The key under a park course map (issue #1352): each mark the map draws,
	// drawn again in the colours the map paints it, with its meaning in text.
	// The swatches are decoration; the list of labels is what a screen reader
	// gets, under the list's own name.
	import { m } from '#lib/i18n/store.svelte.ts';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv } from '#lib/routes/map-style.svelte.ts';
	import {
		MAP_ARROW_INK,
		MAP_ARROW_OUTLINE,
		mapAccentColour,
		mapFinishColour,
		mapLabelHalo,
		mapLabelInk,
		mapOverlayOutline,
		mapStartColour,
		mapTrackLine,
	} from '#lib/routes/basemap_contrast.ts';
	import { checkpointPinColour } from '#lib/parks/course_map.ts';

	let { items, testid }: { items: ParkMapLegendItem[]; testid?: string } = $props();

	const prefersDark = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
	const dark = $derived(basemapIsDarkFromEnv(PUBLIC_MAPTILER_KEY_ENV ?? '', prefersDark));
</script>

{#snippet pin(fill: string)}
	<svg viewBox="0 0 16 22" class="swatch" aria-hidden="true" focusable="false">
		<path d="M8 1C4.1 1 1 4.1 1 8c0 5 7 13 7 13s7-8 7-13c0-3.9-3.1-7-7-7z" fill={fill} />
		<circle cx="8" cy="8" r="2.6" fill={MAP_ARROW_OUTLINE} />
	</svg>
{/snippet}

<ul class="legend" aria-label={m('parks.mapKey')} data-testid={testid}>
	{#each items as item (item.kind)}
		<li>
			{#if item.kind === 'start' || item.kind === 'trailhead'}
				{#if item.kind === 'start'}
					{@render pin(mapStartColour(dark))}
				{:else}
					<svg viewBox="0 0 16 16" class="swatch" aria-hidden="true" focusable="false">
						<circle cx="8" cy="8" r="6" fill={mapStartColour(dark)} stroke={mapOverlayOutline(dark)} stroke-width="2" />
					</svg>
				{/if}
			{:else if item.kind === 'finish' || item.kind === 'startFinish'}
				{@render pin(mapFinishColour(dark))}
			{:else if item.kind === 'checkpoint'}
				<svg viewBox="0 0 16 16" class="swatch" aria-hidden="true" focusable="false">
					<circle cx="8" cy="8" r="6" fill={checkpointPinColour(dark)} stroke={mapOverlayOutline(dark)} stroke-width="2" />
				</svg>
			{:else if item.kind === 'distance'}
				<svg viewBox="0 0 24 24" class="swatch" aria-hidden="true" focusable="false">
					<circle cx="12" cy="12" r="10" fill={mapLabelHalo(dark)} stroke={mapTrackLine(dark)} stroke-width="2" />
					<text x="12" y="16" text-anchor="middle" font-size="11" font-weight="700" fill={mapLabelInk(dark)}>1</text>
				</svg>
			{:else if item.kind === 'direction'}
				<svg viewBox="0 0 16 16" class="swatch" aria-hidden="true" focusable="false">
					<polygon points="3,2 14,8 3,14" fill={MAP_ARROW_INK} stroke={MAP_ARROW_OUTLINE} stroke-width="1.5" />
				</svg>
			{:else}
				<svg viewBox="0 0 24 12" class="swatch wide" aria-hidden="true" focusable="false">
					<line
						x1="2"
						y1="6"
						x2="22"
						y2="6"
						stroke={item.kind === 'focusedLine' ? mapAccentColour(dark) : mapTrackLine(dark)}
						stroke-width="4"
						stroke-linecap="round"
					/>
				</svg>
			{/if}
			<span>{item.label}</span>
		</li>
	{/each}
</ul>

<style>
	.legend {
		list-style: none;
		margin: var(--space-sm) 0 0;
		padding: 0;
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs) var(--space-md);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.legend li {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	.swatch {
		flex: none;
		width: 1rem;
		height: 1rem;
	}
	.swatch.wide {
		width: 1.5rem;
	}
</style>
