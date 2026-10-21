<script lang="ts">
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { appErrorMessage, thrownMessage } from '#lib/core/supabase_error.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { startVisiblePoll } from '#lib/core/visible_poll.ts';
	import { m as tr } from '#lib/i18n/store.svelte.ts';
	import { dmUnreadStore } from '#lib/stores/dm_unread.svelte.ts';
	import { onMount, tick } from 'svelte';
	import Avatar from '#lib/components/Avatar.svelte';
	import { hashHue } from '#lib/format/avatar.ts';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import DmRouteAttachment from '#lib/components/DmRouteAttachment.svelte';
	import { bodyRestatesAttachment, hasDmRouteAttachment } from '#lib/social/dm_attachment.ts';
	import {
		DM_INBOX_POLL_MS,
		DM_THREAD_POLL_MS,
		dmThreadRouteId,
		mergeDmMessages,
		mergeDmPollPage,
		parseDmThreadRouteId
	} from '#lib/social/dm_thread.ts';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import ReportDialog from '#lib/components/ReportDialog.svelte';
	import {
		fetchDmThreads,
		fetchDmThread,
		sendDm,
		unsendDm,
		markDmThreadRead,
		blockUser,
		unblockUser,
		isBlockedByViewer,
		type DmThread,
		type DirectMessage
	} from '#lib/core/data.ts';

	let ready = $state(false);
	let threads = $state<DmThread[]>([]);
	let messages = $state<DirectMessage[]>([]);
	// Drafts are PER THREAD. A single top-level draft followed the viewer into
	// whichever conversation they clicked next — the composer lives inside the
	// `{#if !activeId}{:else}` branch, so switching threads never tears it down
	// — and send() posts to the CURRENT activeId. A half-written private message
	// to one person could be delivered to another. Keying by partner also
	// restores the right draft on switching back, instead of destroying it.
	let drafts = $state<Record<string, string>>({});
	let sending = $state(false);
	let loadingThread = $state(false);
	let sendError = $state<string | null>(null);
	let threadsError = $state(false);
	let threadError = $state(false);
	// The thread is read from its newest end, a page at a time (dm_thread.ts).
	let hasMore = $state(false);
	let loadingEarlier = $state(false);
	let earlierError = $state(false);
	let scroller = $state<HTMLDivElement | null>(null);

	let activeId = $derived(page.params.id ?? null);
	// A deleted partner's thread has no partner to reply to, link to or mark
	// read; it holds only the viewer's own messages (migration 20271021000003).
	const activeTarget = $derived(activeId ? parseDmThreadRouteId(activeId) : null);
	const activePartnerId = $derived(activeTarget?.kind === 'partner' ? activeTarget.partnerId : null);
	const draft = $derived(activeId ? (drafts[activeId] ?? '') : '');
	let me = $derived(auth.user?.id ?? null);
	let activeThread = $derived(threads.find((t) => dmThreadRouteId(t) === activeId) ?? null);

	// The message an Unsend / Report action is open for. Unsend cannot be
	// undone, so it goes through a confirm; Report has its own dialog.
	let unsendTarget = $state<DirectMessage | null>(null);
	let reportTarget = $state<DirectMessage | null>(null);
	let actionError = $state<string | null>(null);

	// Block from inside the conversation, the same toggle the profile header
	// carries (decisions § 1952): Block is confirmed because block_user drains
	// the follow edge both ways, which unblocking does not put back; Unblock
	// runs at once. `user_blocks` is owner-read, so this knows only the
	// viewer's own block — a partner who blocked the viewer still reads as the
	// composer's send refusal, the one sentence § 1916 keeps for both gates.
	let blockedByMe = $state(false);
	let blockBusy = $state(false);
	let showBlockConfirm = $state(false);
	const partnerName = $derived(activeThread?.partnerName ?? tr('messages.runnerFallback'));

	onMount(async () => {
		await auth.ready();
		ready = true;
	});

	// Load the thread list whenever a user is present, not one-shot in
	// onMount: ready() resolves on its safety timeout even when the
	// session hasn't settled yet (slow device / loaded CI runner), and a
	// mount-time `if (auth.user)` gate would then skip the fetch forever.
	let threadsRequested = false;
	$effect(() => {
		if (!auth.user || threadsRequested) return;
		threadsRequested = true;
		void loadThreads();
	});

	// When each conversation was last marked read. A thread-list fetch that
	// started before that answers with the count from before the mark, and
	// assigning it as-is put the badge back on the conversation just opened.
	const markedReadAt = new Map<string, number>();

	function applyThreads(rows: DmThread[], startedAt: number) {
		threads = rows.map((t) =>
			(markedReadAt.get(dmThreadRouteId(t)) ?? -Infinity) >= startedAt ? { ...t, unread: 0 } : t
		);
	}

	async function loadThreads() {
		threadsError = false;
		const startedAt = Date.now();
		try {
			applyThreads(await fetchDmThreads(), startedAt);
		} catch {
			threadsError = true;
		}
	}

	// The inbox re-reads its list every 30 s while the tab is visible, as
	// mobile's does. A failed poll keeps the list it has and logs: the next
	// tick is the retry, and a banner every 30 s would be noise. A list that
	// never loaded retries through loadThreads so its error state can clear.
	let pollingThreads = false;
	async function pollThreads() {
		if (pollingThreads) return;
		if (threadsError) return loadThreads();
		pollingThreads = true;
		const startedAt = Date.now();
		try {
			applyThreads(await fetchDmThreads(), startedAt);
		} catch (e) {
			console.warn('messages inbox poll failed', e);
		} finally {
			pollingThreads = false;
		}
	}

	$effect(() => {
		if (!auth.user) return;
		return startVisiblePoll(() => void pollThreads(), DM_INBOX_POLL_MS);
	});

	// Load the open conversation whenever the route param changes.
	$effect(() => {
		const id = activeId;
		// A send failure belongs to the thread it happened in; leaving it pinned
		// above the composer made it read as an error in the new conversation.
		sendError = null;
		actionError = null;
		if (!id || !auth.user) {
			messages = [];
			hasMore = false;
			threadError = false;
			return;
		}
		void openThread(id);
	});

	async function openThread(id: string) {
		// Two quick clicks leave two fetches in flight and the LAST to resolve
		// won, so the header and URL could read one partner while the bubbles
		// were another's — and send() would post into the thread named by the
		// URL. The guard is "is this still the open conversation?", keyed on the
		// id, rather than a generation counter: a counter also discards a SECOND
		// call for the SAME id, so a re-invocation swallowed the first call's
		// failure and the retry banner never rendered.
		loadingThread = true;
		threadError = false;
		earlierError = false;
		try {
			const result = await fetchDmThread(parseDmThreadRouteId(id));
			if (id !== activeId) return;
			localWrites++;
			messages = result.messages;
			hasMore = result.hasMore;
		} catch {
			if (id !== activeId) return;
			messages = [];
			hasMore = false;
			threadError = true;
			return;
		} finally {
			if (id === activeId) loadingThread = false;
		}
		void scrollToNewest();
		await markThreadRead(id);
	}

	async function markThreadRead(id: string) {
		const target = parseDmThreadRouteId(id);
		if (target.kind !== 'partner') return;
		const newestShown = messages.findLast((m) => m.sender_id === target.partnerId);
		if (!newestShown) return;
		try {
			await markDmThreadRead(id, newestShown);
			markedReadAt.set(id, Date.now());
			const readAt = new Date().toISOString();
			if (id === activeId) {
				messages = messages.map((m) =>
					m.sender_id === target.partnerId && m.read_at === null ? { ...m, read_at: readAt } : m
				);
			}
			// Zero the unread badge locally without a full refetch.
			threads = threads.map((t) => (dmThreadRouteId(t) === id ? { ...t, unread: 0 } : t));
			void dmUnreadStore.refresh();
		} catch (e) {
			// Marking-read is a non-critical side effect; its failure must not
			// blank the conversation the fetch already loaded.
			console.warn('message thread mark-read failed', e);
		}
	}

	// The open conversation re-reads its newest page every 10 s while the tab
	// is visible, as mobile's does (decisions § 1916); the effect's teardown
	// stops it when the conversation changes or the page is left. There is no
	// "newer than" read: re-reading the newest page also brings in an unsend
	// of a message already on screen, which a read past the newest would miss.
	// A failed poll keeps what is shown and logs.
	let pollingThread = false;
	// Bumped when a poll replaces the list across a gap, so a "load earlier"
	// already in flight is dropped rather than merged into the new window.
	let messageWindow = 0;
	// Bumped whenever the list is written from something newer than a poll's
	// read (a send, an unsend, a fresh open), so a poll that was already in
	// flight is dropped rather than putting an unsent message's text back.
	let localWrites = 0;

	function atBottom(): boolean {
		if (!scroller) return true;
		return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 32;
	}

	async function pollThread(id: string) {
		if (id !== activeId || pollingThread || loadingThread || threadError) return;
		pollingThread = true;
		const writesAtStart = localWrites;
		try {
			const result = await fetchDmThread(parseDmThreadRouteId(id));
			if (id !== activeId || writesAtStart !== localWrites) return;
			const follow = atBottom();
			const next = mergeDmPollPage(messages, result, hasMore);
			if (next.gap) messageWindow++;
			messages = next.messages;
			hasMore = next.hasMore;
			// A reader scrolled up stays where they are: new messages append
			// below, so leaving scrollTop alone keeps what they are reading.
			if (follow || next.gap) void scrollToNewest();
			const target = parseDmThreadRouteId(id);
			if (
				target.kind === 'partner' &&
				messages.some((m) => m.sender_id === target.partnerId && m.read_at === null)
			) {
				await markThreadRead(id);
			}
		} catch (e) {
			console.warn('message thread poll failed', e);
		} finally {
			pollingThread = false;
		}
	}

	$effect(() => {
		const id = activeId;
		if (!id || !auth.user) return;
		return startVisiblePoll(() => void pollThread(id), DM_THREAD_POLL_MS);
	});

	$effect(() => {
		const partner = activePartnerId;
		blockedByMe = false;
		showBlockConfirm = false;
		if (!partner || !auth.user) return;
		void loadBlockState(partner);
	});

	// The block check must never gate the conversation, so a failure leaves
	// the composer up: the server still refuses a blocked send (the INSERT
	// policy's is_blocked_either_way), and the composer shows that refusal.
	// Bumped by a completed block or unblock, so a state read that started
	// before it cannot undo what the viewer just did.
	let blockVersion = 0;

	async function loadBlockState(partner: string) {
		const versionAtStart = blockVersion;
		try {
			const blocked = await isBlockedByViewer(partner);
			if (partner === activePartnerId && versionAtStart === blockVersion) blockedByMe = blocked;
		} catch (e) {
			console.warn('message thread block check failed', e);
		}
	}

	async function confirmBlock() {
		showBlockConfirm = false;
		const partner = activePartnerId;
		if (!partner || blockBusy) return;
		const name = partnerName;
		blockBusy = true;
		try {
			await blockUser(partner);
			blockVersion++;
			if (partner === activePartnerId) blockedByMe = true;
			showToast(tr('profile.blockedToast', { name }), 'success');
		} catch (e) {
			showToast(tr('profile.blockError', { error: thrownMessage(e) }), 'error');
		} finally {
			blockBusy = false;
		}
	}

	async function unblock() {
		const partner = activePartnerId;
		if (!partner || blockBusy) return;
		const name = partnerName;
		blockBusy = true;
		try {
			await unblockUser(partner);
			blockVersion++;
			if (partner === activePartnerId) blockedByMe = false;
			showToast(tr('profile.unblockedToast', { name }), 'success');
		} catch (e) {
			showToast(tr('profile.unblockError', { error: thrownMessage(e) }), 'error');
		} finally {
			blockBusy = false;
		}
	}

	// The first page is the newest end of the conversation, so it opens there.
	async function scrollToNewest() {
		await tick();
		if (scroller) scroller.scrollTop = scroller.scrollHeight;
	}

	// Prepending a page must not move what the reader is looking at: keep the
	// distance from the bottom, which the new rows above leave unchanged.
	async function loadEarlier() {
		const id = activeId;
		const oldest = messages[0];
		if (!id || !oldest || loadingEarlier) return;
		const windowAtStart = messageWindow;
		loadingEarlier = true;
		earlierError = false;
		try {
			const result = await fetchDmThread(parseDmThreadRouteId(id), { before: oldest });
			if (id !== activeId || windowAtStart !== messageWindow) return;
			const fromBottom = scroller ? scroller.scrollHeight - scroller.scrollTop : 0;
			messages = mergeDmMessages(messages, result.messages);
			hasMore = result.hasMore;
			await tick();
			if (scroller) scroller.scrollTop = scroller.scrollHeight - fromBottom;
		} catch {
			if (id === activeId) earlierError = true;
		} finally {
			loadingEarlier = false;
		}
	}

	async function send() {
		const id = activeId;
		const partnerId = activePartnerId;
		if (!id || !partnerId || blockedByMe || !draft.trim() || sending) return;
		sending = true;
		sendError = null;
		try {
			const body = drafts[id] ?? '';
			const msg = await sendDm(partnerId, body);
			localWrites++;
			messages = mergeDmMessages(messages, [msg]);
			void scrollToNewest();
			delete drafts[id];
			drafts = { ...drafts };
			try {
				threads = await fetchDmThreads();
			} catch {
				// The send itself succeeded and already renders; a failed
				// list refresh must not claim "send failed" — stale
				// previews are fine until the next load.
			}
		} catch (e) {
			sendError = appErrorMessage(e) ?? tr('messages.sendFailed');
		} finally {
			sending = false;
		}
	}

	async function confirmUnsend() {
		const target = unsendTarget;
		const id = activeId;
		if (!target || !id) return;
		actionError = null;
		try {
			const updated = await unsendDm(target.id);
			localWrites++;
			if (id === activeId) messages = mergeDmMessages(messages, [updated]);
		} catch (e) {
			actionError = appErrorMessage(e) ?? tr('messages.unsendFailed');
		} finally {
			unsendTarget = null;
		}
		try {
			threads = await fetchDmThreads();
		} catch {
			// The unsend itself landed and already renders; a stale preview in
			// the list is corrected by the next load.
		}
	}

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			void send();
		}
	}

	function fmtTime(iso: string): string {
		return new Date(iso).toLocaleString(activeFormatLocale(), {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}

</script>

<svelte:head><title>{tr('messages.pageTitle')}</title></svelte:head>

<div class="page">
	<h1 class="visually-hidden">{tr('messages.heading')}</h1>
	{#if !ready}
		<p class="muted">{tr('shell.loading')}</p>
	{:else if !auth.user}
		<p class="muted">{tr('messages.signInPrompt')}</p>
	{:else}
		<div class="layout">
			<aside class="threads" class:has-active={activeId}>
				<header class="pane-head"><h2>{tr('messages.heading')}</h2></header>
				{#if threadsError}
					<p class="muted empty" role="alert">
						{tr('messages.threadsLoadFailed')}
						<button type="button" class="btn btn-secondary btn-sm" onclick={() => void loadThreads()}>
							{tr('messages.retry')}
						</button>
					</p>
				{:else if threads.length === 0}
					<p class="muted empty">{tr('messages.emptyThreads')}</p>
				{:else}
					<ul>
						{#each threads as t (dmThreadRouteId(t))}
							{@const routeId = dmThreadRouteId(t)}
							{@const name = t.partnerId
								? (t.partnerName ?? tr('messages.runnerFallback'))
								: tr('messages.deletedAccount')}
							<li>
								<a
									class="thread"
									class:active={routeId === activeId}
									href={`/messages/${routeId}`}
								>
									<Avatar url={t.partnerAvatar} name={t.partnerId ? t.partnerName : null} size="2.2rem" font="0.9rem" bg="seed" seedHue={hashHue(routeId)} />
									<span class="thread-body">
										<span class="thread-top">
											<strong>{name}</strong>
											{#if t.unread > 0}<span class="badge">{t.unread}</span>{/if}
										</span>
										<span class="preview" class:unsent={t.lastUnsent}>{t.lastFromMe ? tr('messages.youPrefix') : ''}{t.lastUnsent
												? tr('messages.unsentPlaceholder')
												: t.lastBody}</span>
									</span>
								</a>
							</li>
						{/each}
					</ul>
				{/if}
			</aside>

			<section class="conversation" class:has-active={activeId}>
				{#if !activeId}
					<p class="muted center">{tr('messages.pickConversation')}</p>
				{:else}
					<header class="pane-head conv-head">
						<a class="back" href="/messages" aria-label={tr('messages.backAria')}>←</a>
						{#if activePartnerId}
							<a class="who" href={`/u/${activePartnerId}`}>{partnerName}</a>
							<button
								type="button"
								class="btn btn-secondary btn-sm head-action"
								data-testid="dm-block-toggle"
								aria-pressed={blockedByMe}
								disabled={blockBusy}
								onclick={() => (blockedByMe ? void unblock() : (showBlockConfirm = true))}
							>
								{blockedByMe ? tr('messages.unblock') : tr('messages.block')}
							</button>
						{:else}
							<span class="who">{tr('messages.deletedAccount')}</span>
						{/if}
					</header>
					<div class="messages" bind:this={scroller}>
						{#if loadingThread}
							<p class="muted center">{tr('shell.loading')}</p>
						{:else if threadError}
							<p class="muted center" role="alert">
								{tr('messages.threadLoadFailed')}
								<button
									type="button"
									class="btn btn-secondary btn-sm"
									onclick={() => activeId && void openThread(activeId)}
								>
									{tr('messages.retry')}
								</button>
							</p>
						{:else if messages.length === 0}
							<p class="muted center">{tr('messages.emptyConversation')}</p>
						{:else}
							{#if hasMore}
								<div class="earlier">
									<button
										type="button"
										class="btn btn-secondary btn-sm"
										onclick={() => void loadEarlier()}
										disabled={loadingEarlier}
									>
										{loadingEarlier ? tr('shell.loading') : tr('messages.loadEarlier')}
									</button>
									{#if earlierError}
										<p class="send-error" role="alert">{tr('messages.loadEarlierFailed')}</p>
									{/if}
								</div>
							{/if}
							{#each messages as m (m.id)}
								{@const attached = m.route_id}
								{@const mine = m.sender_id === me}
								<div class="bubble" class:mine class:unsent={m.unsent_at !== null} data-testid="dm-bubble">
									{#if m.unsent_at !== null || m.body === null}
										<span class="text placeholder">{tr('messages.unsentPlaceholder')}</span>
									{:else if hasDmRouteAttachment(attached)}
										<DmRouteAttachment routeId={attached} />
										{#if !bodyRestatesAttachment(m.body, attached)}
											<span class="text">{m.body}</span>
										{/if}
									{:else}
										<span class="text">{m.body}</span>
									{/if}
									<span class="meta">
										<span class="when">{fmtTime(m.created_at)}</span>
										{#if m.unsent_at === null}
											{#if mine}
												<button
													type="button"
													class="msg-action"
													onclick={() => (unsendTarget = m)}
												>{tr('messages.unsend')}</button>
											{:else}
												<button
													type="button"
													class="msg-action"
													onclick={() => (reportTarget = m)}
												>{tr('messages.report')}</button>
											{/if}
										{/if}
									</span>
								</div>
							{/each}
						{/if}
					</div>
					{#if actionError}<p class="send-error" role="alert">{actionError}</p>{/if}
					{#if sendError}<p class="send-error" role="alert">{sendError}</p>{/if}
					{#if !activePartnerId}
						<p class="muted closed">{tr('messages.deletedAccountClosed')}</p>
					{:else if blockedByMe}
						<div class="closed blocked" data-testid="dm-blocked-notice">
							<p class="muted">{tr('messages.blockedNotice', { name: partnerName })}</p>
							<button
								type="button"
								class="btn btn-secondary btn-sm"
								disabled={blockBusy}
								onclick={() => void unblock()}
							>
								{tr('messages.unblock')}
							</button>
						</div>
					{:else}
					<div class="composer">
						<textarea
							value={draft}
							oninput={(e) => {
								if (activeId) drafts[activeId] = e.currentTarget.value;
							}}
							onkeydown={onKeydown}
							placeholder={tr('messages.composerPlaceholder')}
							rows="1"
							maxlength="4000"
						></textarea>
						<button class="btn btn-primary" onclick={send} disabled={sending || !draft.trim()}>
							{sending ? '…' : tr('messages.send')}
						</button>
					</div>
					{/if}
				{/if}
			</section>
		</div>
	{/if}
</div>

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

<ConfirmDialog
	open={showBlockConfirm}
	danger
	title={tr('profile.blockConfirmTitle', { name: partnerName })}
	message={tr('messages.blockConfirmMessage')}
	confirmLabel={tr('profile.blockConfirmLabel')}
	cancelLabel={tr('profile.cancel')}
	onconfirm={confirmBlock}
	oncancel={() => (showBlockConfirm = false)}
	data-testid="dm-block-confirm"
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
	.page {
		padding: var(--space-lg) var(--space-2xl);
		height: 100vh;
		display: flex;
		flex-direction: column;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.center {
		text-align: center;
		margin: auto;
	}
	.layout {
		display: grid;
		grid-template-columns: 20rem 1fr;
		gap: var(--space-lg);
		flex: 1 1 auto;
		min-height: 0;
	}
	.threads,
	.conversation {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
		min-height: 0;
		overflow: hidden;
	}
	.pane-head {
		padding: var(--space-md) var(--space-lg);
		border-bottom: 1px solid var(--color-border);
	}
	.pane-head h2 {
		margin: 0;
		font-size: 1rem;
	}
	.threads ul {
		list-style: none;
		margin: 0;
		padding: 0;
		overflow-y: auto;
	}
	.thread {
		display: flex;
		gap: 0.6rem;
		align-items: center;
		padding: var(--space-sm) var(--space-lg);
		text-decoration: none;
		color: var(--color-text);
		border-bottom: 1px solid var(--color-border);
	}
	.thread:hover,
	.thread.active {
		background: var(--color-bg-secondary);
	}
	.thread-body {
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.1rem;
	}
	.thread-top {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		min-width: 0;
	}
	/* A flex item's default `min-width: auto` refuses to shrink below its
	   content, so a long display name pushed the unread count out of the
	   pane .threads clips — the one thing on the row you cannot afford to
	   lose. The name gives way instead. */
	.thread-top strong {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.badge {
		flex: 0 0 auto;
		background: var(--color-primary);
		color: var(--color-bg);
		border-radius: 999px;
		font-size: var(--font-size-section-label);
		padding: 0.05rem 0.4rem;
		font-weight: 700;
	}
	.preview {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.conv-head {
		display: flex;
		align-items: center;
		gap: 0.6rem;
	}
	.conv-head .who {
		font-weight: 700;
		color: var(--color-text);
		text-decoration: none;
	}
	.head-action {
		margin-inline-start: auto;
	}
	.blocked {
		display: flex;
		align-items: center;
		gap: var(--space-md);
	}
	.blocked p {
		margin: 0;
		flex: 1 1 auto;
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
	.bubble {
		max-width: 70%;
		padding: 0.5rem 0.75rem;
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		align-self: flex-start;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.bubble.mine {
		align-self: flex-end;
		background: var(--color-primary);
		color: var(--color-bg);
	}
	.bubble .meta {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.bubble .when {
		font-size: var(--font-size-section-label);
		opacity: 0.7;
	}
	/* Text-styled so it reads as a quiet affordance on every bubble rather
	   than a button competing with the message; inherits the bubble's
	   foreground, so it stays legible on the sent bubble's inverted fill. */
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
	.placeholder,
	.preview.unsent {
		font-style: italic;
	}
	.closed {
		padding: var(--space-md) var(--space-lg);
		border-top: 1px solid var(--color-border);
		margin: 0;
	}
	/* The attachment card carries its own surface + border, so it must not
	   inherit the sent-bubble's inverted foreground. */
	.bubble.mine :global(.attachment) {
		color: var(--color-text);
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
	.empty {
		padding: var(--space-lg);
	}

	@media (max-width: 48rem) {
		.layout {
			grid-template-columns: minmax(0, 1fr);
		}
		/* On narrow screens show one pane at a time. */
		.threads.has-active {
			display: none;
		}
		.conversation:not(.has-active) {
			display: none;
		}
		.back {
			display: inline;
		}
	}
</style>
