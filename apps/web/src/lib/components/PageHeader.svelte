<script lang="ts">
	import type { Snippet } from 'svelte';

	// A page's title block (issue #1374), one component instead of the
	// `.page-header` markup ~20 routes copied with their own drift: an optional
	// back link and kicker above the h1, a help link beside it, a subtitle and
	// any extra lines under it, and the page's actions at the end of the row.
	// `page_chrome_guard.test.ts` fails a copied `.page-header` anywhere else,
	// and a raw `<h1>` in a route page that is not on its allowlist.
	//
	// `flush` drops the bottom margin, for a page that spaces its blocks with
	// a flex gap instead. `back.onclick` takes a `smartBack()` handler, so the
	// link returns to the page the runner came from when there is one. The
	// `help` slot holds anything that belongs beside the title (a `HelpLink`,
	// an `OfficialBadge`). `testid` names the header; `titleTestid` the h1.
	let {
		title,
		kicker,
		subtitle,
		back,
		help,
		sub,
		actions,
		children,
		flush = false,
		testid,
		titleTestid,
	}: {
		title: string;
		kicker?: string;
		subtitle?: string;
		back?: { href: string; label: string; onclick?: (e: MouseEvent) => void };
		/// Rendered beside the h1: a `HelpLink`, an `OfficialBadge`.
		help?: Snippet;
		/// Replaces `subtitle` when the line needs markup.
		sub?: Snippet;
		actions?: Snippet;
		/// Extra lines under the subtitle (a note, a review link).
		children?: Snippet;
		flush?: boolean;
		testid?: string;
		titleTestid?: string;
	} = $props();
</script>

<header class="page-head" class:flush data-testid={testid ?? 'page-header'}>
	<div class="page-head-text">
		{#if back}
			<a class="page-head-back" href={back.href} onclick={back.onclick}>
				<span class="material-symbols" aria-hidden="true">arrow_back</span>
				{back.label}
			</a>
		{/if}
		{#if kicker}<p class="page-head-kicker" data-testid="page-header-kicker">{kicker}</p>{/if}
		<div class="page-head-title">
			<h1 data-testid={titleTestid}>{title}</h1>
			{#if help}{@render help()}{/if}
		</div>
		{#if sub}
			<div class="page-head-sub" data-testid="page-header-subtitle">{@render sub()}</div>
		{:else if subtitle}
			<p class="page-head-sub" data-testid="page-header-subtitle">{subtitle}</p>
		{/if}
		{#if children}{@render children()}{/if}
	</div>
	{#if actions}
		<div class="page-head-actions">{@render actions()}</div>
	{/if}
</header>

<style>
	.page-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--page-header-gap);
	}
	.page-head.flush {
		margin-bottom: 0;
	}
	.page-head-text {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-2xs);
		min-width: 0;
		flex: 1 1 18rem;
	}
	.page-head-back {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		min-height: 24px;
		font-size: 0.9rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		margin-bottom: var(--space-xs);
	}
	.page-head-back:hover {
		color: var(--color-primary);
	}
	.page-head-back .material-symbols {
		font-size: 1.1rem;
	}
	.page-head-kicker {
		margin: 0;
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.page-head-title {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-sm);
	}
	.page-head-title h1 {
		margin: 0;
		font-size: var(--font-size-page-title);
		font-weight: 700;
		line-height: 1.25;
	}
	.page-head-sub {
		margin: 0;
		max-width: 42rem;
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
	}
	.page-head-sub :global(p) {
		margin: 0;
	}
	.page-head-actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	.page-head-actions :global(.btn) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		text-decoration: none;
	}
	.page-head-actions :global(.material-symbols) {
		font-size: 1.1rem;
	}
</style>
