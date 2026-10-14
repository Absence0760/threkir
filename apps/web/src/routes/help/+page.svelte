<script lang="ts">
	/// The in-app help contents (docs/features/help.md): every guide, grouped by
	/// category, narrowed by who it is written for. Signed-in only and never
	/// indexed — the public, crawlable guides are /learn, a different surface.
	import { AUDIENCES, type Audience } from '#lib/help/index.ts';
	import { helpIndex } from '#lib/help/localized.svelte.ts';
	import { AUDIENCE_LABEL, CATEGORY_LABEL, KIND_LABEL } from '#lib/help/labels.ts';
	import HelpSearchForm from '#lib/components/help/HelpSearchForm.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	// A guide for everyone is a guide for each group, so it stays listed under
	// every chip; the chips themselves are the narrower groups.
	const CHIPS = AUDIENCES.filter((a) => a !== 'everyone');

	let audience = $state<Audience | null>(null);

	const groups = $derived(
		helpIndex()
			.guidesByCategory()
			.map((group) => ({
				...group,
				guides: group.guides.filter(
					(g) => audience === null || g.audience.includes(audience) || g.audience.includes('everyone'),
				),
			}))
			.filter((group) => group.guides.length > 0),
	);
</script>

<svelte:head>
	<title>{m('help.pageTitle')}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="help-page">
	<header class="help-header">
		<h1>{m('help.title')}</h1>
		<p class="subtitle">{m('help.intro')}</p>
	</header>

	<HelpSearchForm />

	<div class="audience-row">
		<span id="help-audience-label" class="audience-label">{m('help.audienceFilter')}</span>
		<div class="chips" role="group" aria-labelledby="help-audience-label">
			<button
				type="button"
				class="chip"
				class:active={audience === null}
				aria-pressed={audience === null}
				onclick={() => (audience = null)}
			>
				{m('help.audienceAll')}
			</button>
			{#each CHIPS as a (a)}
				<button
					type="button"
					class="chip"
					class:active={audience === a}
					aria-pressed={audience === a}
					onclick={() => (audience = a)}
				>
					{m(AUDIENCE_LABEL[a])}
				</button>
			{/each}
		</div>
	</div>

	{#if groups.length === 0}
		<p class="empty">{m('help.noGuidesForAudience')}</p>
	{/if}

	{#each groups as group (group.category)}
		<section class="category" aria-labelledby="help-category-{group.category}">
			<h2 id="help-category-{group.category}">{m(CATEGORY_LABEL[group.category])}</h2>
			<ul class="guide-list">
				{#each group.guides as guide (guide.id)}
					<li>
						<a class="guide-card" href="/help/{guide.id}" data-testid="help-guide-card">
							<span class="guide-kind">{m(KIND_LABEL[guide.kind])}</span>
							<span class="guide-title" lang={guide.lang}>{guide.title}</span>
							<span class="guide-summary" lang={guide.lang}>{guide.summary}</span>
						</a>
					</li>
				{/each}
			</ul>
		</section>
	{/each}
</div>

<style>
	.help-page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 64rem;
	}
	.help-header h1 {
		margin: 0 0 var(--space-xs);
	}
	.subtitle {
		margin: 0;
		color: var(--color-text-secondary);
	}
	.audience-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
		margin: var(--space-lg) 0;
	}
	.audience-label {
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.chips {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
	}
	.chip {
		appearance: none;
		min-height: 2.25rem;
		border: 1.5px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		padding: 0.35rem 0.8rem;
		border-radius: 999px;
		font-size: 0.875rem;
		cursor: pointer;
	}
	.chip.active {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	.chip:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.empty {
		color: var(--color-text-secondary);
	}
	.category {
		margin-top: var(--space-xl);
	}
	.category h2 {
		margin: 0 0 var(--space-sm);
		font-size: 1.15rem;
	}
	.guide-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(100%, 18rem), 1fr));
		gap: var(--space-sm);
	}
	.guide-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		height: 100%;
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
	}
	.guide-card:hover {
		border-color: var(--color-primary);
	}
	.guide-card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.guide-kind {
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.guide-title {
		font-weight: 700;
	}
	.guide-summary {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
</style>
