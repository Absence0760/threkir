<script lang="ts">
	// The board note for a catalogue segment timed by its lines while some of
	// its efforts were still measured by the circles (issue #1308).
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		globalSegmentHasLines,
		globalSegmentHasZoneEfforts,
		type GlobalSegment,
	} from '#lib/core/data.ts';

	let { segment }: { segment: GlobalSegment } = $props();

	let show = $state(false);

	$effect(() => {
		const current = segment;
		show = false;
		if (!globalSegmentHasLines(current)) return;
		let live = true;
		void globalSegmentHasZoneEfforts(current.id).then((has) => {
			if (live) show = has;
		});
		return () => {
			live = false;
		};
	});
</script>

{#if show}
	<p class="old-match-note" data-testid="segment-old-match-note">
		<span class="material-symbols" aria-hidden="true">info</span>
		{m('segmentDetail.oldMatchNote')}
	</p>
{/if}

<style>
	.old-match-note {
		display: flex;
		gap: 0.5rem;
		align-items: flex-start;
		margin: 0 0 0.75rem;
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
	.old-match-note .material-symbols {
		font-size: 1.125rem;
	}
</style>
