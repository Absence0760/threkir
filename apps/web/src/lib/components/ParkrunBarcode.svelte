<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		CODE128_QUIET_ZONE_MODULES,
		barcodeBars,
		code128BModules,
	} from '#lib/integrations/parkrun_barcode.ts';

	interface Props {
		/** A canonical athlete number (`normalizeParkrunAthleteNumber`'s output). */
		number: string;
		/** Bar height in modules; the full-screen view asks for a taller code. */
		heightModules?: number;
		testId?: string;
	}

	let { number, heightModules = 48, testId = 'parkrun-barcode' }: Props = $props();

	const modules = $derived(code128BModules(number));
	const bars = $derived(barcodeBars(modules));
	const width = $derived(modules.length + 2 * CODE128_QUIET_ZONE_MODULES);
</script>

<!-- Black on white in both themes: a scanner needs the contrast, and a dark
     theme's inverted code is not one every finish-funnel reader decodes. -->
<figure class="parkrun-barcode" data-testid={testId}>
	<svg
		viewBox="0 0 {width} {heightModules}"
		role="img"
		aria-label={m('parkrunBarcode.ariaLabel', { number })}
		shape-rendering="crispEdges"
		data-modules={modules.length}
	>
		<rect x="0" y="0" width={width} height={heightModules} fill="#fff" />
		{#each bars as bar (bar.start)}
			<rect
				x={CODE128_QUIET_ZONE_MODULES + bar.start}
				y="0"
				width={bar.width}
				height={heightModules}
				fill="#000"
			/>
		{/each}
	</svg>
	<figcaption aria-hidden="true">{number}</figcaption>
</figure>

<style>
	.parkrun-barcode {
		margin: 0;
		padding: var(--space-sm) 0;
		background: #fff;
		color: #000;
		border-radius: var(--radius-md);
		text-align: center;
	}
	svg {
		display: block;
		width: 100%;
		height: auto;
	}
	figcaption {
		font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
		font-size: 1.1rem;
		letter-spacing: 0.12em;
		margin-top: var(--space-xs);
	}
</style>
