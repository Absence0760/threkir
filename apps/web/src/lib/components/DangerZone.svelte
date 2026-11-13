<script lang="ts">
	import type { Snippet } from 'svelte';
	import SectionHeader from '#lib/components/SectionHeader.svelte';

	interface Props {
		heading: string;
		description: string;
		children: Snippet;
	}

	let { heading, description, children }: Props = $props();
	const headingId = $props.id();
</script>

<section class="danger-zone" aria-labelledby={headingId}>
	<SectionHeader label={heading} id={headingId} tone="danger" />
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
