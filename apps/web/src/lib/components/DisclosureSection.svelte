<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		/// Stable key: the persistence key for this section and the prefix of
		/// the heading id the region is named by.
		id: string;
		title: string;
		/// One short line saying what is inside, so a collapsed section can be
		/// judged without opening it.
		hint?: string;
		open: boolean;
		ontoggle: (open: boolean) => void;
		/// Class carried on the region so the host page keeps its own layout
		/// hooks (and the selectors its specs are written against).
		sectionClass?: string;
		children: Snippet;
	}

	const { id, title, hint, open, ontoggle, sectionClass = '', children }: Props = $props();
</script>

<section class="disclosure {sectionClass}" aria-labelledby="{id}-title">
	<!-- The reader's choice is read off the summary click, not the toggle
	     event. A toggle is queued for every change of `open`, the host's own
	     included, and a click can land on a <details> the page re-renders
	     away before that event fires, so the choice was lost (or a stale
	     element reported its old state). The click is the intent; the toggle
	     handler only catches the browser opening a section itself (find in
	     page), and only from a live element that disagrees with the prop. -->
	<details
		{open}
		ontoggle={(e) => {
			const el = e.currentTarget;
			if (el.isConnected && el.open !== open) ontoggle(el.open);
		}}
	>
		<summary
			class="disclosure-summary"
			onclick={(e) => {
				e.preventDefault();
				ontoggle(!open);
			}}
		>
			<span class="material-symbols disclosure-chevron" aria-hidden="true">expand_more</span>
			<h2 class="section-title" id="{id}-title">{title}</h2>
			{#if hint}
				<span class="disclosure-hint">{hint}</span>
			{/if}
		</summary>
		<div class="disclosure-body">
			{@render children()}
		</div>
	</details>
</section>

<style>
	.disclosure {
		margin-bottom: var(--space-md);
	}
	.disclosure-summary {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		padding: var(--space-2xs) 0;
		cursor: pointer;
		list-style: none;
		border-radius: var(--radius-sm);
	}
	.disclosure-summary::-webkit-details-marker {
		display: none;
	}
	.disclosure-summary:hover .section-title {
		color: var(--color-primary);
	}
	.disclosure-summary:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.disclosure-chevron {
		align-self: center;
		font-size: 1.1rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}
	details[open] .disclosure-chevron {
		transform: rotate(180deg);
	}
	.section-title {
		font-size: 0.85rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.disclosure-hint {
		font-size: var(--font-size-section-label);
		color: var(--color-text-tertiary);
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.disclosure-body {
		padding-top: var(--space-sm);
	}
</style>
