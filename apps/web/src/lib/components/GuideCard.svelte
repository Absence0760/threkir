<script lang="ts">
	import { m, currentLocale } from '$lib/i18n/store.svelte';
	import { getCategory } from '$lib/learn/categories';
	import { localizedGuideMeta, readingMinutes, type GuideIndexEntry } from '$lib/learn/guides';

	let { guide, featured = false }: { guide: GuideIndexEntry; featured?: boolean } = $props();

	const minutes = $derived(readingMinutes(guide.slug));

	const category = $derived(getCategory(guide.category));
	// Re-resolve the card's title + description for the active locale so the
	// listing matches the localized article body a click away; falls back to
	// the English frontmatter field-by-field when no localized file exists.
	const meta = $derived(localizedGuideMeta(guide.slug, currentLocale()) ?? guide);
</script>

<a class="card-elevated guide-card" class:featured href="/learn/{guide.slug}">
	<span class="card-meta">
		{#if category}
			<span class="category-pill">{m(category.labelKey)}</span>
		{/if}
		{#if minutes !== null}
			<span class="reading-time">{m('learn.readingTime', { minutes })}</span>
		{/if}
	</span>
	<h3>{meta.title}</h3>
	<p class="guide-desc">{meta.description}</p>
	<span class="read-more">{m('learn.readGuide')}</span>
</a>

<style>
	.guide-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
		height: 100%;
	}

	.card-meta {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}

	.reading-time {
		font-size: var(--font-size-section-label);
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--color-text-tertiary);
	}

	.category-pill {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-primary);
		background: var(--color-primary-light);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 0.15rem 0.5rem;
	}

	.guide-card h3 {
		font-size: 1.1rem;
		font-weight: 700;
		margin: 0;
		line-height: 1.25;
		color: var(--color-text);
	}

	.guide-desc {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.5;
		flex: 1;
	}

	.read-more {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-primary);
	}

	/* The one guide the hub points a newcomer at first. Same card, given the
	   full row and a larger title so the entry point is obvious without a
	   second component to keep in step. */
	.guide-card.featured {
		padding: var(--space-xl);
		border-color: var(--color-primary);
	}

	.guide-card.featured h3 {
		font-size: 1.6rem;
		letter-spacing: -0.01em;
	}

	.guide-card.featured .guide-desc {
		font-size: 1rem;
		max-width: 46rem;
		flex: 0 1 auto;
	}
</style>
