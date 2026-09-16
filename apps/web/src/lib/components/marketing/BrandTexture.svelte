<script lang="ts">
	import { contourPaths } from '$lib/marketing/contour_field';

	// Contour lines over the brand canvas. A gradient has no surface, so the
	// sign-in pane read as a coloured rectangle with copy on it; this gives
	// it ground. Traced from a real height field by marching squares
	// (contour_field.ts), so the saddle between the two summits and the
	// crowding on the steep flank are properties of the terrain rather than
	// of a hand-drawn set of ovals.
	//
	// Drawn, not fetched, for the same reasons as MapBackdrop: no network, no
	// third party, no consent question on the highest-traffic anonymous
	// surface in the product, and no raster to go stale or to ship as a
	// binary. It is also not a MAP — the geometry is a synthesised field, so
	// there is no real place here and nothing to read a location out of.
	//
	// `box` is the coordinate space the field is traced in. The pane passes a
	// portrait one and the band a wide one, so the two halves of the canvas
	// show the same landscape at different crops rather than the same picture
	// squashed twice.

	// `strength` scales every line's opacity. The brand canvas is a fixed
	// dark surface and takes the default; a THEME surface needs both a
	// quieter set and a token ink, which is what `tint` is for — a literal
	// white would invert out of existence on the cream and swamp the dark.
	let {
		width = 760,
		height = 900,
		strength = 1,
		tint = '',
	}: { width?: number; height?: number; strength?: number; tint?: string } = $props();

	let paths = $derived(contourPaths({ width, height }));
</script>

<svg
	class="texture"
	viewBox="0 0 {width} {height}"
	preserveAspectRatio="xMidYMid slice"
	aria-hidden="true"
	focusable="false"
	style={tint ? `--texture-stroke: ${tint}` : undefined}
>
	{#each paths as d, i (i)}
		<!-- Higher ground reads slightly brighter, which is the only cue that
		     says which way is up on a single-colour contour set. The ramp's
		     palest stop is measured under the strongest of these in
		     gradient_foreground_guard.test.ts. -->
		<path {d} stroke-opacity={((0.042 + i * 0.009) * strength).toFixed(3)} />
	{/each}
</svg>

<style>
	.texture {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		pointer-events: none;
	}

	path {
		fill: none;
		/* § 506's sanctioned shape: a hex fallback on a LOCAL custom property
		   the parent sets per instance. The fallback is the fixed-canvas ink. */
		stroke: var(--texture-stroke, #FFFFFF);
		stroke-width: 1.25;
		/* The SVG is scaled to cover its box, so a stroke in user units would
		   thicken with it — at pane size the lines would read as ribbons. */
		vector-effect: non-scaling-stroke;
	}
</style>
