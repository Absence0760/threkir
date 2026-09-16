<script lang="ts">
	import type { Snippet } from 'svelte';
	import PublicHeader from './PublicHeader.svelte';
	import PublicFooter from './PublicFooter.svelte';

	// `prose` narrows the column to a reading measure for a guide body;
	// `wide` is the card-grid width the hub and category pages share.
	// `banner` puts the brand ramp behind the page's top band and flips the
	// header to its transparent overlay variant — the same chrome the landing
	// page wears. Without it, clicking Learn went from a magenta hero under a
	// transparent bar to a WHITE header bar over a cream body, which is the
	// jump that made Learn read as another site.
	let {
		width = 'wide',
		banner = false,
		children,
	}: { width?: 'wide' | 'prose'; banner?: boolean; children: Snippet } = $props();
</script>

<div class="learn-page" class:prose={width === 'prose'}>
	<PublicHeader overlay={banner} />
	{@render children()}
	<PublicFooter />
</div>

<style>
	.learn-page {
		--learn-col: 64rem;
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.learn-page.prose {
		--learn-col: 44rem;
	}

	/* One definition of the column every band on a learn page sits in.
	   Each page had its own copy, and they drifted — the hub's header
	   ended up 8rem narrower than the card grid directly beneath it, so
	   the heading and the cards did not share a left edge. Pages still
	   own their vertical padding; only the horizontal frame lives here. */
	/* Full-bleed brand band; the column inside it keeps the same frame as
	   every other band on the page. The ramp is the landing hero's, stopped
	   early — an index page gets a strip, not a hero. Its stops and the inks
	   on them are measured in gradient_foreground_guard.test.ts. */
	.learn-page :global(.learn-band) {
		background: linear-gradient(135deg, #140A18 0%, #6E1450 100%);
		padding-block-start: 4.5rem;
	}

	/* Everything inside the band is on a fixed dark canvas, so it cannot use
	   the theme's text tokens — they are dark-on-dark in light mode. */
	.learn-page :global(.learn-band),
	.learn-page :global(.learn-band) :global(h1),
	.learn-page :global(.learn-band) :global(a) {
		color: #FFFFFF;
	}

	.learn-page :global(.learn-band) :global(.kicker),
	.learn-page :global(.learn-band) :global(p) {
		color: rgba(255, 255, 255, 0.85);
	}

	.learn-page :global(.learn-column) {
		max-width: var(--learn-col);
		margin-inline: auto;
		width: 100%;
	}
</style>
