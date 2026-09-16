<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { countUp } from '$lib/motion/actions';

	// The split screen every page between the landing page and the app shares:
	// sign-in, sign-up and the reset request on /login, then /auth/reset,
	// /auth/confirm-age and /auth/callback. A visitor who clicks "Get Started"
	// walks through several of these in a row, and they used to be three
	// different designs; now the brand panel they left the landing page on
	// stays put while the form beside it changes.
	//
	// The page owns its <main id="main-content"> and passes it in as children:
	// shellless_landmark_guards reads the landmark out of each page's own
	// source, and a shell that supplied it would make that guard vacuous.
	//
	// Motion here ENDS. The landing page runs continuous motion behind a pause
	// control; a form is where a visitor is concentrating, so everything in
	// this shell plays once on arrival and then rests. A page's own loading
	// indicator is the one loop allowed (conventions § Web motion).

	let {
		children,
		panel,
		wide = false,
	}: {
		children: Snippet;
		/// The panel's copy. Omitted, the panel is brand-only: logo and art.
		panel?: Snippet;
		/// A wider card, for a page whose choices sit in a grid (onboarding)
		/// rather than one column of fields.
		wide?: boolean;
	} = $props();
</script>

<div class="auth-shell">
	<aside class="auth-panel" class:auth-panel--bare={!panel}>
		<div class="panel-topo" aria-hidden="true"></div>

		<!-- Not aria-hidden: on a desktop viewport this is the page's only route
		     home, and a hidden subtree left it focusable but nameless (axe
		     aria-hidden-focus; WCAG 4.1.2 + 2.4.3). -->
		<a href="/" class="panel-logo">
			<img src="/wordmark-light.svg" alt="Threkir" />
		</a>

		{#if panel}
			<div class="panel-copy">
				{@render panel()}
			</div>
		{/if}

		<!-- In flow after the copy, so the picture starts where the words stop in
		     every language: no copy is ever set on the art, and every ink on the
		     panel stays measured against the ramp. -->
		<div class="panel-art" aria-hidden="true">
			<picture class="panel-terrain">
				<source
					type="image/webp"
					srcset="/marketing/terrain-panel-800.webp 800w, /marketing/terrain-panel-1200.webp 1200w"
					sizes="(min-width: 56rem) 50vw, 100vw"
				/>
				<img
					src="/marketing/terrain-panel-800.webp"
					alt=""
					width="1200"
					height="1500"
					decoding="async"
				/>
			</picture>
			<div class="panel-card">
				<span class="panel-card-rec"><span class="panel-card-dot"></span>{m('landing.previewRecording')}</span>
				<span class="panel-card-clock" use:countUp={{ delay: 900, duration: 1600 }}>24:17</span>
				<span class="panel-card-meta">
					{m('landing.previewDistance')} <strong use:countUp={{ delay: 900, duration: 1600 }}>4.82</strong> km
				</span>
			</div>
		</div>
	</aside>

	<div class="auth-side" class:auth-side--wide={wide}>
		{@render children()}
	</div>
</div>

<style>
	.auth-shell {
		--ease-out: cubic-bezier(0.22, 1, 0.36, 1);
		min-height: 100vh;
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		grid-template-rows: auto 1fr;
		background: var(--color-bg);
	}

	/* --- panel ---------------------------------------------------------- */

	/* The landing hero's plum, stopped before its magenta terminus so the
	   panel reads as the same night the visitor clicked through from. Every
	   stop is measured under white copy, bare and under each veil, by
	   gradient_foreground_guard.test.ts. */
	.auth-panel {
		position: relative;
		overflow: hidden;
		isolation: isolate;
		display: flex;
		flex-direction: column;
		color: #FFFFFF;
		background: linear-gradient(165deg, #140A18 0%, #3A0F33 48%, #6E1450 100%);
		min-height: 13rem;
		padding: var(--space-lg) var(--space-md);
	}

	.auth-panel::before {
		content: '';
		position: absolute;
		z-index: -1;
		top: -30%;
		inset-inline-end: -30%;
		width: 80%;
		height: 90%;
		background: radial-gradient(ellipse, rgba(254, 89, 50, 0.18) 0%, transparent 70%);
		pointer-events: none;
	}

	/* On a phone the panel is a short band with no copy, so the art fills it. */
	.panel-art {
		position: absolute;
		z-index: -1;
		inset: 0;
		pointer-events: none;
	}

	.panel-topo {
		position: absolute;
		z-index: -1;
		inset: 0;
		background: rgba(255, 255, 255, 0.07);
		mask-image: url('/marketing/topo.svg');
		mask-size: 60rem 40rem;
		mask-position: 30% 10%;
	}

	.panel-terrain {
		position: absolute;
		inset: 0;
		mask-image: linear-gradient(to bottom, transparent 0%, black 40%);
	}

	.panel-terrain img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: 50% 70%;
		display: block;
	}

	@keyframes art-settle {
		from {
			opacity: 0;
			transform: scale(1.08) translateY(1.5rem);
		}
	}

	/* A glass readout floating over the terrain, the same run the landing
	   page's phone is recording. Decorative: its figures count up once and
	   stop. Hidden on a phone, where the panel is a short band. */
	.panel-card {
		display: none;
	}

	.panel-logo {
		position: relative;
		display: inline-flex;
		align-self: flex-start;
		border-radius: var(--radius-md);
	}

	.panel-logo img {
		height: 2rem;
		width: auto;
		display: block;
	}

	.panel-copy {
		display: none;
	}

	/* --- form side ------------------------------------------------------ */

	.auth-side {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-md);
		padding: 0 var(--space-md) var(--space-xl);
	}

	/* The page's <main>. Styled here, through the page's own class, so every
	   page in the journey carries the same card without restating it. */
	.auth-side :global(.auth-card) {
		position: relative;
		width: 100%;
		max-width: 27rem;
		/* Rides up over the panel band on a phone. */
		margin-top: -3.5rem;
		padding: var(--space-xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: 1.5rem;
		box-shadow:
			0 1px 2px color-mix(in srgb, var(--color-text) 6%, transparent),
			0 2rem 4rem -1.5rem color-mix(in srgb, var(--color-primary) 32%, transparent);
	}

	/* Entrances only for visitors who accept motion: a `from` keyframe that
	   hides content still paints for one frame under the global reduced-motion
	   rule, before the timeline ticks. */
	@media (prefers-reduced-motion: no-preference) {
		.panel-terrain {
			animation: art-settle 2.4s var(--ease-out) backwards;
		}

		.auth-side :global(.auth-card) {
			animation: card-rise 800ms var(--ease-out) 120ms backwards;
		}

		.panel-card {
			animation: card-float-in 1100ms var(--ease-out) 700ms backwards;
		}
	}

	.auth-side--wide :global(.auth-card) {
		max-width: 34rem;
	}

	@keyframes card-rise {
		from {
			opacity: 0;
			transform: translateY(1.5rem);
		}
	}

	@media (min-width: 56rem) {
		.auth-shell {
			grid-template-columns: minmax(0, 1.05fr) minmax(26rem, 0.95fr);
			grid-template-rows: none;
		}

		.auth-side {
			order: 0;
			justify-content: center;
			padding: var(--space-2xl);
		}

		/* The form side gets the faintest contour texture, so the two halves
		   read as one surface rather than a photo pasted beside a form. */
		.auth-side::before {
			content: '';
			position: absolute;
			inset: 0;
			background: color-mix(in srgb, var(--color-text) 4%, transparent);
			mask-image: url('/marketing/topo.svg');
			mask-size: 70rem 46.7rem;
			pointer-events: none;
		}

		.auth-side :global(.auth-card) {
			margin-top: 0;
			padding: var(--space-2xl) var(--space-xl);
		}

		.auth-panel {
			order: 1;
			position: sticky;
			top: 0;
			height: 100vh;
			min-height: 0;
			padding: var(--space-2xl);
		}

		.panel-copy {
			display: block;
			position: relative;
			max-width: 30rem;
			margin-block-start: var(--space-2xl);
		}

		/* Bleeds to the panel's edges below the copy; a brand-only panel has no
		   copy, so this takes everything under the logo. */
		.panel-art {
			position: relative;
			flex: 1;
			min-height: 12rem;
			margin: var(--space-lg) calc(-1 * var(--space-2xl)) calc(-1 * var(--space-2xl));
		}

		.panel-card {
			position: absolute;
			inset-inline-end: 12%;
			bottom: 18%;
			display: flex;
			flex-direction: column;
			gap: 0.15rem;
			padding: 0.9rem 1.2rem;
			border-radius: 1.1rem;
			background: rgba(20, 10, 24, 0.55);
			border: 1px solid rgba(255, 255, 255, 0.18);
			backdrop-filter: blur(14px);
			box-shadow: 0 1.5rem 3rem rgba(0, 0, 0, 0.35);
		}

		.panel-card-rec {
			display: inline-flex;
			align-items: center;
			gap: 0.4rem;
			font-size: var(--font-size-section-label);
			font-weight: 700;
			letter-spacing: 0.1em;
			text-transform: uppercase;
			color: #FFB59C;
		}

		.panel-card-dot {
			width: 0.45rem;
			height: 0.45rem;
			border-radius: var(--radius-pill);
			background: var(--brand-ember);
			box-shadow: 0 0 0.6rem rgba(254, 89, 50, 0.9);
		}

		.panel-card-clock {
			font-size: 1.9rem;
			font-weight: 800;
			letter-spacing: -0.02em;
			font-variant-numeric: tabular-nums;
			line-height: 1.1;
		}

		.panel-card-meta {
			font-size: 0.85rem;
			color: rgba(255, 255, 255, 0.85);
		}

		.panel-card-meta strong {
			color: #FFFFFF;
			font-variant-numeric: tabular-nums;
		}
	}

	@keyframes card-float-in {
		from {
			opacity: 0;
			transform: translateY(2rem) scale(0.94);
		}
	}
</style>
