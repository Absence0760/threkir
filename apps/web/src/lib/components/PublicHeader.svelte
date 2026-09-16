<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import MotionToggle from '$lib/components/marketing/MotionToggle.svelte';

	/// The landing page runs continuous motion and owes it a pause control
	/// (WCAG 2.2.2); /learn runs none, so only the page that moves asks for it.
	let { motionToggle = false }: { motionToggle?: boolean } = $props();

	// White-on-dark chrome, full stop. At the top of the page it is
	// transparent over a dark ramp -- the landing hero, or the brand band every
	// /learn route opens on -- and `learn_band_guard.test.ts` holds that
	// pairing. It stays on screen as the page scrolls, and from the first few
	// pixels of scroll it paints its own plum glass, because from there the
	// ground under it is whatever content is passing: the same guard measures
	// every ink on that glass over the lightest ground a page can put under it.
	// It used to carry a second `solid` variant for a themed surface; a
	// variant nothing renders is a variant nothing keeps working.
	let scrolled = $state(false);

	function trackScroll(_node: HTMLElement) {
		const update = () => {
			scrolled = window.scrollY > 8;
		};
		update();
		window.addEventListener('scroll', update, { passive: true });
		return {
			destroy() {
				window.removeEventListener('scroll', update);
			},
		};
	}
</script>

<nav class="landing-nav" class:landing-nav--scrolled={scrolled} use:trackScroll>
	<a href="/" class="landing-logo" aria-label="Threkir">
		<img src="/wordmark-light.svg" alt="Threkir" class="landing-wordmark" />
	</a>
	<!-- Apps + Features were in-page anchors to sections one scroll away on a
	     four-section page, and they were already hidden below 768px -- the
	     mobile bar has always shipped without them. They stay in the footer,
	     where a site map belongs, and the section ids stay live for the deep
	     links that target them.

	     A "Get started free" pill sat beside Sign In too, and went when the
	     bar was still position:absolute and so on screen only beside the
	     hero's own, larger CTA. Sign In stays because a returning visitor has
	     nothing else to aim at. -->
	<div class="nav-links">
		{#if motionToggle}
			<MotionToggle />
		{/if}
		<a href="/learn" class="nav-link">{m('landing.navLearn')}</a>
		{#if auth.loggedIn}
			<a href="/dashboard" class="nav-signin">{m('landing.openApp')}</a>
		{:else}
			<a href="/login" class="nav-signin">{m('landing.signIn')}</a>
		{/if}
	</div>
</nav>

<style>
	/* One bar, one set of box metrics. There were two variants, and they set
	   their own padding and disagreed — solid came out 15px shorter, so every
	   item jumped 8px when a visitor clicked Learn. learn/chrome.spec.ts still
	   pins the geometry across / and /learn. */
	.landing-nav {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
		position: fixed;
		top: 0;
		inset-inline-start: 0;
		inset-inline-end: 0;
		z-index: var(--z-public-header);
		border-bottom: 1px solid transparent;
		transition:
			background var(--transition-base),
			padding var(--transition-base),
			border-color var(--transition-base),
			box-shadow var(--transition-base);
	}

	/* The glass the bar paints once content scrolls under it. Every ink in
	   this file is measured over it, composited on white, by
	   learn_band_guard.test.ts -- lighten the alpha and that fails. */
	.landing-nav--scrolled {
		padding-block: var(--space-sm);
		background: rgba(20, 10, 24, 0.8);
		backdrop-filter: blur(14px) saturate(1.3);
		border-bottom-color: rgba(255, 255, 255, 0.08);
		box-shadow: 0 0.75rem 2rem -1rem rgba(0, 0, 0, 0.5);
	}

	/* The bar covers the top of the viewport, so an anchor jump or a
	   keyboard-focused element must stop below it (WCAG 2.4.11). Sized to the
	   bar at its TALLEST, unscrolled (91px): a jump from the top of the page
	   lands while the bar is still compacting. Scoped to pages that render
	   the bar. */
	:global(html:has(.landing-nav)) {
		scroll-padding-top: 6.25rem;
	}

	.landing-logo {
		display: flex;
		align-items: center;
		text-decoration: none;
	}

	/* Always the white wordmark: the bar only ever sits on a dark ramp, so
	   the theme-swapped pair the solid variant needed is gone with it. */
	.landing-wordmark {
		height: 2rem;
		width: auto;
		display: block;
	}

	.nav-links {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
	}

	.nav-link {
		font-size: 0.9rem;
		font-weight: 500;
		color: rgba(255, 255, 255, 0.72);
		transition: color var(--transition-fast);
	}

	.nav-link:hover {
		color: #ffffff;
	}

	.nav-signin {
		font-weight: 500;
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		color: rgba(255, 255, 255, 0.8);
		border: 1px solid rgba(255, 255, 255, 0.25);
		backdrop-filter: blur(8px);
		transition: all var(--transition-fast);
	}

	.nav-signin:hover {
		border-color: rgba(255, 255, 255, 0.6);
		color: #ffffff;
		background: rgba(255, 255, 255, 0.1);
	}

	@media (max-width: 768px) {
		.nav-link {
			display: none;
		}
		.nav-links {
			gap: var(--space-sm);
		}
		.nav-signin {
			padding: var(--space-sm) var(--space-md);
			font-size: 0.85rem;
		}
	}
</style>
