<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { HTMLAttributes } from 'svelte/elements';

	// The whole-surface "nothing here" card: icon, heading, explainer, actions.
	// It spans the content width like every other block on an uncapped list
	// page (conventions.md § Web page padding) and caps only its prose.
	// `body` replaces `text` when the explainer needs markup (a link);
	// `children` renders below the actions for content that belongs inside
	// the card, such as a row of starter tiles.
	let {
		icon,
		title,
		text,
		headingLevel = 2,
		tone = 'neutral',
		body,
		actions,
		children,
		class: className = '',
		...rest
	}: {
		icon: string;
		title: string;
		text?: string;
		headingLevel?: 2 | 3;
		tone?: 'neutral' | 'danger';
		body?: Snippet;
		actions?: Snippet;
		children?: Snippet;
		class?: string;
	} & Omit<HTMLAttributes<HTMLDivElement>, 'title' | 'children' | 'class'> = $props();
</script>

<div class="empty-state {className}" class:danger={tone === 'danger'} {...rest}>
	<span class="material-symbols empty-state-icon" aria-hidden="true">{icon}</span>
	<svelte:element this={headingLevel === 3 ? 'h3' : 'h2'} class="empty-state-title">{title}</svelte:element>
	{#if body}
		<div class="empty-state-text">{@render body()}</div>
	{:else if text}
		<p class="empty-state-text">{text}</p>
	{/if}
	{#if actions}
		<div class="empty-state-actions">{@render actions()}</div>
	{/if}
	{#if children}
		<div class="empty-state-extra">{@render children()}</div>
	{/if}
</div>

<style>
	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
		min-width: 0;
	}
	.empty-state-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 3.25rem;
		height: 3.25rem;
		border-radius: 50%;
		background: var(--color-bg-tertiary);
		font-size: 1.75rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-2xs);
	}
	.danger .empty-state-icon {
		background: var(--color-danger-light);
		color: var(--color-danger-text);
	}
	.empty-state-title {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
		color: var(--color-text);
	}
	.empty-state-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
		overflow-wrap: anywhere;
	}
	.empty-state-text :global(p) {
		margin: 0;
	}
	.empty-state-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.empty-state-actions :global(.material-symbols) {
		font-size: 1.1rem;
	}
	.empty-state-extra {
		align-self: stretch;
		margin-top: var(--space-md);
		padding-top: var(--space-lg);
		border-top: 1px solid var(--color-border);
		text-align: start;
	}
</style>
