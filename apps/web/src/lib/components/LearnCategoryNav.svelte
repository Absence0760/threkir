<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { CATEGORIES } from '$lib/learn/categories';
	import { guidesByCategory } from '$lib/learn/guides';

	// The hub and every category page carry the same chip row, which is what
	// stops a category page reading as a different site: it is the only way
	// to move sideways between categories, and without it the breadcrumb is
	// the sole way out.
	let { current = null }: { current?: string | null } = $props();

	// An empty category would render a chip leading to a page with nothing
	// on it.
	const categories = $derived(CATEGORIES.filter((c) => guidesByCategory(c.id).length > 0));
</script>

<nav class="categories" aria-label={m('learn.browseByCategory')}>
	{#each categories as category (category.id)}
		{@const active = category.id === current}
		<a
			class="category-chip"
			class:active
			href="/learn/category/{category.id}"
			aria-current={active ? 'page' : undefined}
		>
			{m(category.labelKey)}
		</a>
	{/each}
</nav>

<style>
	.categories {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}

	.category-chip {
		padding: 0.4rem var(--space-md);
		border-radius: var(--radius-pill);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		text-decoration: none;
		transition: all var(--transition-base);
	}

	.category-chip:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	/* The chip for the page you are on. aria-current carries it for a screen
	   reader; the fill carries it for everyone else, so the state is not
	   colour-only. */
	.category-chip.active {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: var(--color-on-primary);
	}
</style>
