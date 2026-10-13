<script lang="ts">
	/// One help guide (docs/features/help.md). Guide text is plain strings with
	/// a small markup that `HelpRichText` renders from parsed tokens, so nothing
	/// here is {@html}. Section anchors come from `sectionId`, the same function
	/// the guard checks for uniqueness.
	import { page } from '$app/state';
	import { guideFor } from '#lib/help/index.ts';
	import { sectionId } from '#lib/help/markup.ts';
	import { KIND_LABEL, PLATFORM_LABEL, REQUIREMENT_LABEL } from '#lib/help/labels.ts';
	import HelpRichText from '#lib/components/help/HelpRichText.svelte';
	import { currentLocale, m } from '#lib/i18n/store.svelte.ts';

	const id = $derived(page.params.id ?? '');
	const guide = $derived(guideFor(id));
	const related = $derived((guide?.related ?? []).map((r) => guideFor(r)).filter((g) => g !== undefined));
</script>

<svelte:head>
	<title>{guide ? `${guide.title} — ${m('help.pageTitle')}` : m('help.pageTitle')}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="help-guide-page">
	<a class="back-link" href="/help">
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('help.allGuides')}
	</a>

	{#if !guide}
		<h1>{m('help.notFoundTitle')}</h1>
		<p>{m('help.notFoundBody', { id })}</p>
	{:else}
		<!-- Guide text is English-only for now (docs/features/help.md), so it
		     carries lang="en" while the chrome around it follows the app locale. -->
		<article class="guide" data-testid="help-guide">
			<header class="guide-header">
				<p class="guide-kind">{m(KIND_LABEL[guide.kind])}</p>
				<h1 lang="en">{guide.title}</h1>
				<p class="lede" lang="en">{guide.summary}</p>
				<dl class="badges">
					<div class="badge-row">
						<dt>{m('help.platformsLabel')}</dt>
						{#each guide.platforms as p (p)}
							<dd class="badge">{m(PLATFORM_LABEL[p])}</dd>
						{/each}
					</div>
					{#if guide.requires?.length}
						<div class="badge-row">
							<dt>{m('help.requiresLabel')}</dt>
							{#each guide.requires as r (r)}
								<dd class="badge badge-requires">{m(REQUIREMENT_LABEL[r])}</dd>
							{/each}
						</div>
					{/if}
				</dl>
			</header>

			{#if guide.sections.length > 1}
				<nav class="on-page" aria-labelledby="help-on-page">
					<h2 id="help-on-page" class="on-page-title">{m('help.onThisPage')}</h2>
					<ul>
						{#each guide.sections as s (s.heading)}
							<li><a href="#{sectionId(s.heading)}" lang="en">{s.heading}</a></li>
						{/each}
					</ul>
				</nav>
			{/if}

			{#each guide.sections as s (s.heading)}
				<section aria-labelledby={sectionId(s.heading)} lang="en">
					<h2 id={sectionId(s.heading)} tabindex="-1">{s.heading}</h2>
					{#each s.blocks as b, i (i)}
						{#if b.type === 'p'}
							<p><HelpRichText text={b.text} /></p>
						{:else if b.type === 'steps'}
							<ol class="steps">
								{#each b.items as item, j (j)}<li><HelpRichText text={item} /></li>{/each}
							</ol>
						{:else if b.type === 'list'}
							<ul class="list">
								{#each b.items as item, j (j)}<li><HelpRichText text={item} /></li>{/each}
							</ul>
						{:else if b.type === 'note'}
							<aside class="note note-{b.tone}">
								<strong class="note-tag" lang={currentLocale()}>{b.tone === 'tip' ? m('help.noteTip') : m('help.noteCaution')}</strong>
								<p><HelpRichText text={b.text} /></p>
							</aside>
						{/if}
					{/each}
				</section>
			{/each}

			{#if related.length}
				<nav class="related" aria-labelledby="help-related">
					<h2 id="help-related">{m('help.related')}</h2>
					<ul lang="en">
						{#each related as r (r.id)}
							<li>
								<a href="/help/{r.id}">{r.title}</a>
								<span class="related-summary">{r.summary}</span>
							</li>
						{/each}
					</ul>
				</nav>
			{/if}
		</article>
	{/if}
</div>

<style>
	.help-guide-page {
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
	.guide-header h1 {
		margin: 0 0 var(--space-xs);
	}
	.guide-kind {
		margin: var(--space-md) 0 var(--space-2xs);
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.lede {
		margin: 0 0 var(--space-md);
		font-size: 1.05rem;
		color: var(--color-text-secondary);
	}
	.badges {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		margin: 0 0 var(--space-lg);
	}
	.badge-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs);
	}
	.badge-row dt {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.badge {
		margin: 0;
		padding: 0.15rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		font-size: 0.85rem;
		color: var(--color-text);
		background: var(--color-surface);
	}
	.badge-requires {
		border-color: var(--color-primary);
	}
	.on-page {
		margin: 0 0 var(--space-lg);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.on-page-title {
		margin: 0 0 var(--space-xs);
		font-size: 0.9rem;
	}
	.on-page ul {
		margin: 0;
		padding-inline-start: var(--space-lg);
	}
	.on-page li {
		margin: var(--space-2xs) 0;
	}
	section h2 {
		margin: var(--space-xl) 0 var(--space-sm);
		font-size: 1.2rem;
		scroll-margin-top: var(--space-lg);
	}
	section p,
	section li {
		line-height: 1.6;
	}
	.steps,
	.list {
		padding-inline-start: var(--space-lg);
	}
	.steps li,
	.list li {
		margin: var(--space-xs) 0;
	}
	.note {
		margin: var(--space-md) 0;
		padding: var(--space-sm) var(--space-md);
		border-inline-start: 4px solid var(--color-primary);
		border-radius: var(--radius-sm);
		background: var(--color-bg-tertiary);
	}
	.note-caution {
		border-inline-start-color: var(--color-warning-strong);
	}
	.note p {
		margin: var(--space-2xs) 0 0;
	}
	.note-tag {
		font-size: 0.85rem;
	}
	.related {
		margin-top: var(--space-xl);
	}
	.related h2 {
		font-size: 1.1rem;
	}
	.related ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.related a {
		font-weight: 600;
	}
	.related-summary {
		display: block;
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
</style>
