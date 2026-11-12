<script lang="ts">
	/// The help search box. A plain GET form to /help/search, so the query lives
	/// in the URL: a search can be bookmarked, shared and gone back to.
	import { m } from '#lib/i18n/store.svelte.ts';

	let { query = '' }: { query?: string } = $props();
</script>

<form class="help-search" role="search" action="/help/search" method="get" data-testid="help-search">
	<label for="help-search-input" class="visually-hidden">{m('help.searchLabel')}</label>
	<input
		id="help-search-input"
		type="search"
		name="q"
		value={query}
		placeholder={m('help.searchLabel')}
		autocomplete="off"
	/>
	<button type="submit" class="btn btn-primary">
		<span class="material-symbols" aria-hidden="true">search</span>
		{m('help.searchSubmit')}
	</button>
</form>

<style>
	.help-search {
		display: flex;
		gap: var(--space-sm);
		max-width: 40rem;
	}
	.help-search input {
		flex: 1;
		min-width: 0;
		min-height: 2.75rem;
		padding: 0 var(--space-md);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 1rem;
	}
	.help-search input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}
	.help-search .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.help-search .material-symbols {
		font-size: 1.1rem;
	}
</style>
