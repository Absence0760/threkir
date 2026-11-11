<script lang="ts">
	// A group's members and what its owner and admins can do to them (issue
	// #1365 slice 2, group_messages.md § 2). Removal and handing over ownership
	// cannot be taken back from here, so each is confirmed; a role change is one
	// tap back and runs at once (conventions.md § Destructive actions). The
	// server decides every action; this only hides what it would refuse.
	import Modal from './Modal.svelte';
	import ConfirmDialog from './ConfirmDialog.svelte';
	import GroupPeoplePicker from './GroupPeoplePicker.svelte';
	import Avatar from './Avatar.svelte';
	import { hashHue } from '#lib/format/avatar.ts';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { clubRoleLabel } from '#lib/i18n/enum_labels.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import {
		inviteToGroup,
		removeGroupMember,
		renameGroup,
		setGroupMemberRole,
		transferGroupOwnership,
		type GroupMember,
	} from '#lib/core/data.ts';
	import {
		GROUP_TITLE_MAX,
		canChangeGroupRoles,
		canManageGroup,
		canRemoveGroupMember,
		groupSeatsLeft,
		normalizeGroupTitle,
		sortGroupMembers,
		type GroupRole,
	} from '#lib/social/group_messages.ts';

	interface Props {
		open: boolean;
		conversationId: string;
		title: string;
		members: GroupMember[];
		me: string | null;
		onclose: () => void;
		/// After any change, so the thread re-reads the roster and the title.
		onchanged: () => void | Promise<void>;
	}

	let { open, conversationId, title, members, me, onclose, onchanged }: Props = $props();

	const myRole = $derived<GroupRole | null>(members.find((x) => x.userId === me && x.state === 'active')?.role ?? null);
	const sorted = $derived(sortGroupMembers(members));
	const active = $derived(members.filter((x) => x.state === 'active'));
	const pending = $derived(members.filter((x) => x.state === 'invited'));
	const seats = $derived(groupSeatsLeft(active.length, pending.length));
	const inGroup = $derived(new Set(members.map((x) => x.userId)));

	let busy = $state(false);
	let inviting = $state(false);
	let invitees = $state<string[]>([]);
	let renaming = $state(false);
	let draftTitle = $state('');
	let removeTarget = $state<GroupMember | null>(null);
	let transferTarget = $state<GroupMember | null>(null);

	$effect(() => {
		if (open) return;
		inviting = false;
		invitees = [];
		renaming = false;
		removeTarget = null;
		transferTarget = null;
	});

	function nameOf(x: GroupMember): string {
		return x.name ?? tr('messages.runnerFallback');
	}

	function roleLabel(x: GroupMember): string {
		if (x.state === 'invited') return tr('groups.roleInvited');
		// The same three words a club role reads as, from the one vocabulary.
		return clubRoleLabel(x.role ?? 'member');
	}

	async function run(action: () => Promise<void>, success: string, failKey: 'groups.actionFailed') {
		if (busy) return false;
		busy = true;
		try {
			await action();
			showToast(success, 'success');
			await onchanged();
			return true;
		} catch (e) {
			showToast(tr(failKey, { error: errorCopy(e, tr, failKey) }), 'error');
			return false;
		} finally {
			busy = false;
		}
	}

	async function sendInvites() {
		const ids = invitees;
		if (ids.length === 0) return;
		const ok = await run(
			async () => {
				await inviteToGroup(conversationId, ids);
			},
			tr('groups.invitedToast', { count: ids.length }),
			'groups.actionFailed',
		);
		if (ok) {
			inviting = false;
			invitees = [];
		}
	}

	async function saveTitle(e: SubmitEvent) {
		e.preventDefault();
		const next = normalizeGroupTitle(draftTitle);
		if (next === null) return;
		const ok = await run(() => renameGroup(conversationId, next), tr('groups.renamedToast'), 'groups.actionFailed');
		if (ok) renaming = false;
	}

	function setRole(x: GroupMember, role: 'admin' | 'member') {
		void run(
			() => setGroupMemberRole(conversationId, x.userId, role),
			role === 'admin' ? tr('groups.madeAdminToast', { name: nameOf(x) }) : tr('groups.removedAdminToast', { name: nameOf(x) }),
			'groups.actionFailed',
		);
	}

	async function confirmRemove() {
		const x = removeTarget;
		removeTarget = null;
		if (!x) return;
		await run(
			() => removeGroupMember(conversationId, x.userId),
			x.state === 'invited' ? tr('groups.inviteCancelledToast', { name: nameOf(x) }) : tr('groups.removedToast', { name: nameOf(x) }),
			'groups.actionFailed',
		);
	}

	async function confirmTransfer() {
		const x = transferTarget;
		transferTarget = null;
		if (!x) return;
		await run(() => transferGroupOwnership(conversationId, x.userId), tr('groups.transferredToast', { name: nameOf(x) }), 'groups.actionFailed');
	}
</script>

<Modal {open} {onclose} title={tr('groups.membersTitle', { count: active.length })} narrow data-testid="group-members-sheet">
	{#if canManageGroup(myRole)}
		<div class="manage">
			{#if renaming}
				<form class="rename" onsubmit={saveTitle}>
					<label class="visually-hidden" for="group-rename-input">{tr('groups.titleLabel')}</label>
					<input
						id="group-rename-input"
						type="text"
						bind:value={draftTitle}
						maxlength={GROUP_TITLE_MAX}
						data-testid="group-rename-input"
					/>
					<button type="submit" class="btn btn-primary btn-sm" disabled={busy || normalizeGroupTitle(draftTitle) === null} data-testid="group-rename-save">
						{tr('groups.renameSave')}
					</button>
					<button type="button" class="btn btn-secondary btn-sm" onclick={() => (renaming = false)}>
						{tr('profile.cancel')}
					</button>
				</form>
			{:else}
				<button
					type="button"
					class="btn btn-secondary btn-sm"
					data-testid="group-rename"
					onclick={() => {
						draftTitle = title;
						renaming = true;
					}}
				>
					<span class="material-symbols" aria-hidden="true">edit</span>{tr('groups.rename')}
				</button>
			{/if}
			{#if !inviting}
				<button
					type="button"
					class="btn btn-secondary btn-sm"
					data-testid="group-invite-more"
					disabled={seats === 0}
					onclick={() => (inviting = true)}
				>
					<span class="material-symbols" aria-hidden="true">person_add</span>{tr('groups.inviteMore')}
				</button>
			{/if}
		</div>
		{#if inviting}
			<div class="inviting" data-testid="group-invite-panel">
				<GroupPeoplePicker bind:selected={invitees} exclude={inGroup} max={seats} disabled={busy} />
				<div class="row-actions">
					<button type="button" class="btn btn-secondary btn-sm" onclick={() => (inviting = false)}>
						{tr('profile.cancel')}
					</button>
					<button
						type="button"
						class="btn btn-primary btn-sm"
						disabled={busy || invitees.length === 0}
						data-testid="group-invite-send"
						onclick={() => void sendInvites()}
					>
						{tr('groups.inviteSend', { count: invitees.length })}
					</button>
				</div>
			</div>
		{/if}
	{/if}

	<ul class="members" data-testid="group-members">
		{#each sorted as x (x.userId)}
			<li class="member" data-testid="group-member" data-user-id={x.userId} data-role={x.role ?? 'invited'}>
				<Avatar url={x.avatarUrl} name={x.name} size="2rem" font="0.85rem" bg="seed" seedHue={hashHue(x.userId)} />
				<span class="who">
					<a href={`/u/${x.userId}`}>{nameOf(x)}{x.userId === me ? ` ${tr('groups.youSuffix')}` : ''}</a>
					<span class="role">{roleLabel(x)}</span>
				</span>
				{#if x.userId !== me}
					<span class="row-actions">
						{#if canChangeGroupRoles(myRole) && x.state === 'active' && x.role !== 'owner'}
							{#if x.role === 'admin'}
								<button type="button" class="link-action" disabled={busy} onclick={() => setRole(x, 'member')} data-testid="group-member-demote">
									{tr('groups.removeAdmin')}
								</button>
							{:else}
								<button type="button" class="link-action" disabled={busy} onclick={() => setRole(x, 'admin')} data-testid="group-member-promote">
									{tr('groups.makeAdmin')}
								</button>
							{/if}
							<button type="button" class="link-action" disabled={busy} onclick={() => (transferTarget = x)} data-testid="group-member-transfer">
								{tr('groups.makeOwner')}
							</button>
						{/if}
						{#if canRemoveGroupMember(myRole, me, x)}
							<button type="button" class="link-action danger" disabled={busy} onclick={() => (removeTarget = x)} data-testid="group-member-remove">
								{x.state === 'invited' ? tr('groups.cancelInvite') : tr('groups.remove')}
							</button>
						{/if}
					</span>
				{/if}
			</li>
		{/each}
	</ul>
</Modal>

<ConfirmDialog
	open={removeTarget !== null}
	danger
	title={removeTarget?.state === 'invited'
		? tr('groups.cancelInviteConfirmTitle', { name: removeTarget ? nameOf(removeTarget) : '' })
		: tr('groups.removeConfirmTitle', { name: removeTarget ? nameOf(removeTarget) : '' })}
	message={removeTarget?.state === 'invited' ? tr('groups.cancelInviteConfirmMessage') : tr('groups.removeConfirmMessage')}
	confirmLabel={removeTarget?.state === 'invited' ? tr('groups.cancelInvite') : tr('groups.remove')}
	cancelLabel={tr('profile.cancel')}
	onconfirm={confirmRemove}
	oncancel={() => (removeTarget = null)}
	data-testid="group-remove-confirm"
/>

<ConfirmDialog
	open={transferTarget !== null}
	danger
	title={tr('groups.transferConfirmTitle', { name: transferTarget ? nameOf(transferTarget) : '' })}
	message={tr('groups.transferConfirmMessage')}
	confirmLabel={tr('groups.makeOwner')}
	cancelLabel={tr('profile.cancel')}
	onconfirm={confirmTransfer}
	oncancel={() => (transferTarget = null)}
	data-testid="group-transfer-confirm"
/>

<style>
	.manage {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin-bottom: var(--space-sm);
	}
	.manage .material-symbols {
		font-size: 1rem;
		margin-inline-end: 0.25rem;
	}
	.rename {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		width: 100%;
	}
	.rename input {
		flex: 1 1 12rem;
		min-width: 0;
		font: inherit;
		padding: 0.4rem 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		color: var(--color-text);
	}
	.inviting {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-sm);
		margin-bottom: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.members {
		list-style: none;
		margin: 0;
		padding: 0;
	}
	.member {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) 0;
		border-bottom: 1px solid var(--color-border);
		flex-wrap: wrap;
	}
	.who {
		display: flex;
		flex-direction: column;
		min-width: 0;
		flex: 1 1 8rem;
	}
	.who a {
		color: var(--color-text);
		font-weight: 600;
		text-decoration: none;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.role {
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.row-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
	.link-action {
		background: none;
		border: none;
		min-height: 2.75rem;
		padding: 0 0.25rem;
		font: inherit;
		font-size: 0.85rem;
		color: var(--color-primary);
		text-decoration: underline;
		cursor: pointer;
	}
	.link-action.danger {
		color: var(--color-danger-text);
	}
	.link-action:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.link-action:focus-visible {
		outline: 2px solid currentColor;
		outline-offset: 2px;
	}
</style>
