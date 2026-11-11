<script lang="ts">
	// Create a group (issue #1365 slice 2, D1, D2): a title and at least two
	// people, who are invited, never added. The creator takes one of the 32
	// seats, so up to 31 can be invited.
	import { goto } from '$app/navigation';
	import Modal from './Modal.svelte';
	import GroupPeoplePicker from './GroupPeoplePicker.svelte';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { messagesInbox } from '#lib/stores/messages_inbox.svelte.ts';
	import { createGroupConversation } from '#lib/core/data.ts';
	import {
		GROUP_MIN_INVITEES,
		groupSeatsLeft,
		normalizeGroupTitle,
	} from '#lib/social/group_messages.ts';

	let { open, onclose }: { open: boolean; onclose: () => void } = $props();

	let title = $state('');
	let selected = $state<string[]>([]);
	let busy = $state(false);
	let error = $state<string | null>(null);

	const normalized = $derived(normalizeGroupTitle(title));
	// Empty is the untouched state, which `required` and the disabled submit
	// already answer; only a title that is too long earns the message.
	const titleTooLong = $derived(normalized === null && title.trim() !== '');
	const ready = $derived(normalized !== null && selected.length >= GROUP_MIN_INVITEES);

	$effect(() => {
		if (open) return;
		title = '';
		selected = [];
		busy = false;
		error = null;
	});

	async function create(e: SubmitEvent) {
		e.preventDefault();
		if (!ready || busy || normalized === null) return;
		busy = true;
		error = null;
		try {
			const id = await createGroupConversation(normalized, selected);
			showToast(tr('groups.createdToast', { title: normalized }), 'success');
			await messagesInbox.refreshThreads();
			onclose();
			await goto(`/messages/group/${id}`);
		} catch (err) {
			error = errorCopy(err, tr, 'groups.createFailed', 'groups.createFailed');
		} finally {
			busy = false;
		}
	}
</script>

<Modal {open} {onclose} title={tr('groups.createTitle')} narrow data-testid="group-create-dialog">
	<form onsubmit={create}>
		<label class="field">
			<span>{tr('groups.titleLabel')}</span>
			<!-- No maxlength: it counts UTF-16 units, so it would stop a valid
			     title of 31 emoji that the server, counting characters, takes. -->
			<input
				type="text"
				bind:value={title}
				required
				autocomplete="off"
				aria-invalid={titleTooLong}
				aria-describedby={titleTooLong ? 'group-title-error' : undefined}
				data-testid="group-title-input"
			/>
		</label>
		{#if titleTooLong}
			<p id="group-title-error" class="error" role="alert" data-testid="group-title-error">{tr('groups.titleInvalid')}</p>
		{/if}
		<p class="hint">{tr('groups.createHint')}</p>
		<GroupPeoplePicker bind:selected max={groupSeatsLeft(1, 0)} disabled={busy} />
		{#if error}<p class="error" role="alert" data-testid="group-create-error">{error}</p>{/if}
		<div class="actions">
			<button type="button" class="btn btn-secondary btn-sm" onclick={onclose} disabled={busy}>
				{tr('profile.cancel')}
			</button>
			<button type="submit" class="btn btn-primary btn-sm" disabled={!ready || busy} data-testid="group-create-submit">
				{busy ? tr('groups.creating') : tr('groups.createSubmit')}
			</button>
		</div>
	</form>
</Modal>

<style>
	form {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		font-weight: 600;
	}
	.field input {
		font: inherit;
		font-weight: 400;
		padding: 0.5rem 0.7rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
	}
	.hint {
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.error {
		margin: 0;
		color: var(--color-danger-text);
		font-size: 0.85rem;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
