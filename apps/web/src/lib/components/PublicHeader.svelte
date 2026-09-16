<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import MotionToggle from '$lib/components/marketing/MotionToggle.svelte';

	/// The landing page runs continuous motion and owes it a pause control
	/// (WCAG 2.2.2); /learn runs none, so only the page that moves asks for it.
	let { motionToggle = false }: { motionToggle?: boolean } = $props();

	// This bar is only ever drawn over a dark ramp -- the landing hero, or
	// the brand band every /learn route opens on -- so it is transparent
	// white-on-dark chrome, full stop. It used to carry a second `solid`
	// variant for a themed surface; once /learn gained its band nothing
	// rendered it, and a variant nothing renders is a variant nothing keeps
	// working. `learn_band_guard.test.ts` holds the premise: a route that
	// mounts LearnPage must also render a .learn-band.
</script>

<nav class="landing-nav">
	<a href="/" class="landing-logo" aria-label="Threkir">
		<img src="/wordmark-light.svg" alt="Threkir" class="landing-wordmark" />
	</a>
	<!-- Apps + Features were in-page anchors to sections one scroll away on a
	     four-section page, and they were already hidden below 768px -- the
	     mobile bar has always shipped without them. They stay in the footer,
	     where a site map belongs, and the section ids stay live for the deep
	     links that target them.

	     A "Get started free" pill sat beside Sign In too. This header is
	     position:absolute, not sticky, so it is on screen only at the very
	     top -- where the hero's own, much larger CTA is already visible --
	     and gone by the time a reader would want one. It was visible only
	     while redundant. Sign In stays because a returning visitor has
	     nothing else to aim at; new visitors have the hero. -->
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
		position: absolute;
		top: 0;
		inset-inline-start: 0;
		inset-inline-end: 0;
		z-index: 10;
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
