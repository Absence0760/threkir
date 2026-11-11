<script lang="ts">
	// Grisnir's hop beside a run's one milestone line (first run, first 5K, a
	// badge, a new best, the longest yet). A still, decorative; the line is
	// the moment and stays dry. Never on a failed, unsaved or error state.
	import GrisnirArt from './GrisnirArt.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { MILESTONE_LINE, type MilestoneKind } from '#lib/mascot/mascot.ts';

	let { kind }: { kind: MilestoneKind } = $props();
</script>

<div class="grisnir-milestone" data-testid="run-milestone-grisnir" data-milestone={kind}>
	<GrisnirArt pose="proud" width="2.75rem" />
	<p>{m(MILESTONE_LINE[kind])}</p>
</div>

<style>
	.grisnir-milestone {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
	}
	p {
		margin: 0;
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-text);
	}
</style>
