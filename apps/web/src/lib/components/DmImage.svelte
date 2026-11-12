<script lang="ts">
	import { onDestroy } from 'svelte';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { fetchDmImage, type DmImageView } from '#lib/core/data.ts';
	import { DM_IMAGE_FAST_CHECKS, DM_IMAGE_SIGNED_URL_SECONDS, dmImageRecheckMs } from '#lib/social/dm_image.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';

	let { imageId }: { imageId: string } = $props();

	let view = $state<DmImageView | null>(null);
	let failed = $state(false);
	let timer: ReturnType<typeof setTimeout> | null = null;
	let checks = 0;
	let current = '';

	function schedule(ms: number, id: string) {
		if (timer) clearTimeout(timer);
		timer = setTimeout(() => void load(id), ms);
	}

	/// Counts this check and says when the next one is due.
	function nextCheck(): number {
		return dmImageRecheckMs(++checks);
	}

	async function load(id: string) {
		try {
			const v = await fetchDmImage(id);
			if (id !== current) return;
			failed = v === null;
			view = v;
			if (v?.status === 'pending') schedule(nextCheck(), id);
			if (v?.status === 'ready') schedule((DM_IMAGE_SIGNED_URL_SECONDS - 60) * 1000, id);
		} catch (e) {
			if (id !== current) return;
			console.error('dm image read failed', thrownMessage(e));
			const next = nextCheck();
			// After the fast phase a photo that never loaded says so, and the
			// slow checks carry on in case the read comes back.
			if (checks >= DM_IMAGE_FAST_CHECKS && view?.status !== 'ready') failed = true;
			schedule(next, id);
		}
	}

	$effect(() => {
		current = imageId;
		checks = 0;
		view = null;
		failed = false;
		void load(imageId);
	});

	onDestroy(() => {
		if (timer) clearTimeout(timer);
	});
</script>

{#if view?.status === 'ready' && view.url}
	<a class="photo" href={view.url} target="_blank" rel="noopener noreferrer" data-testid="dm-photo">
		<img
			src={view.url}
			alt={tr('messages.photoAlt')}
			width={view.width ?? undefined}
			height={view.height ?? undefined}
			loading="lazy"
			referrerpolicy="no-referrer"
		/>
	</a>
{:else if view?.status === 'rejected'}
	<span class="photo-note" data-testid="dm-photo-rejected">{tr('messages.photoRejected')}</span>
{:else if failed}
	<span class="photo-note" data-testid="dm-photo-unavailable">{tr('messages.photoUnavailableToView')}</span>
{:else}
	<span class="photo-note pending" data-testid="dm-photo-pending">
		<span class="material-symbols" aria-hidden="true">hourglass_empty</span>{tr('messages.photoProcessing')}
	</span>
{/if}

<style>
	.photo {
		display: block;
		max-width: min(100%, 20rem);
	}
	.photo img {
		display: block;
		max-width: 100%;
		height: auto;
		border-radius: var(--radius-md, 0.5rem);
	}
	.photo-note {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		font-size: 0.85rem;
		opacity: 0.8;
	}
</style>
