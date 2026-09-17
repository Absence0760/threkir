<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		heading: string;
		description: string;
		children: Snippet;
	}

	let { heading, description, children }: Props = $props();
	const headingId = $props.id();
</script>

<section class="danger-zone" aria-labelledby={headingId}>
	<h2 class="danger-zone-heading" id={headingId}>{heading}</h2>
	<p class="danger-zone-desc">{description}</p>
	<div class="danger-zone-actions">
		{@render children()}
	</div>
</section>

<style>
	.danger-zone {
		margin-block-start: var(--space-xl);
		padding: var(--space-lg);
		background: var(--color-surface);
		border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
		border-radius: var(--radius-lg);
	}
	.danger-zone-heading {
		margin: 0 0 var(--space-sm);
		font-size: 0.9rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-danger-text);
	}
	.danger-zone-desc {
		margin: 0 0 var(--space-md);
		font-size: 0.85rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
	}
	.danger-zone-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
	}
</style>
