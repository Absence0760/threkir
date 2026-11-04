<script lang="ts">
	// A placeholder rectangle for a part of a loading page — a map, a chart, a
	// row's title bar. Composed into the shape the page settles into so the
	// loaded frame fills the blocks instead of re-laying the page out
	// (decisions § 2288). Same shimmer as the page-local `.skel` rows on
	// /runs, /gym and /history, and frozen under reduced motion.
	//
	// Decorative: the host page announces the load once, through a
	// `role="status"` line, not once per block.
	let {
		height,
		width = '100%',
		radius = 'var(--radius-sm)',
	}: { height: string; width?: string; radius?: string } = $props();
</script>

<span
	class="skeleton-block"
	aria-hidden="true"
	style:height
	style:width
	style:border-radius={radius}
></span>

<style>
	.skeleton-block {
		display: block;
		flex-shrink: 0;
		max-width: 100%;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		animation: skeleton-shimmer 1.4s ease-in-out infinite;
	}
	@keyframes skeleton-shimmer {
		0% {
			background-position: 200% 0;
		}
		100% {
			background-position: -200% 0;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.skeleton-block {
			animation: none;
		}
	}
</style>
