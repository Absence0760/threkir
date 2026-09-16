<script lang="ts">
	// A stylised basemap behind the product preview's route.
	//
	// TrackPreview draws a polyline and nothing else — in the app a real
	// basemap sits under it, fetched from MapTiler, and that fetch is held
	// until consent because the endpoint logs the requester IP. The landing
	// page is the highest-traffic anonymous surface in the product, so it is
	// the last place to fire that request before the banner is answered
	// (audit/cookie-consent). Without something behind it the route floated on
	// a flat panel and read as a tile layer that had failed to load.
	//
	// So this is drawn, not fetched: deterministic geometry, no network, no
	// third party, no consent question, and every colour a token, so it
	// follows the theme like the rest of the shot. It is plainly stylised
	// rather than dressed up as a real place.

	// Irregular spacing on purpose — an even grid reads as graph paper.
	const ACROSS = [17, 43, 74, 101, 129, 152];
	const DOWN = [21, 49, 78, 112, 147, 181, 214];
</script>

<svg
	class="backdrop"
	viewBox="0 0 240 160"
	preserveAspectRatio="xMidYMid slice"
	aria-hidden="true"
	focusable="false"
>
	<!-- Parkland -->
	<path
		class="park"
		d="M132 18 Q168 10 196 24 Q214 34 210 56 Q206 78 178 84 Q148 90 134 72 Q122 52 132 18 Z"
	/>
	<path class="park" d="M8 92 Q34 84 52 96 Q62 112 44 124 Q20 132 8 118 Z" />

	<!-- Water -->
	<path
		class="water"
		d="M-6 132 Q44 120 82 100 Q122 80 168 96 Q206 110 248 98"
	/>

	<!-- Street grid -->
	{#each ACROSS as y (y)}
		<line class="street" x1="-4" y1={y} x2="244" y2={y} />
	{/each}
	{#each DOWN as x (x)}
		<line class="street" x1={x} y1="-4" x2={x} y2="164" />
	{/each}
	<!-- Two roads that ignore the grid, which is what keeps it from reading
	     as graph paper. -->
	<path class="street arterial" d="M-4 8 Q70 38 118 56 Q172 76 244 70" />
	<path class="street arterial" d="M56 -4 Q72 52 108 92 Q140 128 150 164" />

	<!-- A few blocks, so the grid encloses something -->
	<rect class="block" x="24" y="24" width="24" height="18" rx="1.5" />
	<rect class="block" x="80" y="53" width="18" height="18" rx="1.5" />
	<rect class="block" x="106" y="106" width="20" height="14" rx="1.5" />
	<rect class="block" x="158" y="128" width="26" height="16" rx="1.5" />
	<rect class="block" x="190" y="104" width="18" height="20" rx="1.5" />
</svg>

<style>
	.backdrop {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		display: block;
	}

	/* Deliberately faint. The route is the subject; this only has to stop the
	   panel reading as an empty frame. */
	/* The -text variants, not the base tokens: contrast_guard bans a bare
	   accent as a fill or stroke because it fails AA wherever it lands on a
	   light surface. These are decorative and faint, but the theme-aware
	   variant is the right value anyway — the base green is candy-bright
	   against a paper basemap. */
	.park {
		fill: var(--color-success-text);
		opacity: 0.18;
	}

	.water {
		fill: none;
		stroke: var(--color-accent-cyan-text);
		stroke-width: 11;
		stroke-linecap: round;
		opacity: 0.24;
	}

	.street {
		fill: none;
		stroke: var(--color-text-tertiary);
		stroke-width: 0.9;
		opacity: 0.28;
	}

	.arterial {
		stroke-width: 2.2;
		opacity: 0.34;
	}

	.block {
		fill: var(--color-text-tertiary);
		opacity: 0.1;
	}
</style>
