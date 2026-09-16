<script lang="ts">
	import TrackPreview from '$lib/components/TrackPreview.svelte';
	import MapBackdrop from './MapBackdrop.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import {
		DEMO_DISTANCE_LABEL,
		DEMO_PACE_LABEL,
		DEMO_TIME_LABEL,
		DEMO_TRACK,
	} from '$lib/marketing/demo_preview';

	// The sign-in brand pane's product shot — the same argument as the
	// landing hero's ProductPreview, at a quarter of its height: the pane
	// had three bulleted claims and showed nothing the claims were about,
	// on the one screen a visitor reaches with their guard up.
	//
	// A separate component rather than a `compact` prop on ProductPreview:
	// that one is a pair of device frames carrying a splits chart, a zone
	// bar and a 695-line animation built for a 9rem-tall hero, and the
	// prop would have to switch off nearly all of it. This is one card of
	// the product's own renderer over the same DEMO_* data, so the two
	// cannot show different runs, and it inherits the same freedom from a
	// committed PNG: the route here is drawn by the code that draws a real
	// one on /runs.
	//
	// It sits on --brand-ramp, so the card is a light surface floating on a
	// dark canvas and every ink inside it is a literal measured against
	// that light surface rather than a theme token — the pane is a fixed
	// brand canvas in both themes.
</script>

<figure class="showcase">
	<div class="map">
		<MapBackdrop />
		<TrackPreview points={DEMO_TRACK} aspect={2.6} />
	</div>

	<div class="stats">
		<div class="stat">
			<span class="label">{m('landing.previewDistance')}</span>
			<span class="value">{DEMO_DISTANCE_LABEL}<small>km</small></span>
		</div>
		<div class="stat">
			<span class="label">{m('landing.previewTime')}</span>
			<span class="value">{DEMO_TIME_LABEL}</span>
		</div>
		<div class="stat">
			<span class="label">{m('landing.previewPace')}</span>
			<span class="value">{DEMO_PACE_LABEL}<small>/km</small></span>
		</div>
	</div>

	<figcaption>{m('landing.previewCaption')}</figcaption>
</figure>

<style>
	.showcase {
		margin: 0;
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border-radius: var(--radius-lg);
		/* A card on a dark canvas needs its own edge — the page's border
		   token is tuned for a light surface and disappears here. */
		border: 1px solid rgba(255, 255, 255, 0.14);
		box-shadow: 0 18px 40px rgba(20, 10, 24, 0.35);
		overflow: hidden;
	}

	.map {
		position: relative;
		/* The backdrop is absolutely positioned inside this box, so the
		   height comes from the route SVG's own aspect. */
		background: var(--color-bg-secondary);
	}

	.stats {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-sm);
		padding: var(--space-md) var(--space-lg);
		border-top: 1px solid var(--color-border);
	}

	.stat {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}

	.label {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: var(--section-label-tracking);
		color: var(--color-text-tertiary);
	}

	.value {
		font-size: 1.15rem;
		font-weight: 700;
		letter-spacing: -0.01em;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
	}

	.value small {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		color: var(--color-text-tertiary);
		margin-inline-start: 0.1rem;
	}

	figcaption {
		padding: 0 var(--space-lg) var(--space-md);
		font-size: var(--font-size-section-label);
		color: var(--color-text-tertiary);
		line-height: 1.4;
	}
</style>
