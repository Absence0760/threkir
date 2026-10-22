<script lang="ts">
	import type { Snippet } from 'svelte';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { startVisiblePoll } from '#lib/core/visible_poll.ts';
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { hashHue } from '#lib/format/avatar.ts';
	import Avatar from '#lib/components/Avatar.svelte';
	import AiTag from '#lib/components/AiTag.svelte';
	import { messagesInbox } from '#lib/stores/messages_inbox.svelte.ts';
	import { DM_INBOX_POLL_MS, dmThreadRouteId } from '#lib/social/dm_thread.ts';
	import { coachInboxPreview, inboxEntries } from '#lib/social/messages_inbox.ts';

	let { children }: { children: Snippet } = $props();

	let ready = $state(false);

	const coachPath = '/messages/coach';
	const onCoach = $derived(page.url.pathname === coachPath);
	// The open conversation: a DM partner (or deleted-partner key) from the
	// `[[id]]` page, or the Coach.
	const activeId = $derived(page.params.id ?? null);
	const hasActive = $derived(activeId !== null || onCoach);

	const entries = $derived(
		inboxEntries(
			messagesInbox.threads,
			messagesInbox.coach && {
				placement: messagesInbox.coach.placement,
				lastAt: messagesInbox.coach.latest?.createdAt ?? null,
			},
		),
	);
	const coach = $derived(messagesInbox.coach);
	const pinned = $derived(coach?.placement === 'pinned');

	// The row opens the conversation its preview came from; with none, the
	// Coach picks the runner's current plan.
	const coachHref = $derived.by(() => {
		const latest = coach?.latest;
		if (!latest) return coachPath;
		return `${coachPath}?plan=${latest.planId === null ? 'none' : encodeURIComponent(latest.planId)}`;
	});

	// Without consent nothing the Coach said was read, so the row describes
	// the Coach instead of quoting it.
	const coachPreview = $derived.by(() => {
		const latest = coach?.latest;
		if (!coach?.consented || !latest) return m('messages.coachRowIntro');
		const text = coachInboxPreview(latest.content);
		return latest.role === 'user' ? m('messages.youPrefix') + text : text;
	});

	onMount(async () => {
		await auth.ready();
		ready = true;
	});

	// Loads whenever a user is present, not one-shot in onMount: ready()
	// resolves on its safety timeout even when the session hasn't settled yet
	// (slow device / loaded CI runner), and a mount-time `if (auth.user)` gate
	// would then skip the fetch forever.
	let loadedFor: string | null = null;
	$effect(() => {
		const uid = auth.user?.id ?? null;
		messagesInbox.bind(uid);
		if (!uid) {
			loadedFor = null;
			return;
		}
		if (loadedFor === uid) return;
		loadedFor = uid;
		void messagesInbox.loadThreads();
		void messagesInbox.loadCoach();
	});

	// The inbox re-reads every 30 s while the tab is visible, as mobile's does.
	$effect(() => {
		if (!auth.user) return;
		return startVisiblePoll(() => void messagesInbox.poll(), DM_INBOX_POLL_MS);
	});

	// Leaving the Coach conversation re-decides the row: the runner may have
	// just accepted the disclosure there, and has a newer message either way.
	let wasOnCoach = false;
	$effect(() => {
		const now = onCoach;
		if (wasOnCoach && !now) void messagesInbox.loadCoach();
		wasOnCoach = now;
	});

	let placing = $state(false);
	async function togglePin() {
		if (!coach || placing) return;
		placing = true;
		try {
			await messagesInbox.setCoachPlacement(pinned ? 'listed' : 'pinned');
		} catch (e) {
			showToast(m('prefs.saveFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			placing = false;
		}
	}
</script>

<div class="page">
	<h1 class="visually-hidden">{m('messages.heading')}</h1>
	{#if !ready}
		<p class="muted">{m('shell.loading')}</p>
	{:else if !auth.user}
		<p class="muted">{m('messages.signInPrompt')}</p>
	{:else}
		<div class="layout">
			<aside class="threads" class:has-active={hasActive}>
				<header class="pane-head"><h2>{m('messages.heading')}</h2></header>
				{#if messagesInbox.threadsError}
					<p class="muted empty" role="alert">
						{m('messages.threadsLoadFailed')}
						<button type="button" class="btn btn-secondary btn-sm" onclick={() => void messagesInbox.loadThreads()}>
							{m('messages.retry')}
						</button>
					</p>
				{/if}
				{#if entries.length > 0}
					<ul>
						{#each entries as entry (entry.kind === 'coach' ? 'coach' : dmThreadRouteId(entry.thread))}
							{#if entry.kind === 'coach'}
								<li class="coach-item">
									<a
										class="thread coach-row"
										class:active={onCoach}
										href={coachHref}
										data-testid="inbox-coach-row"
										data-placement={coach?.placement}
									>
										<span class="coach-avatar" aria-hidden="true">
											<span class="material-symbols">sports</span>
										</span>
										<span class="thread-body">
											<span class="thread-top">
												<strong>{m('nav.coach')}</strong>
												<AiTag />
												{#if pinned}
													<span class="pinned-mark" title={m('messages.coachPinned')}>
														<span class="material-symbols" aria-hidden="true">push_pin</span>
														<span class="visually-hidden">{m('messages.coachPinned')}</span>
													</span>
												{/if}
											</span>
											<span class="preview" data-testid="inbox-coach-preview">{coachPreview}</span>
										</span>
									</a>
									<button
										type="button"
										class="pin-toggle"
										data-testid="inbox-coach-pin"
										aria-pressed={pinned}
										disabled={placing}
										title={pinned ? m('messages.coachUnpin') : m('messages.coachPin')}
										aria-label={pinned ? m('messages.coachUnpin') : m('messages.coachPin')}
										onclick={togglePin}
									>
										<span class="material-symbols" aria-hidden="true">push_pin</span>
									</button>
								</li>
							{:else}
								{@const t = entry.thread}
								{@const routeId = dmThreadRouteId(t)}
								{@const name = t.partnerId
									? (t.partnerName ?? m('messages.runnerFallback'))
									: m('messages.deletedAccount')}
								<li>
									<a class="thread" class:active={routeId === activeId} href={`/messages/${routeId}`}>
										<Avatar
											url={t.partnerAvatar}
											name={t.partnerId ? t.partnerName : null}
											size="2.2rem"
											font="0.9rem"
											bg="seed"
											seedHue={hashHue(routeId)}
										/>
										<span class="thread-body">
											<span class="thread-top">
												<strong>{name}</strong>
												{#if t.unread > 0}<span class="badge">{t.unread}</span>{/if}
											</span>
											<span class="preview" class:unsent={t.lastUnsent}
												>{t.lastFromMe ? m('messages.youPrefix') : ''}{t.lastUnsent
													? m('messages.unsentPlaceholder')
													: t.lastBody}</span
											>
										</span>
									</a>
								</li>
							{/if}
						{/each}
					</ul>
				{/if}
				{#if !messagesInbox.threadsError && messagesInbox.threads.length === 0}
					<p class="muted empty">{m('messages.emptyThreads')}</p>
				{/if}
			</aside>

			<section class="conversation" class:has-active={hasActive}>
				{@render children()}
			</section>
		</div>
	{/if}
</div>

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
		min-width: 0;
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
	.preview.unsent {
		font-style: italic;
	}
	/* The pin control sits beside the row's link, not inside it: a button
	   inside an anchor is invalid and would also navigate. */
	.coach-item {
		position: relative;
		display: flex;
		align-items: stretch;
		border-bottom: 1px solid var(--color-border);
	}
	.coach-item .coach-row {
		flex: 1 1 auto;
		min-width: 0;
		border-bottom: none;
		padding-inline-end: 0.25rem;
	}
	.coach-avatar {
		flex: 0 0 auto;
		width: 2.2rem;
		height: 2.2rem;
		border-radius: 50%;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: color-mix(in srgb, var(--section-coach) 14%, var(--color-surface));
		color: var(--section-coach-ink);
	}
	.coach-avatar .material-symbols {
		font-size: 1.25rem;
	}
	.pinned-mark {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-text-tertiary);
	}
	.pinned-mark .material-symbols {
		font-size: 0.95rem;
	}
	.pin-toggle {
		flex: 0 0 auto;
		align-self: center;
		margin-inline-end: var(--space-sm);
		min-width: 2.75rem;
		min-height: 2.75rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		border: 1px solid transparent;
		border-radius: var(--radius-md);
		color: var(--color-text-tertiary);
		cursor: pointer;
	}
	.pin-toggle[aria-pressed='true'] {
		color: var(--color-primary);
	}
	.pin-toggle:hover,
	.pin-toggle:focus-visible {
		border-color: var(--color-border);
		color: var(--color-primary);
	}
	.pin-toggle .material-symbols {
		font-size: 1.15rem;
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
	}
</style>
