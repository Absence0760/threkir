<script lang="ts">
	/// "How this works": the way from a screen to the help guide that explains
	/// it. Takes the screen's SvelteKit route id and links to every guide whose
	/// `routes` name it — straight to the guide when there is one, a short list
	/// when there are several, nothing when there are none.
	/// `help_guides_guard.test.ts` fails the unit job when a `route` here has no
	/// guide, so a mounted link never silently renders nothing.
	import { helpIndex } from '#lib/help/localized.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	let { route }: { route: string } = $props();
	const guides = $derived(helpIndex().guidesForRoute(route));
	const only = $derived(guides.length === 1 ? guides[0] : undefined);
</script>

{#if only}
	<a class="help-link" href="/help/{only.id}" data-testid="help-link">
		<span class="material-symbols" aria-hidden="true">help</span>
		{m('help.howThisWorks')}
	</a>
{:else if guides.length > 1}
	<details class="help-link-menu" data-testid="help-link">
		<summary class="help-link">
			<span class="material-symbols" aria-hidden="true">help</span>
			{m('help.howThisWorks')}
		</summary>
		<ul aria-label={m('help.guidesForThisPage')}>
			{#each guides as guide (guide.id)}
				<li><a href="/help/{guide.id}" lang={guide.lang}>{guide.title}</a></li>
			{/each}
		</ul>
	</details>
{/if}

<style>
	.help-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		min-height: 2.25rem;
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
		cursor: pointer;
	}
	.help-link:hover {
		text-decoration: underline;
	}
	.help-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
		border-radius: var(--radius-sm);
	}
	.help-link .material-symbols {
		font-size: 1.1rem;
	}
	.help-link-menu {
		position: relative;
		display: inline-block;
	}
	.help-link-menu summary {
		list-style: none;
	}
	.help-link-menu summary::-webkit-details-marker {
		display: none;
	}
	.help-link-menu ul {
		position: absolute;
		top: calc(100% + 0.25rem);
		inset-inline-start: 0;
		z-index: 60;
		min-width: 14rem;
		max-width: min(22rem, calc(100vw - 2rem));
		margin: 0;
		padding: var(--space-xs) 0;
		list-style: none;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-lg);
	}
	.help-link-menu li a {
		display: block;
		padding: var(--space-xs) var(--space-md);
		font-size: 0.875rem;
		color: var(--color-text);
		text-decoration: none;
	}
	.help-link-menu li a:hover,
	.help-link-menu li a:focus-visible {
		background: var(--color-bg-tertiary);
	}
</style>
