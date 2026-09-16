<script lang="ts">
	import { onMount } from 'svelte';
	import { motion } from '$lib/motion/motion.svelte';
	import { m } from '$lib/i18n/store.svelte';

	// WCAG 2.2.2: motion that starts by itself and runs past five seconds needs
	// a way to stop it. The accessible name stays constant and the state rides
	// on aria-pressed, so the visible label is always the name (2.5.3).
	//
	// Hidden under reduced motion — there is nothing moving to pause.
	//
	// Disabled until mounted: the prerendered button has no handler until
	// hydration, and a control that silently ignores a click is worse than one
	// that says it is not ready. Same pattern as /login's `hydrated` gate.
	let mounted = $state(false);
	onMount(() => {
		mounted = true;
	});
</script>

{#if !motion.reduced}
	<button
		type="button"
		class="motion-toggle"
		aria-pressed={motion.paused}
		disabled={!mounted}
		onclick={() => motion.setPaused(!motion.paused)}
	>
		<span class="material-symbols" aria-hidden="true">{motion.paused ? 'play_arrow' : 'pause'}</span>
		<span class="motion-toggle-label">{m('motion.pause')}</span>
	</button>
{/if}

<style>
	/* A fixed height below the Sign In pill's at every breakpoint (42px on a
	   desktop, 38px on a phone): the bar's height is set by the pill, and
	   learn/chrome.spec.ts holds the header to the same geometry on / and
	   /learn, where there is no toggle. */
	.motion-toggle {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		height: 2.25rem;
		padding: 0 var(--space-md) 0 var(--space-sm);
		border-radius: var(--radius-pill);
		border: 1px solid rgba(255, 255, 255, 0.25);
		background: rgba(255, 255, 255, 0.06);
		color: rgba(255, 255, 255, 0.85);
		font: inherit;
		font-size: 0.85rem;
		font-weight: 500;
		cursor: pointer;
		backdrop-filter: blur(8px);
		transition:
			border-color var(--transition-fast),
			background var(--transition-fast),
			color var(--transition-fast);
	}

	.motion-toggle:disabled {
		cursor: default;
	}

	.motion-toggle:hover:not(:disabled) {
		border-color: rgba(255, 255, 255, 0.6);
		background: rgba(255, 255, 255, 0.12);
		color: #FFFFFF;
	}

	.motion-toggle[aria-pressed='true'] {
		border-color: rgba(255, 255, 255, 0.6);
		color: #FFFFFF;
	}

	.motion-toggle .material-symbols {
		font-size: 1.25rem;
	}

	/* Icon-only on a phone, where the bar holds the wordmark and Sign In. The
	   label stays in the accessibility tree. */
	@media (max-width: 768px) {
		.motion-toggle {
			padding: 0;
			width: 2.25rem;
			justify-content: center;
		}
		.motion-toggle-label {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}
</style>
