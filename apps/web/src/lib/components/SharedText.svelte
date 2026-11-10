<script lang="ts">
	// AI text another user wrote: drawn as text nodes from typed blocks, never
	// through {@html}, so nothing in it can become markup (decisions § 110).
	import { parseSharedMarkdown, type SharedSpan } from '#lib/social/coach_share.ts';

	interface Props {
		text: string;
	}

	let { text }: Props = $props();

	const blocks = $derived(parseSharedMarkdown(text));
</script>

{#snippet spans(list: SharedSpan[])}
	{#each list as s, i (i)}
		{#if s.style === 'bold'}<strong>{s.text}</strong>{:else if s.style === 'italic'}<em>{s.text}</em
			>{:else if s.style === 'code'}<code>{s.text}</code>{:else}{s.text}{/if}
	{/each}
{/snippet}

<div class="shared-text">
	{#each blocks as b, i (i)}
		{#if b.type === 'heading'}
			<p class="heading">{@render spans(b.spans)}</p>
		{:else if b.type === 'bullet'}
			<p class="item"><span class="marker" aria-hidden="true">•</span><span>{@render spans(b.spans)}</span></p>
		{:else if b.type === 'ordered'}
			<p class="item"><span class="marker">{b.marker}</span><span>{@render spans(b.spans)}</span></p>
		{:else}
			<p>{@render spans(b.spans)}</p>
		{/if}
	{/each}
</div>

<style>
	.shared-text p {
		margin: 0 0 0.4rem;
		white-space: pre-line;
		overflow-wrap: anywhere;
	}
	.shared-text p:last-child {
		margin-bottom: 0;
	}
	.heading {
		font-weight: 700;
	}
	.item {
		display: flex;
		gap: 0.4rem;
	}
	.marker {
		flex: 0 0 auto;
		color: var(--color-text-secondary);
	}
	code {
		font-family: var(--font-mono, monospace);
		font-size: 0.9em;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm, 4px);
		padding: 0 0.2rem;
	}
</style>
