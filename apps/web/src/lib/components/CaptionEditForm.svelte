<script lang="ts">
	import { untrack } from 'svelte';

	// The inline caption editor the run, route and club photo galleries share,
	// twin of mobile's CaptionEditor. It owns the typed text and stays open,
	// locked with Save busy, until the write settles: `onSave` answers whether
	// the caption was stored, and only a stored caption closes it. A failed
	// write keeps the text to retry (issue #1374 FS-11); the gallery reports
	// the failure in its own words.
	let {
		initial,
		placeholder,
		ariaLabel,
		saveLabel,
		cancelLabel,
		onSave,
		onClose
	}: {
		initial: string | null;
		placeholder: string;
		ariaLabel: string;
		saveLabel: string;
		cancelLabel: string;
		onSave: (caption: string | null) => Promise<boolean>;
		onClose: () => void;
	} = $props();

	// Seeded once from the photo's caption; the person's typing owns it after.
	let value = $state(untrack(() => initial ?? ''));
	let saving = $state(false);

	async function save(e: SubmitEvent) {
		e.preventDefault();
		if (saving) return;
		saving = true;
		const stored = await onSave(value.trim() || null);
		saving = false;
		if (stored) onClose();
	}
</script>

<form class="caption-edit" onsubmit={save} aria-busy={saving}>
	<input
		type="text"
		bind:value
		maxlength="280"
		readonly={saving}
		{placeholder}
		aria-label={ariaLabel}
	/>
	<button class="btn btn-primary btn-sm" type="submit" disabled={saving}>{saveLabel}</button>
	<button class="btn btn-secondary btn-sm" type="button" disabled={saving} onclick={onClose}>
		{cancelLabel}
	</button>
</form>

<style>
	.caption-edit {
		display: flex;
		flex-wrap: wrap;
		gap: 0.3rem;
	}

	.caption-edit input {
		flex: 1 1 100%;
		padding: 0.35rem 0.55rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		font-size: 0.85rem;
	}
</style>
