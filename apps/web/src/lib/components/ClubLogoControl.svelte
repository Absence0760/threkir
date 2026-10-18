<script lang="ts">
	import AvatarCropDialog from './AvatarCropDialog.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import { uploadClubLogo, removeClubLogo } from '#lib/core/data.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { AVATAR_SOURCE_MAX_BYTES } from '#lib/util/avatar_render.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	interface Props {
		clubId: string;
		hasLogo: boolean;
		onchange: (url: string | null) => void;
	}

	let { clubId, hasLogo, onchange }: Props = $props();

	let fileInput = $state<HTMLInputElement | null>(null);
	// The picked file waits here while the crop dialog is open; only the
	// cropped, re-encoded square is uploaded.
	let cropFile = $state<File | null>(null);
	let busy = $state(false);
	let showRemoveConfirm = $state(false);

	function handleSelect(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		if (file.size > AVATAR_SOURCE_MAX_BYTES) {
			showToast(m('clubLogo.failed', { error: m('avatarCrop.tooLarge') }), 'error');
			return;
		}
		cropFile = file;
	}

	async function handleCropped(cropped: File) {
		cropFile = null;
		busy = true;
		try {
			onchange(await uploadClubLogo(clubId, cropped));
			showToast(m('clubLogo.saved'), 'success');
		} catch (err) {
			showToast(m('clubLogo.failed', { error: thrownMessage(err) }), 'error');
		} finally {
			busy = false;
		}
	}

	// The delete hits Storage and cannot be undone, so it confirms first.
	async function handleRemove() {
		showRemoveConfirm = false;
		busy = true;
		try {
			await removeClubLogo(clubId);
			onchange(null);
			showToast(m('clubLogo.removed'), 'success');
		} catch (err) {
			showToast(m('clubLogo.failed', { error: thrownMessage(err) }), 'error');
		} finally {
			busy = false;
		}
	}
</script>

<div class="logo-actions" data-testid="club-logo-control">
	<input
		bind:this={fileInput}
		type="file"
		accept="image/jpeg,image/png,image/webp"
		onchange={handleSelect}
		hidden
		data-testid="club-logo-file-input"
	/>
	<button
		type="button"
		class="btn btn-outline btn-sm"
		onclick={() => fileInput?.click()}
		disabled={busy}
		data-testid="club-logo-change"
	>
		<span class="material-symbols" aria-hidden="true">photo_camera</span>
		{busy ? m('clubLogo.uploading') : hasLogo ? m('clubLogo.change') : m('clubLogo.add')}
	</button>
	{#if hasLogo}
		<button
			type="button"
			class="btn btn-outline btn-sm"
			onclick={() => (showRemoveConfirm = true)}
			disabled={busy}
			data-testid="club-logo-remove"
		>
			{m('clubLogo.remove')}
		</button>
	{/if}
</div>

<AvatarCropDialog
	file={cropFile}
	title={m('clubLogo.cropTitle')}
	onconfirm={handleCropped}
	oncancel={() => (cropFile = null)}
/>

<ConfirmDialog
	open={showRemoveConfirm}
	title={m('clubLogo.removeConfirmTitle')}
	message={m('clubLogo.removeConfirmMessage')}
	confirmLabel={m('clubLogo.remove')}
	onconfirm={handleRemove}
	oncancel={() => (showRemoveConfirm = false)}
	danger
/>

<style>
	.logo-actions {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 0.4rem;
	}
</style>
