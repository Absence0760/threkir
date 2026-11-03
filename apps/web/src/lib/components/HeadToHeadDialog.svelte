<script lang="ts">
	// The head-to-head card on its own, for a page with no run of the caller's
	// in hand: the route page and the segment pages. Run detail opens the same
	// panel as the Versus style of its share dialog instead.
	import Modal from '#lib/components/Modal.svelte';
	import HeadToHeadPanel from '#lib/components/HeadToHeadPanel.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { HeadToHeadKind } from '#lib/social/head_to_head.ts';

	interface Props {
		open: boolean;
		onclose: () => void;
		kind: HeadToHeadKind;
		targetId: string;
	}

	let { open, onclose, kind, targetId }: Props = $props();
</script>

<Modal {open} {onclose} title={m('headToHead.title')} wide data-testid="head-to-head-dialog">
	{#if open}
		<HeadToHeadPanel {kind} {targetId} />
	{/if}
</Modal>
