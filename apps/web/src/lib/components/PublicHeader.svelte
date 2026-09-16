<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';

	// overlay = transparent white-on-dark chrome laid over the landing
	// hero; solid = the same nav on a themed surface for the other
	// public pages (/learn). One component so the marketing surface
	// can't drift between the two again.
	let { overlay = false }: { overlay?: boolean } = $props();
</script>

<nav class="landing-nav" class:overlay class:solid={!overlay}>
	<a href="/" class="landing-logo" aria-label="Threkir">
		{#if overlay}
			<img src="/wordmark-light.svg" alt="Threkir" class="landing-wordmark" />
		{:else}
			<img src="/wordmark.svg" alt="Threkir" class="landing-wordmark on-light" />
			<img src="/wordmark-light.svg" alt="Threkir" class="landing-wordmark on-dark" />
		{/if}
	</a>
	<!-- Apps + Features were in-page anchors to sections one scroll away on a
	     four-section page, and they were already hidden below 768px -- the
	     mobile bar has always shipped without them. They stay in the footer,
	     where a site map belongs, and the section ids stay live for the deep
	     links that target them. -->
	<div class="nav-links">
		<a href="/learn" class="nav-link">{m('landing.navLearn')}</a>
		{#if auth.loggedIn}
			<a href="/dashboard" class="nav-signin">{m('landing.openApp')}</a>
		{:else}
			<a href="/login" class="nav-signin">{m('landing.signIn')}</a>
			<!-- ?signup=1 or the two pills are one button wearing two labels:
			     /login renders the sign-in form, and a visitor who clicked
			     "Get started free" landed under the headline "Sign in to your
			     account". The Learn CTAs have always carried the flag. -->
			<a href="/login?signup=1" class="nav-cta">{m('landing.getStartedFree')}</a>
		{/if}
	</div>
</nav>

<style>
	/* Both variants share their box metrics, so the wordmark, the nav
	   links, and the Sign In pill land in exactly the same place on the
	   landing page and on /learn. The variants used to set their own
	   padding and disagreed — solid was 15px shorter, so every item in
	   the header jumped up 8px when a visitor clicked Learn. Only what
	   MUST differ between an overlay and an in-flow bar (position,
	   ground, border) belongs in the variant blocks below. */
	.landing-nav {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
	}

	.landing-nav.overlay {
		position: absolute;
		top: 0;
		inset-inline-start: 0;
		inset-inline-end: 0;
		z-index: 10;
	}

	.landing-nav.solid {
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
	}

	.landing-logo {
		display: flex;
		align-items: center;
		text-decoration: none;
	}

	.landing-wordmark {
		height: 2rem;
		width: auto;
		display: block;
	}

	/* The solid header sits on a themed surface, so swap between the
	   dark-text and white-text wordmarks with the theme (explicit
	   html[data-theme] wins; auto/unset follows the OS preference). */
	.solid .landing-wordmark.on-dark {
		display: none;
	}
	:global([data-theme='dark']) .solid .landing-wordmark.on-light {
		display: none;
	}
	:global([data-theme='dark']) .solid .landing-wordmark.on-dark {
		display: block;
	}
	@media (prefers-color-scheme: dark) {
		:global([data-theme='auto']) .solid .landing-wordmark.on-light,
		:global(html:not([data-theme])) .solid .landing-wordmark.on-light {
			display: none;
		}
		:global([data-theme='auto']) .solid .landing-wordmark.on-dark,
		:global(html:not([data-theme])) .solid .landing-wordmark.on-dark {
			display: block;
		}
	}

	.nav-links {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
	}

	.nav-link {
		font-size: 0.9rem;
		font-weight: 500;
		transition: color var(--transition-fast);
	}

	.overlay .nav-link {
		color: rgba(255, 255, 255, 0.72);
	}

	.overlay .nav-link:hover {
		color: #ffffff;
	}

	.solid .nav-link {
		color: var(--color-text-secondary);
	}

	.solid .nav-link:hover {
		color: var(--color-text);
	}

	.nav-signin {
		font-weight: 500;
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		transition: all var(--transition-fast);
	}

	.overlay .nav-signin {
		color: rgba(255, 255, 255, 0.8);
		border: 1px solid rgba(255, 255, 255, 0.25);
		backdrop-filter: blur(8px);
	}

	.overlay .nav-signin:hover {
		border-color: rgba(255, 255, 255, 0.6);
		color: #ffffff;
		background: rgba(255, 255, 255, 0.1);
	}

	.solid .nav-signin {
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
	}

	.solid .nav-signin:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	/* Filled in BOTH variants from the primary pair rather than a white pill
	   with a frozen ink: white reads as the primary action on the hero ramp
	   and disappears on /learn's light surface, and app.css already holds
	   --color-primary / --color-on-primary to AA in both themes. */
	.nav-cta {
		font-weight: 600;
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		background: var(--color-primary);
		color: var(--color-on-primary);
		border: 1px solid transparent;
		white-space: nowrap;
		transition: all var(--transition-fast);
	}

	.nav-cta:hover {
		background: var(--color-primary-hover);
	}

	@media (max-width: 768px) {
		.nav-link {
			display: none;
		}
		/* Both pills stay. Hiding Sign In to make room was tried and is the
		   wrong trade — a returning visitor needs it more than a new one
		   needs a second CTA — and it breaks the /-vs-/learn header parity
		   that learn/chrome.spec.ts pins. Shrink them instead. */
		.nav-links {
			gap: var(--space-sm);
		}
		.nav-signin,
		.nav-cta {
			padding: var(--space-sm) var(--space-md);
			font-size: 0.85rem;
		}
	}
</style>
