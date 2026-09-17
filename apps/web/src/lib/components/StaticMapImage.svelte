<script lang="ts">
	import type { Snippet } from 'svelte';

	/// Every static-map `<img>` on web renders through here. The picture is
	/// decoration over a card that already works without it (an L3 map layer
	/// over an L1 card, conventions.md § Layered resilience), so a request
	/// that fails — a MapTiler outage, a revoked key, a blocked host — renders
	/// `fallback` instead of a broken image, or nothing when there is none.
	///
	/// The failure is keyed to the URL that failed rather than held as a flag,
	/// so a new URL (a different track, a consent change that switches the
	/// source) gets its own attempt.
	///
	/// `frame` wraps the image when it renders and is dropped with it, for a
	/// caller whose image sits inside a link that would otherwise be left
	/// behind empty.
	let {
		src,
		alt,
		class: className,
		testid,
		lazy = false,
		crossorigin,
		fallback,
		frame,
	}: {
		src: string;
		alt: string;
		class?: string;
		testid?: string;
		lazy?: boolean;
		crossorigin?: 'anonymous';
		fallback?: Snippet;
		frame?: Snippet<[Snippet]>;
	} = $props();

	let failedSrc = $state<string | null>(null);
</script>

{#snippet image()}
	<img
		{src}
		{alt}
		class={className}
		loading={lazy ? 'lazy' : 'eager'}
		decoding="async"
		{crossorigin}
		data-testid={testid}
		onerror={() => (failedSrc = src)}
	/>
{/snippet}

{#if failedSrc === src}
	{@render fallback?.()}
{:else if frame}
	{@render frame(image)}
{:else}
	{@render image()}
{/if}
