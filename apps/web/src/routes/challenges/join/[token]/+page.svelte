<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import {
		joinChallengeByToken,
		previewChallengeInvite,
		type ChallengeInvitePreview
	} from '#lib/core/data.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		challengeWindowLabel,
		formatChallengeGoal
	} from '#lib/format/challenge_labels.svelte.ts';
	import { runnerHandle } from '#lib/social/runner_handle.ts';

	const token = $derived(page.params.token ?? '');
	let status = $state<'loading' | 'ready' | 'missing' | 'loadFailed'>('loading');
	let preview = $state<ChallengeInvitePreview | null>(null);
	let busy = $state(false);
	let joinError = $state<string | null>(null);

	const returnTo = $derived(encodeURIComponent(page.url.pathname));
	const creator = $derived(
		preview
			? (preview.creator_name ??
					runnerHandle(preview.creator_id, {
						handle: (slug) => m('live.runnerHandle', { slug }),
						anonymous: m('checkpoint.anonymousRunner')
					}))
			: ''
	);

	async function load() {
		status = 'loading';
		try {
			// Auth first: the preview's `joined` flag is the caller's, and a hard
			// reload races the session restore.
			await auth.ready();
			preview = await previewChallengeInvite(token);
			status = preview ? 'ready' : 'missing';
		} catch (e) {
			console.error('challenge invite preview failed', e);
			status = 'loadFailed';
		}
	}

	onMount(load);

	async function join() {
		if (busy || !preview) return;
		busy = true;
		joinError = null;
		try {
			const id = await joinChallengeByToken(token);
			if (!id) {
				status = 'missing';
				return;
			}
			goto(`/challenges/${id}`);
		} catch (e) {
			joinError = errorCopy(e, m, 'challengeJoin.joinFailed', 'challengeJoin.joinFailed');
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>{preview?.title ?? m('challengeJoin.pageTitle')}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<div class="invite-page">
	<header class="invite-header">
		<a href="/" class="logo">
			<img src="/logo-mark.svg" alt="" class="logo-mark" />
			<span>Threkir</span>
		</a>
	</header>

	<main class="invite-main" id="main-content" aria-live="polite">
		{#if status === 'loading'}
			<section class="invite-card">
				<p class="muted" role="status">{m('challengeJoin.loading')}</p>
			</section>
		{:else if status === 'loadFailed'}
			<section class="invite-card" data-testid="challenge-join-load-failed">
				<h1>{m('challengeJoin.loadFailedTitle')}</h1>
				<p class="muted">{m('challengeJoin.loadFailedBody')}</p>
				<div class="invite-actions">
					<button type="button" class="btn btn-primary" onclick={load}>
						{m('challenges.retry')}
					</button>
				</div>
			</section>
		{:else if status === 'missing' || !preview}
			<section class="invite-card" data-testid="challenge-join-missing">
				<p class="kicker">{m('clubJoin.hmm')}</p>
				<h1>{m('challengeJoin.missingTitle')}</h1>
				<p class="muted">{m('challengeJoin.missingBody')}</p>
				<div class="invite-actions">
					<a class="btn btn-primary" href="/challenges">{m('challengeJoin.browse')}</a>
				</div>
			</section>
		{:else}
			<section class="invite-card" data-testid="challenge-join-card">
				<p class="kicker">{m('challengeJoin.kicker', { name: creator })}</p>
				<h1>{preview.title}</h1>
				<div class="chips">
					<span class="chip">{challengeWindowLabel(preview)}</span>
					{#if preview.goal_value != null}
						<span class="chip goal">{formatChallengeGoal(preview.metric, preview.goal_value)}</span>
					{/if}
					<span class="chip">
						{m('challengeJoin.participants', { n: preview.participant_count })}
					</span>
				</div>
				{#if preview.description}
					<p class="desc">{preview.description}</p>
				{/if}

				{#if preview.joined}
					<p class="muted">{m('challengeJoin.alreadyIn')}</p>
					<div class="invite-actions">
						<a class="btn btn-primary" href={`/challenges/${preview.id}`}>
							{m('challengeJoin.openChallenge')}
						</a>
					</div>
				{:else if auth.loggedIn}
					<div class="invite-actions">
						<button
							type="button"
							class="btn btn-primary"
							onclick={join}
							disabled={busy}
							data-testid="challenge-join-button"
						>
							{busy ? m('challengeJoin.joining') : m('challengeJoin.join')}
						</button>
					</div>
				{:else}
					<p class="muted">{m('challengeJoin.signInBody')}</p>
					<div class="invite-actions">
						<a class="btn btn-primary" href="/login?signup=1&return_to={returnTo}">
							{m('clubJoin.createFreeAccount')}
						</a>
						<a class="btn btn-outline" href="/login?return_to={returnTo}">
							{m('clubJoin.signIn')}
						</a>
					</div>
				{/if}
				{#if joinError}
					<p class="error" role="alert">{joinError}</p>
				{/if}
			</section>
		{/if}
	</main>
</div>

<style>
	.invite-page {
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		background: var(--color-bg);
	}
	.invite-header {
		padding: var(--space-md) var(--space-xl);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}
	.logo {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-text);
		text-decoration: none;
	}
	.logo-mark {
		width: 1.85rem;
		height: 1.85rem;
		border-radius: var(--radius-md);
		display: block;
	}
	.invite-main {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-xl) var(--space-md);
	}
	.invite-card {
		width: 100%;
		max-width: 32rem;
		padding: var(--space-2xl) var(--space-xl);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-lg);
		text-align: center;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.72rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-xs);
	}
	h1 {
		margin: 0 0 var(--space-sm);
		font-size: 1.7rem;
		font-weight: 800;
		color: var(--color-text);
		line-height: 1.2;
		overflow-wrap: anywhere;
	}
	.chips {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-xs);
		margin: 0 0 var(--space-md);
	}
	.chip {
		padding: 0.2rem 0.6rem;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 600;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
	}
	.chip.goal {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.desc {
		margin: 0 0 var(--space-lg);
		color: var(--color-text-secondary);
		overflow-wrap: anywhere;
	}
	.muted {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		margin: 0 0 var(--space-lg);
		line-height: 1.5;
	}
	.error {
		color: var(--color-danger-text);
		margin: var(--space-md) 0 0;
		font-size: 0.88rem;
	}
	.invite-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
</style>
