<script lang="ts">
	import type { Snippet } from 'svelte';

	// A card in a list, the web twin of ui_kit's `ListCard` (conventions.md
	// § Web list cards; issue #1374). Same slots as mobile: either `children`
	// (any content inside the standard padding) or the row form — `leading`,
	// `title` with an optional `badge`, `subtitle`, `meta` under them, and
	// `trailing` or a `chevron` at the end — plus `actions` under the content.
	//
	// The card's link or button covers the whole card (its `::after` is
	// stretched over it), so a tap anywhere opens the item, while `trailing`
	// and `actions` sit above that layer and keep their own clicks. The link's
	// accessible name is what it contains: the leading, title, subtitle and
	// meta; `trailing` is read after it as its own text. `label` replaces that
	// name when the visible text is abbreviated.
	//
	// `page_chrome_guard.test.ts` fails a hand-built list card (a `.card`,
	// `.card-elevated` or `*-row` link inside an `{#each}`) on the routes it
	// has migrated.
	let {
		href,
		onclick,
		label,
		title,
		subtitle,
		leading,
		badge,
		meta,
		trailing,
		actions,
		children,
		chevron = false,
		selected = false,
		dense = false,
		flush = false,
		class: extra = '',
		testid,
	}: {
		href?: string;
		onclick?: () => void;
		label?: string;
		title?: string;
		subtitle?: string;
		leading?: Snippet;
		badge?: Snippet;
		meta?: Snippet;
		trailing?: Snippet;
		actions?: Snippet;
		children?: Snippet;
		chevron?: boolean;
		/// The card is in the current selection: tinted, and `aria-pressed` on
		/// its button.
		selected?: boolean;
		dense?: boolean;
		/// No padding, for content that runs to the card's edges.
		flush?: boolean;
		/// A page's own modifier, for layout or a test to find the card by.
		class?: string;
		testid?: string;
	} = $props();
</script>

{#snippet body()}
	{#if children}
		{@render children()}
	{:else}
		<span class="lc-row">
			{#if leading}<span class="lc-leading">{@render leading()}</span>{/if}
			<span class="lc-texts">
				<span class="lc-title-line">
					<span class="list-card-title">{title}</span>
					{#if badge}{@render badge()}{/if}
				</span>
				{#if subtitle}<span class="list-card-subtitle">{subtitle}</span>{/if}
				{#if meta}<span class="lc-meta">{@render meta()}</span>{/if}
			</span>
		</span>
	{/if}
{/snippet}

<div
	class="list-card {extra}"
	class:selected
	class:dense
	class:flush
	class:tappable={href != null || onclick != null}
	data-testid={testid}
>
	<div class="lc-top">
		{#if href != null}
			<a class="lc-tap" {href} aria-label={label}>{@render body()}</a>
		{:else if onclick}
			<button type="button" class="lc-tap" {onclick} aria-label={label} aria-pressed={selected || undefined}
				>{@render body()}</button
			>
		{:else}
			<div class="lc-tap">{@render body()}</div>
		{/if}
		{#if trailing || chevron}
			<span class="lc-end">
				{#if trailing}{@render trailing()}{/if}
				{#if chevron}<span class="material-symbols lc-chevron" aria-hidden="true">chevron_right</span>{/if}
			</span>
		{/if}
	</div>
	{#if actions}<div class="lc-actions">{@render actions()}</div>{/if}
</div>

<style>
	.list-card {
		position: relative;
		box-sizing: border-box;
		/* Fills a grid cell, so a row of cards lines up. */
		height: 100%;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-sm);
		color: var(--color-text);
		transition:
			border-color var(--transition-fast),
			box-shadow var(--transition-base);
		--lc-pad-y: var(--space-md);
		--lc-pad-x: var(--space-md);
	}
	.list-card.dense {
		--lc-pad-y: var(--space-sm);
	}
	.list-card.flush {
		--lc-pad-y: 0;
		--lc-pad-x: 0;
		overflow: hidden;
	}
	.list-card.tappable:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
	}
	.list-card.selected {
		background: var(--color-primary-light);
		border-color: var(--color-primary);
	}
	.lc-top {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--lc-pad-y) var(--lc-pad-x);
	}
	.lc-tap {
		flex: 1;
		min-width: 0;
		display: block;
		color: inherit;
		text-decoration: none;
		font: inherit;
		text-align: start;
		background: none;
		border: 0;
		padding: 0;
	}
	a.lc-tap,
	button.lc-tap {
		cursor: pointer;
	}
	/* The link covers the card; trailing and actions sit above it. */
	a.lc-tap::after,
	button.lc-tap::after {
		content: '';
		position: absolute;
		inset: 0;
		border-radius: inherit;
	}
	a.lc-tap:focus-visible,
	button.lc-tap:focus-visible {
		outline: none;
	}
	.list-card:has(.lc-tap:focus-visible) {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.lc-end,
	.lc-actions {
		position: relative;
		z-index: 1;
	}
	.lc-end {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-shrink: 0;
		max-width: 50%;
	}
	.lc-chevron {
		color: var(--color-text-secondary);
	}
	.lc-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		min-width: 0;
	}
	.lc-leading {
		flex-shrink: 0;
		display: flex;
	}
	.lc-texts {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.lc-title-line {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-xs) var(--space-sm);
		min-width: 0;
	}
	.list-card-title {
		font-weight: 600;
		font-size: 1rem;
		overflow-wrap: anywhere;
	}
	.list-card-subtitle {
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
	.lc-meta {
		display: block;
		margin-top: var(--space-xs);
	}
	.lc-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-sm);
		padding: 0 var(--space-md) var(--space-sm);
	}
</style>
