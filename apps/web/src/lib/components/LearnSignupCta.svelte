<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';

	// The closing band the hub and every category page end on. Distinct from
	// LearnCta, which is the per-article CTA pointing at the app feature a
	// specific guide teaches.
</script>

<section class="signup-cta learn-column" aria-labelledby="learn-cta-heading">
	<p class="kicker">{m('learn.ctaKicker')}</p>
	<h2 id="learn-cta-heading">{m('learn.ctaHeading')}</h2>
	<p class="signup-sub">{m('learn.ctaSub')}</p>
	<a class="btn btn-primary" href="/login?signup=1">{m('learn.ctaButton')}</a>
</section>

<style>
	.signup-cta {
		padding: var(--space-xl) var(--space-md);
		text-align: center;
	}

	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}

	.signup-cta h2 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
		color: var(--color-text);
	}

	.signup-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 32rem;
		margin: 0 auto var(--space-md);
		line-height: 1.5;
	}
</style>
