<script lang="ts">
	// A group conversation (issue #1365 slice 2, group_messages.md § 3,
	// decisions § 2463). Everything this page shows comes through the read rule
	// (private.can_read_message): an active member reads from the moment they
	// accepted, someone who left reads only their own messages, and the viewer's
	// own block leaves a placeholder where the blocked person's message was.
	// A group the viewer is not in, one that does not exist and one they left
	// without writing anything all read the same: not available.
	import { tick } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { hashHue } from '#lib/format/avatar.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { startVisiblePoll } from '#lib/core/visible_poll.ts';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { messagesInbox } from '#lib/stores/messages_inbox.svelte.ts';
	import { dmUnreadStore } from '#lib/stores/dm_unread.svelte.ts';
	import Avatar from '#lib/components/Avatar.svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import ReportDialog from '#lib/components/ReportDialog.svelte';
	import DmMessageText from '#lib/components/DmMessageText.svelte';
	import DmReactions from '#lib/components/DmReactions.svelte';
	import DmImage from '#lib/components/DmImage.svelte';
	import GroupMembersSheet from '#lib/components/GroupMembersSheet.svelte';
	import { AppError } from '#lib/core/app_error.ts';
	import {
		editDm,
		fetchDmImagesEnabled,
		fetchDmReactions,
		fetchGroupBlockedPlaceholders,
		fetchGroupMembers,
		fetchGroupMessagesEnabled,
		fetchGroupProfiles,
		fetchGroupThread,
		leaveGroup,
		markGroupRead,
		sendGroupMessage,
		setDmReaction,
		unsendDm,
		uploadDmImage,
		type DirectMessage,
		type GroupMember,
	} from '#lib/core/data.ts';
	import { DM_THREAD_POLL_MS, mergeDmMessages, mergeDmPollPage, type DmOrderKey } from '#lib/social/dm_thread.ts';
	import { mergeGroupThread, placeholdersSince } from '#lib/social/group_messages.ts';
	import { canEditDm } from '#lib/social/dm_edit.ts';
	import { parseDmReaction, withMyDmReaction, type DmReaction, type DmReactionRow } from '#lib/social/dm_reactions.ts';
	import { DmImageEncodeError, encodeDmImage } from '#lib/social/dm_image_encode.ts';

	const groupId = $derived(page.params.id ?? '');
	const routeId = $derived(`group/${groupId}`);
	const me = $derived(auth.user?.id ?? null);
	const row = $derived(messagesInbox.threads.find((t) => t.kind === 'group' && t.conversationId === groupId) ?? null);

	// null while unknown; the flag is read here as well as by the inbox so a
	// deep link decides on its own. A failed read leaves it null, which shows
	// nothing of the group (fail-closed) and is read again on the next poll;
	// only a definite false is "not available".
	let enabled = $state<boolean | null>(null);
	let members = $state<GroupMember[]>([]);
	// 'active' once group_members answers, 'outside' on its P0002: the viewer
	// left, was removed, never belonged, or the group does not exist.
	let membership = $state<'unknown' | 'active' | 'outside'>('unknown');
	let messages = $state<DirectMessage[]>([]);
	let placeholders = $state<DmOrderKey[]>([]);
	let profiles = $state(new Map<string, { name: string | null; avatarUrl: string | null }>());
	let reactions = $state<DmReactionRow[]>([]);
	let hasMore = $state(false);
	let loading = $state(true);
	let loadError = $state(false);
	let loadingEarlier = $state(false);
	let earlierError = $state(false);
	let scroller = $state<HTMLDivElement | null>(null);

	// Drafts are per group, as the 1:1 page keeps them per thread: this
	// component is reused when the route moves to another group, and a draft
	// that followed the reader would post to a different audience.
	let drafts = $state<Record<string, string>>({});
	const draft = $derived(drafts[groupId] ?? '');
	let sending = $state(false);
	let sendError = $state<string | null>(null);
	let actionError = $state<string | null>(null);
	let photosEnabled = $state(false);
	let photoDraft = $state<{ group: string; blob: Blob; preview: string } | null>(null);
	const groupPhoto = $derived(photoDraft?.group === groupId ? photoDraft : null);
	let photoInput = $state<HTMLInputElement | null>(null);
	let preparingPhoto = $state(false);

	let editingId = $state<string | null>(null);
	let editDraft = $state('');
	let editBusy = $state(false);
	let editError = $state<string | null>(null);
	let now = $state(Date.now());

	let unsendTarget = $state<DirectMessage | null>(null);
	let reportTarget = $state<DirectMessage | null>(null);
	let showMembers = $state(false);
	let showLeaveConfirm = $state(false);
	let leaving = $state(false);
	let muteBusy = $state(false);

	// Writes newer than a poll's read (send, unsend, edit, open) drop that poll.
	let localWrites = 0;
	let polling = false;
	let markedThrough: string | null = null;
	let reactionWrites = 0;

	const active = $derived(membership === 'active');
	const leftWithHistory = $derived(membership === 'outside' && (row?.membershipState === 'left' || messages.length > 0));
	const notAvailable = $derived(enabled === false || (membership === 'outside' && !leftWithHistory));
	const title = $derived(row?.title ?? tr('groups.groupFallback'));
	const activeMembers = $derived(members.filter((x) => x.state === 'active'));
	const muted = $derived(row?.muted ?? messagesInbox.writtenFlag(groupId, 'muted') ?? false);
	const items = $derived(mergeGroupThread(messages, placeholders));

	$effect(() => {
		const timer = setInterval(() => (now = Date.now()), 15_000);
		return () => clearInterval(timer);
	});

	$effect(() => {
		if (!auth.user) return;
		void fetchDmImagesEnabled().then((on) => (photosEnabled = on));
	});

	$effect(() => () => {
		if (photoDraft) URL.revokeObjectURL(photoDraft.preview);
	});

	$effect(() => {
		const id = groupId;
		if (!id || !auth.user) return;
		void open(id);
	});

	function senderName(id: string): string {
		return (
			members.find((x) => x.userId === id)?.name ?? profiles.get(id)?.name ?? tr('messages.runnerFallback')
		);
	}

	function senderAvatar(id: string): string | null {
		return members.find((x) => x.userId === id)?.avatarUrl ?? profiles.get(id)?.avatarUrl ?? null;
	}

	async function loadMembers(id: string) {
		try {
			const rows = await fetchGroupMembers(id);
			if (id !== groupId) return;
			members = rows;
			membership = 'active';
		} catch (e) {
			if (id !== groupId) return;
			if (e instanceof AppError && e.key === 'groups.notFound') {
				const wasMember = membership === 'active';
				members = [];
				membership = 'outside';
				// D12: someone who left or was removed reads only their own
				// messages. The server already answers so; what this page still
				// holds from before goes too, rather than waiting for a reload.
				messages = messages.filter((x) => x.sender_id === me);
				placeholders = [];
				reactions = [];
				// The inbox beside the thread still holds the group's row and
				// its last message until its own poll; a removal read here is
				// the earlier signal, so the list is re-read now.
				if (wasMember) void messagesInbox.afterLeave();
			} else {
				console.warn('group members read failed', e);
			}
		}
	}

	// Names for senders who are no longer members: the leaver's own view, or
	// someone who left after writing.
	async function loadProfiles(id: string) {
		const known = new Set(members.map((x) => x.userId));
		const missing = [...new Set(messages.map((x) => x.sender_id))].filter((s) => !known.has(s) && !profiles.has(s));
		if (missing.length === 0) return;
		try {
			const found = await fetchGroupProfiles(missing);
			if (id !== groupId) return;
			const next = new Map(profiles);
			for (const [k, v] of found) next.set(k, v);
			profiles = next;
		} catch (e) {
			console.warn('group sender profiles read failed', e);
		}
	}

	async function loadPlaceholders(id: string) {
		if (membership !== 'active') {
			placeholders = [];
			return;
		}
		try {
			const rows = await fetchGroupBlockedPlaceholders(id, placeholdersSince(messages, hasMore));
			if (id === groupId) placeholders = rows;
		} catch (e) {
			console.warn('group placeholders read failed', e);
		}
	}

	async function loadReactions(id: string) {
		const ids = messages.filter((x) => x.unsent_at === null).map((x) => x.id);
		const writes = reactionWrites;
		try {
			const rows = await fetchDmReactions(ids);
			if (id === groupId && writes === reactionWrites) reactions = rows;
		} catch (e) {
			console.warn('group reactions read failed', e);
		}
	}

	async function open(id: string) {
		loading = true;
		loadError = false;
		membership = 'unknown';
		members = [];
		messages = [];
		placeholders = [];
		reactions = [];
		markedThrough = null;
		sendError = null;
		actionError = null;
		cancelEdit();
		const on = await fetchGroupMessagesEnabled();
		if (id !== groupId) return;
		enabled = on;
		if (on !== true) {
			loading = false;
			return;
		}
		try {
			const [first] = await Promise.all([fetchGroupThread(id), loadMembers(id)]);
			if (id !== groupId) return;
			localWrites++;
			messages = first.messages;
			hasMore = first.hasMore;
		} catch {
			if (id !== groupId) return;
			loadError = true;
			return;
		} finally {
			if (id === groupId) loading = false;
		}
		void scrollToNewest();
		void loadProfiles(id);
		void loadPlaceholders(id);
		void loadReactions(id);
		await markRead(id);
	}

	// Through the newest message on screen; nothing is shared with anyone (D6).
	async function markRead(id: string) {
		if (membership !== 'active') return;
		const newest = messages.at(-1);
		if (!newest || newest.id === markedThrough) return;
		try {
			await markGroupRead(id, newest.id);
			if (id !== groupId) return;
			markedThrough = newest.id;
			messagesInbox.markRead(`group/${id}`);
			void dmUnreadStore.refresh();
		} catch (e) {
			console.warn('group mark-read failed', e);
		}
	}

	function atBottom(): boolean {
		if (!scroller) return true;
		return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 32;
	}

	async function scrollToNewest() {
		await tick();
		if (scroller) scroller.scrollTop = scroller.scrollHeight;
	}

	async function poll(id: string) {
		if (id !== groupId || polling || loading) return;
		if (enabled === null) return open(id);
		if (loadError || enabled !== true) return;
		polling = true;
		const writesAtStart = localWrites;
		try {
			const [result] = await Promise.all([fetchGroupThread(id), loadMembers(id)]);
			if (id !== groupId || writesAtStart !== localWrites) return;
			const follow = atBottom();
			const next = mergeDmPollPage(messages, result, hasMore);
			messages = next.messages;
			hasMore = next.hasMore;
			if (follow || next.gap) void scrollToNewest();
			void loadProfiles(id);
			void loadPlaceholders(id);
			void loadReactions(id);
			await markRead(id);
		} catch (e) {
			console.warn('group thread poll failed', e);
		} finally {
			polling = false;
		}
	}

	// The house cadence (decisions § 2223): 10 s while the tab is visible.
	$effect(() => {
		const id = groupId;
		if (!id || !auth.user) return;
		return startVisiblePoll(() => void poll(id), DM_THREAD_POLL_MS);
	});

	async function loadEarlier() {
		const id = groupId;
		const oldest = messages[0];
		if (!oldest || loadingEarlier) return;
		loadingEarlier = true;
		earlierError = false;
		try {
			const result = await fetchGroupThread(id, { before: oldest });
			if (id !== groupId) return;
			const fromBottom = scroller ? scroller.scrollHeight - scroller.scrollTop : 0;
			messages = mergeDmMessages(messages, result.messages);
			hasMore = result.hasMore;
			await tick();
			if (scroller) scroller.scrollTop = scroller.scrollHeight - fromBottom;
			void loadProfiles(id);
			void loadPlaceholders(id);
			void loadReactions(id);
		} catch {
			if (id === groupId) earlierError = true;
		} finally {
			loadingEarlier = false;
		}
	}

	function clearPhotoDraft() {
		if (photoDraft) URL.revokeObjectURL(photoDraft.preview);
		photoDraft = null;
		if (photoInput) photoInput.value = '';
	}

	async function pickPhoto(e: Event & { currentTarget: HTMLInputElement }) {
		const file = e.currentTarget.files?.[0];
		if (!file) return;
		preparingPhoto = true;
		sendError = null;
		try {
			const id = groupId;
			const blob = await encodeDmImage(file);
			if (id !== groupId) return;
			clearPhotoDraft();
			photoDraft = { group: id, blob, preview: URL.createObjectURL(blob) };
		} catch (err) {
			sendError =
				err instanceof DmImageEncodeError && err.kind === 'too_large'
					? tr('messages.photoTooLarge')
					: tr('messages.photoUnreadable');
		} finally {
			preparingPhoto = false;
			if (photoInput) photoInput.value = '';
		}
	}

	async function send() {
		const id = groupId;
		const photo = groupPhoto;
		const body = drafts[id] ?? '';
		if (!active || sending || (!body.trim() && !photo)) return;
		sending = true;
		sendError = null;
		try {
			const imageId = photo ? await uploadDmImage(photo.blob) : undefined;
			const msg = await sendGroupMessage(id, body, { imageId });
			if (photo && photoDraft === photo) clearPhotoDraft();
			delete drafts[id];
			drafts = { ...drafts };
			if (id === groupId) {
				localWrites++;
				messages = mergeDmMessages(messages, [msg]);
				void scrollToNewest();
			}
			await messagesInbox.refreshThreads();
		} catch (e) {
			if (id !== groupId) return;
			sendError = errorCopy(e, tr, 'messages.sendFailed', 'messages.sendFailed');
			// A refusal is most often a removal the poll has not shown yet.
			void loadMembers(id);
		} finally {
			sending = false;
		}
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			void send();
		}
	}

	async function confirmUnsend() {
		const target = unsendTarget;
		const id = groupId;
		unsendTarget = null;
		if (!target) return;
		actionError = null;
		try {
			const updated = await unsendDm(target.id);
			if (id === groupId) {
				localWrites++;
				messages = mergeDmMessages(messages, [updated]);
			}
		} catch (e) {
			if (id === groupId) actionError = errorCopy(e, tr, 'messages.unsendFailed', 'messages.unsendFailed');
		}
		await messagesInbox.refreshThreads();
	}

	function startEdit(x: DirectMessage) {
		editingId = x.id;
		editDraft = x.body ?? '';
		editError = null;
	}

	function cancelEdit() {
		editingId = null;
		editDraft = '';
		editError = null;
	}

	async function saveEdit() {
		const targetId = editingId;
		const id = groupId;
		if (!targetId || editBusy || !editDraft.trim()) return;
		editBusy = true;
		editError = null;
		try {
			const updated = await editDm(targetId, editDraft);
			if (id !== groupId) return;
			localWrites++;
			messages = mergeDmMessages(messages, [updated]);
			if (editingId === targetId) cancelEdit();
		} catch (e) {
			if (id === groupId) editError = errorCopy(e, tr, 'messages.editFailed', 'messages.editFailed');
		} finally {
			editBusy = false;
		}
	}

	function onEditKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			void saveEdit();
		} else if (e.key === 'Escape') {
			e.preventDefault();
			cancelEdit();
		}
	}

	async function react(x: DirectMessage, next: DmReaction | null) {
		if (!me) return;
		const previous = reactions.find((r) => r.message_id === x.id && r.user_id === me)?.reaction ?? null;
		const write = ++reactionWrites;
		const mine = (reaction: DmReaction) => ({ message_id: x.id, user_id: me, reaction });
		reactions = withMyDmReaction(reactions, x.id, me, next, mine);
		actionError = null;
		try {
			await setDmReaction(x.id, next);
		} catch (e) {
			if (write === reactionWrites) reactions = withMyDmReaction(reactions, x.id, me, parseDmReaction(previous), mine);
			actionError = errorCopy(e, tr, 'messages.reactionRefused', 'messages.reactionRefused');
		}
	}

	async function toggleMuted() {
		if (muteBusy) return;
		const next = !muted;
		muteBusy = true;
		try {
			await messagesInbox.setMuted(groupId, next);
			if (next) showToast(tr('messages.mutedToast'), 'success');
		} catch (e) {
			showToast(tr('messages.conversationActionFailed', { error: errorCopy(e, tr, 'messages.conversationActionFailed') }), 'error');
		} finally {
			muteBusy = false;
		}
	}

	async function confirmLeave() {
		showLeaveConfirm = false;
		if (leaving) return;
		leaving = true;
		try {
			await leaveGroup(groupId);
			showToast(tr('groups.leftToast', { title }), 'success');
			await messagesInbox.afterLeave();
			await goto('/messages');
		} catch (e) {
			showToast(tr('groups.actionFailed', { error: errorCopy(e, tr, 'groups.actionFailed') }), 'error');
		} finally {
			leaving = false;
		}
	}

	async function afterRosterChange() {
		await Promise.all([loadMembers(groupId), messagesInbox.refreshThreads()]);
		void poll(groupId);
	}

	function fmtTime(iso: string): string {
		return new Date(iso).toLocaleString(activeFormatLocale(), {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit',
		});
	}
</script>

<svelte:head><title>{tr('messages.pageTitle')}</title></svelte:head>

{#if notAvailable}
	<header class="pane-head conv-head">
		<a class="back" href="/messages" aria-label={tr('messages.backAria')}>←</a>
	</header>
	<p class="muted center" data-testid="group-unavailable">{tr('groups.notAvailable')}</p>
{:else}
	<header class="pane-head conv-head">
		<a class="back" href="/messages" aria-label={tr('messages.backAria')}>←</a>
		<span class="group-avatar" aria-hidden="true"><span class="material-symbols">group</span></span>
		<span class="who-block">
			<span class="who" data-testid="group-title">{title}</span>
			{#if active}
				<button type="button" class="members-link" onclick={() => (showMembers = true)} data-testid="group-members-open">
					{tr('groups.memberCount', { count: activeMembers.length })}
				</button>
			{/if}
		</span>
		{#if active}
			<div class="head-actions">
				<button
					type="button"
					class="icon-action"
					data-testid="group-mute-toggle"
					aria-pressed={muted}
					disabled={muteBusy}
					title={muted ? tr('messages.unmute') : tr('messages.mute')}
					aria-label={muted ? tr('messages.unmute') : tr('messages.mute')}
					onclick={() => void toggleMuted()}
				>
					<span class="material-symbols" aria-hidden="true">{muted ? 'notifications' : 'notifications_off'}</span>
				</button>
				<button
					type="button"
					class="icon-action"
					data-testid="group-members-button"
					title={tr('groups.membersButton')}
					aria-label={tr('groups.membersButton')}
					onclick={() => (showMembers = true)}
				>
					<span class="material-symbols" aria-hidden="true">group</span>
				</button>
				<button
					type="button"
					class="btn btn-secondary btn-sm"
					data-testid="group-leave"
					disabled={leaving}
					onclick={() => (showLeaveConfirm = true)}
				>
					{tr('groups.leave')}
				</button>
			</div>
		{/if}
	</header>
	<div class="messages" bind:this={scroller}>
		{#if loading || enabled === null}
			<p class="muted center">{tr('shell.loading')}</p>
		{:else if loadError}
			<p class="muted center" role="alert">
				{tr('messages.threadLoadFailed')}
				<button type="button" class="btn btn-secondary btn-sm" onclick={() => void open(groupId)}>
					{tr('messages.retry')}
				</button>
			</p>
		{:else}
			{#if hasMore}
				<div class="earlier">
					<button type="button" class="btn btn-secondary btn-sm" onclick={() => void loadEarlier()} disabled={loadingEarlier}>
						{loadingEarlier ? tr('shell.loading') : tr('messages.loadEarlier')}
					</button>
					{#if earlierError}<p class="send-error" role="alert">{tr('messages.loadEarlierFailed')}</p>{/if}
				</div>
			{:else if active}
				<p class="system" data-testid="group-history-note">{tr('groups.historyNote')}</p>
			{/if}
			{#if items.length === 0}
				<p class="muted center">{active ? tr('groups.emptyThread') : tr('messages.emptyConversation')}</p>
			{/if}
			{#each items as item (item.kind === 'message' ? item.message.id : `blocked-${item.id}`)}
				{#if item.kind === 'blocked'}
					<p class="system blocked" data-testid="group-blocked-placeholder">{tr('groups.blockedPlaceholder')}</p>
				{:else}
					{@const x = item.message}
					{@const mine = x.sender_id === me}
					{#if x.kind === 'group_renamed'}
						<p class="system" data-testid="group-renamed-line">
							{x.unsent_at !== null || x.body === null
								? tr('messages.unsentPlaceholder')
								: mine
									? tr('groups.renamedLineYou', { title: x.body })
									: tr('groups.renamedLine', { name: senderName(x.sender_id), title: x.body })}
						</p>
					{:else}
						<div class="line" class:mine>
							{#if !mine}
								<Avatar
									url={senderAvatar(x.sender_id)}
									name={senderName(x.sender_id)}
									size="1.8rem"
									font="0.75rem"
									bg="seed"
									seedHue={hashHue(x.sender_id)}
								/>
							{/if}
							<div class="bubble" class:mine class:unsent={x.unsent_at !== null} data-testid="dm-bubble">
								{#if !mine}<span class="sender" data-testid="group-sender">{senderName(x.sender_id)}</span>{/if}
								{#if x.unsent_at !== null || (x.body === null && x.image_id === null)}
									<span class="text placeholder">{tr('messages.unsentPlaceholder')}</span>
								{:else if editingId === x.id}
									<div class="edit">
										<textarea
											bind:value={editDraft}
											onkeydown={onEditKeydown}
											aria-label={tr('messages.editLabel')}
											rows="2"
											maxlength="4000"
											data-testid="dm-edit-input"
										></textarea>
										{#if editError}<p class="edit-error" role="alert">{editError}</p>{/if}
										<div class="edit-actions">
											<button type="button" class="msg-action" onclick={cancelEdit}>{tr('messages.editCancel')}</button>
											<button type="button" class="msg-action" disabled={editBusy || !editDraft.trim()} onclick={() => void saveEdit()} data-testid="dm-edit-save">
												{tr('messages.editSave')}
											</button>
										</div>
									</div>
								{:else}
									{#if x.image_id !== null}<DmImage imageId={x.image_id} />{/if}
									{#if x.body !== null}<DmMessageText body={x.body} />{/if}
								{/if}
								<span class="meta">
									<span class="when">{fmtTime(x.created_at)}</span>
									{#if x.edited_at !== null && x.unsent_at === null}
										<span class="edited">{tr('messages.edited')}</span>
									{/if}
									{#if x.unsent_at === null && editingId !== x.id}
										{#if mine}
											{#if active && canEditDm(x, me, now)}
												<button type="button" class="msg-action" onclick={() => startEdit(x)} data-testid="dm-edit">
													{tr('messages.edit')}
												</button>
											{/if}
											<button type="button" class="msg-action" onclick={() => (unsendTarget = x)}>{tr('messages.unsend')}</button>
										{:else}
											<button type="button" class="msg-action" onclick={() => (reportTarget = x)}>{tr('messages.report')}</button>
										{/if}
									{/if}
								</span>
								{#if x.unsent_at === null && editingId !== x.id}
									<DmReactions messageId={x.id} rows={reactions} {me} canReact={active} onset={(r) => void react(x, r)} />
								{/if}
							</div>
						</div>
					{/if}
				{/if}
			{/each}
		{/if}
	</div>
	{#if actionError}<p class="send-error" role="alert">{actionError}</p>{/if}
	{#if sendError}<p class="send-error" role="alert">{sendError}</p>{/if}
	{#if membership === 'outside'}
		<p class="muted closed" data-testid="group-left-notice">{tr('groups.leftNotice')}</p>
	{:else if active}
		{#if groupPhoto}
			<div class="photo-draft">
				<img src={groupPhoto.preview} alt={tr('messages.photoDraftAlt')} />
				<button type="button" class="btn btn-secondary btn-sm" onclick={clearPhotoDraft} aria-label={tr('messages.photoRemove')}>
					<span class="material-symbols" aria-hidden="true">close</span>
				</button>
			</div>
		{/if}
		<div class="composer">
			{#if photosEnabled}
				<input
					bind:this={photoInput}
					type="file"
					accept="image/jpeg,image/png,image/webp"
					class="visually-hidden"
					tabindex="-1"
					onchange={(e) => void pickPhoto(e)}
					data-testid="dm-photo-input"
				/>
				<button
					type="button"
					class="btn btn-secondary attach"
					aria-label={tr('messages.photoAttach')}
					title={tr('messages.photoAttach')}
					disabled={sending || preparingPhoto}
					onclick={() => photoInput?.click()}
				>
					<span class="material-symbols" aria-hidden="true">add_photo_alternate</span>
				</button>
			{/if}
			<textarea
				value={draft}
				oninput={(e) => (drafts[groupId] = e.currentTarget.value)}
				onkeydown={onKeydown}
				placeholder={tr('messages.composerPlaceholder')}
				aria-label={tr('groups.composerLabel', { title })}
				rows="1"
				maxlength="4000"
			></textarea>
			<button class="btn btn-primary" onclick={send} disabled={sending || preparingPhoto || (!draft.trim() && !groupPhoto)}>
				{sending ? '…' : tr('messages.send')}
			</button>
		</div>
	{/if}
{/if}

{#if active}
	<GroupMembersSheet
		open={showMembers}
		conversationId={groupId}
		{title}
		{members}
		{me}
		onclose={() => (showMembers = false)}
		onchanged={afterRosterChange}
	/>
{/if}

<ConfirmDialog
	open={showLeaveConfirm}
	danger
	title={tr('groups.leaveConfirmTitle', { title })}
	message={tr('groups.leaveConfirmMessage')}
	confirmLabel={tr('groups.leave')}
	cancelLabel={tr('profile.cancel')}
	onconfirm={confirmLeave}
	oncancel={() => (showLeaveConfirm = false)}
	data-testid="group-leave-confirm"
/>

<ConfirmDialog
	open={unsendTarget !== null}
	danger
	title={tr('messages.unsendConfirmTitle')}
	message={tr('messages.unsendConfirmMessage')}
	confirmLabel={tr('messages.unsend')}
	onconfirm={confirmUnsend}
	oncancel={() => (unsendTarget = null)}
	data-testid="dm-unsend-confirm"
/>

{#if reportTarget}
	<ReportDialog
		open={reportTarget !== null}
		targetKind="direct_message"
		targetId={reportTarget.id}
		onclose={() => (reportTarget = null)}
	/>
{/if}

<style>
	.muted {
		color: var(--color-text-secondary);
	}
	.center {
		text-align: center;
		margin: auto;
	}
	.pane-head {
		padding: var(--space-md) var(--space-lg);
		border-bottom: 1px solid var(--color-border);
	}
	.conv-head {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.group-avatar {
		flex: 0 0 auto;
		width: 2.2rem;
		height: 2.2rem;
		border-radius: 50%;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
	}
	.who-block {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.who {
		font-weight: 700;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.members-link {
		align-self: flex-start;
		background: none;
		border: none;
		padding: 0;
		font: inherit;
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
		text-decoration: underline;
		cursor: pointer;
	}
	.members-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.head-actions {
		margin-inline-start: auto;
		display: flex;
		align-items: center;
		gap: 0.15rem;
		flex: 0 0 auto;
	}
	.icon-action {
		min-width: 2.75rem;
		min-height: 2.75rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-md);
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.icon-action[aria-pressed='true'] {
		color: var(--color-primary);
	}
	.icon-action:hover,
	.icon-action:focus-visible {
		border-color: var(--color-border);
		color: var(--color-primary);
	}
	.back {
		display: none;
		text-decoration: none;
		color: var(--color-text-secondary);
		font-size: 1.2rem;
	}
	.messages {
		flex: 1 1 auto;
		overflow-y: auto;
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.system {
		align-self: center;
		margin: 0;
		max-width: 80%;
		text-align: center;
		font-size: var(--font-size-section-label);
		color: var(--color-text-secondary);
	}
	.system.blocked {
		font-style: italic;
		align-self: flex-start;
		padding: 0.4rem 0.75rem;
		border: 1px dashed var(--color-border);
		border-radius: var(--radius-md);
	}
	.line {
		display: flex;
		align-items: flex-end;
		gap: 0.4rem;
		max-width: 75%;
		align-self: flex-start;
	}
	.line.mine {
		align-self: flex-end;
	}
	.bubble {
		min-width: 0;
		padding: 0.5rem 0.75rem;
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.bubble.mine {
		background: var(--color-primary);
		color: var(--color-bg);
	}
	.sender {
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text-secondary);
	}
	.bubble .meta {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 0.5rem;
	}
	.bubble .when,
	.bubble .edited {
		font-size: var(--font-size-section-label);
		opacity: 0.7;
	}
	.msg-action {
		background: none;
		border: none;
		padding: 0.15rem 0;
		font: inherit;
		font-size: var(--font-size-section-label);
		color: inherit;
		opacity: 0.85;
		text-decoration: underline;
		cursor: pointer;
	}
	.msg-action:focus-visible {
		outline: 2px solid currentColor;
		outline-offset: 2px;
	}
	.placeholder {
		font-style: italic;
	}
	.edit {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.edit textarea {
		resize: vertical;
		min-width: 14rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.4rem 0.6rem;
		font: inherit;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.edit-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.75rem;
	}
	.edit-error {
		margin: 0;
		font-size: var(--font-size-section-label);
		font-weight: 600;
	}
	.earlier {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.25rem;
	}
	.send-error {
		color: var(--color-danger-text);
		font-size: 0.8rem;
		padding: 0 var(--space-lg);
		margin: 0;
	}
	.closed {
		padding: var(--space-md) var(--space-lg);
		border-top: 1px solid var(--color-border);
		margin: 0;
	}
	.composer {
		display: flex;
		gap: 0.5rem;
		padding: var(--space-md) var(--space-lg);
		border-top: 1px solid var(--color-border);
	}
	.composer textarea {
		flex: 1 1 auto;
		resize: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.5rem 0.7rem;
		font: inherit;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.composer .attach {
		flex: 0 0 auto;
		min-width: 2.75rem;
	}
	.photo-draft {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		padding: var(--space-sm) var(--space-lg) 0;
	}
	.photo-draft img {
		max-height: 6rem;
		max-width: 10rem;
		border-radius: var(--radius-md);
		object-fit: cover;
	}
	@media (max-width: 48rem) {
		.back {
			display: inline;
		}
		.line {
			max-width: 90%;
		}
	}
</style>
