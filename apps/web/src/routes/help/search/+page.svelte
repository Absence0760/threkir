<script lang="ts">
	/// Help search results for `?q=`. Ranked by `searchGuides`: a word in the
	/// title outranks one in the summary, which outranks one further down.
	import { page } from '$app/state';
	import { searchGuides } from '#lib/help/index.ts';
	import { KIND_LABEL } from '#lib/help/labels.ts';
	import HelpSearchForm from '#lib/components/help/HelpSearchForm.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	const query = $derived((page.url.searchParams.get('q') ?? '').trim());
	const results = $derived(searchGuides(query));
</script>

<svelte:head>
	<title>{m('help.searchPageTitle')}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="help-search-page">
	<a class="back-link" href="/help">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('help.allGuides')}
	</a>
	<h1>{m('help.searchTitle')}</h1>

	<HelpSearchForm {query} />

	<div class="results" role="status" aria-live="polite">
		{#if !query}
			<p class="state-msg">{m('help.searchPrompt')}</p>
		{:else if results.length === 0}
			<p class="state-msg">{m('help.searchEmpty', { query })}</p>
		{:else}
			<h2>{m('help.searchResultsFor', { query })}</h2>
		{/if}
	</div>

	{#if results.length}
		<ul class="result-list" data-testid="help-search-results">
			{#each results as guide (guide.id)}
				<li>
					<a class="result" href="/help/{guide.id}">
						<span class="result-kind">{m(KIND_LABEL[guide.kind])}</span>
						<span class="result-title">{guide.title}</span>
						<span class="result-summary">{guide.summary}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.help-search-page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: 2.25rem;
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
	}
	.back-link .material-symbols {
		font-size: 1.1rem;
	}
	h1 {
		margin: var(--space-sm) 0 var(--space-md);
	}
	.results h2 {
		margin: var(--space-lg) 0 var(--space-sm);
		font-size: 1.1rem;
	}
	.state-msg {
		margin-top: var(--space-lg);
		color: var(--color-text-secondary);
	}
	.result-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.result {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
	}
	.result:hover {
		border-color: var(--color-primary);
	}
	.result:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.result-kind {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.result-title {
		font-weight: 700;
	}
	.result-summary {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
</style>
