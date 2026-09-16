<script lang="ts">
	import type { Snippet } from 'svelte';
	import PublicHeader from './PublicHeader.svelte';
	import PublicFooter from './PublicFooter.svelte';

	// `prose` narrows the column to a reading measure for a guide body;
	// `wide` is the card-grid width the hub and category pages share.
	let { width = 'wide', children }: { width?: 'wide' | 'prose'; children: Snippet } = $props();
</script>

<div class="learn-page" class:prose={width === 'prose'}>
	<PublicHeader />
	{@render children()}
	<PublicFooter />
</div>

<style>
	.learn-page {
		--learn-col: 64rem;
		/* 64rem fits three 17rem cards and leaves ~200px of margin either side
		   on a 1440px screen. 76rem fits four and uses it. The prose measure
		   below is untouched — a reading column does not want the width. */
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.learn-page.prose {
		--learn-col: 44rem;
	}

	@media (min-width: 90rem) {
		.learn-page {
			--learn-col: 76rem;
		}
		.learn-page.prose {
			--learn-col: 44rem;
		}
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
