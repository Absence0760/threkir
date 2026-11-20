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
		| 'trailhead'
		| 'startBox'
		| 'finishBox'
		| 'startFinishBox'
		| 'turnaround';

	export interface ParkMapLegendItem {
		kind: ParkMapLegendKind;
		label: string;
		/// Makes the entry a button: a park course's start and finish entries
		/// take the map to that box. `label` is the button's accessible name.
		action?: { label: string; run: () => void };
	}
</script>

<script lang="ts">
	// The key under a park course map (issue #1352): each mark the map draws,
	// drawn again in the colours the map paints it, with its meaning in text.
	// The swatches are decoration; the list of labels is what a screen reader
	// gets, under the list's own name. An entry with an action is a button
	// that looks like the other entries, its hit area padded out to 44 px.
	import { m } from '#lib/i18n/store.svelte.ts';
	import { PUBLIC_MAPTILER_KEY as PUBLIC_MAPTILER_KEY_ENV } from '$app/env/public';
	import { basemapIsDarkFromEnv } from '#lib/routes/map-style.svelte.ts';
	import {
		MAP_ARROW_INK,
		MAP_ARROW_OUTLINE,
		MAP_ZONE_FILL_OPACITY,
		mapFinishColour,
		mapFinishZoneColour,
		mapLabelHalo,
		mapLabelInk,
		mapOverlayOutline,
		mapPinnedLine,
		mapStartColour,
		mapStartZoneColour,
		mapTrackLine,
	} from '#lib/routes/basemap_contrast.ts';
	import { checkpointPinColour } from '#lib/parks/course_map.ts';
	import { turnaroundSvg } from '#lib/races/course_gate_layers.ts';

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

<!-- A start or finish box as the map draws it: the fill, its outline, and its
     timing line, solid for the start and chequered for the finish. The box a
     start and finish share is the start colour with a chequered line across
     its middle. -->
{#snippet boxPart(which: 'start' | 'finish' | 'both')}
	{@const colour = which === 'finish' ? mapFinishZoneColour(dark) : mapStartZoneColour(dark)}
	{@const y = which === 'both' ? 8.5 : 3}
	<rect x="1" y="3" width="22" height="11" fill={colour} fill-opacity={MAP_ZONE_FILL_OPACITY} stroke={colour} stroke-width="1" />
	<line x1="1" y1={y} x2="23" y2={y} stroke={mapOverlayOutline(dark)} stroke-width="4" />
	<line x1="1" y1={y} x2="23" y2={y} stroke={colour} stroke-width="2.5" />
	{#if which !== 'start'}
		<line x1="1" y1={y} x2="23" y2={y} stroke={MAP_ARROW_OUTLINE} stroke-width="2.5" stroke-dasharray="2.5 2.5" />
	{/if}
{/snippet}

<ul class="legend" aria-label={m('parks.mapKey')} data-testid={testid}>
	{#each items as item (item.kind)}
		<li data-kind={item.kind}>
			{#if item.action}
				{@const action = item.action}
				<button type="button" class="pick" aria-label={action.label} onclick={action.run}>
					{@render mark(item)}
					<span>{item.label}</span>
				</button>
			{:else}
				{@render mark(item)}
				<span>{item.label}</span>
			{/if}
		</li>
	{/each}
</ul>

{#snippet mark(item: ParkMapLegendItem)}
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
	{:else if item.kind === 'startBox' || item.kind === 'finishBox' || item.kind === 'startFinishBox'}
		<svg viewBox="0 0 24 16" class="swatch wide" aria-hidden="true" focusable="false">
			{@render boxPart(item.kind === 'startBox' ? 'start' : item.kind === 'finishBox' ? 'finish' : 'both')}
		</svg>
	{:else if item.kind === 'turnaround'}
		<span class="swatch tag" style:border-color={mapOverlayOutline(dark)} style:background={mapLabelHalo(dark)}>
			<!-- Static markup from the palette only. -->
			{@html turnaroundSvg(mapLabelInk(dark))}
		</span>
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
			{#if item.kind === 'focusedLine'}
				<line x1="2" y1="6" x2="22" y2="6" stroke={mapLabelHalo(dark)} stroke-width="8" stroke-linecap="round" />
			{/if}
			<line
				x1="2"
				y1="6"
				x2="22"
				y2="6"
				stroke={item.kind === 'focusedLine' ? mapPinnedLine(dark) : mapTrackLine(dark)}
				stroke-width={item.kind === 'focusedLine' ? 5 : 3}
				stroke-linecap="round"
			/>
		</svg>
	{/if}
{/snippet}

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
	.pick {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0;
		border: 0;
		background: none;
		font: inherit;
		color: inherit;
		cursor: pointer;
	}
	/* The hit area, 44 px tall and a little wider, without a bigger look. */
	.pick::before {
		content: '';
		position: absolute;
		inset-inline: -0.25rem;
		top: 50%;
		height: 44px;
		transform: translateY(-50%);
	}
	.pick:hover span {
		text-decoration: underline;
	}
	.pick:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
		border-radius: 2px;
	}
	.swatch {
		flex: none;
		width: 1rem;
		height: 1rem;
	}
	.swatch.wide {
		width: 1.5rem;
	}
	.swatch.tag {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.25rem;
		height: 1.25rem;
		border: 2px solid;
		border-radius: 999px;
	}
	.swatch.tag :global(svg) {
		width: 0.85rem;
		height: 0.85rem;
	}
</style>
