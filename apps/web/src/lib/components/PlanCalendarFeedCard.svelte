<script lang="ts">
	import { onMount } from 'svelte';
	import { PUBLIC_SUPABASE_URL } from '$app/env/public';
	import { supabase } from '#lib/core/supabase.ts';
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { formatRelativeTime } from '#lib/format/time.ts';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { rateLimitErrorMessage } from '#lib/i18n/rate_limit_message.ts';
	import {
		fetchPlanCalendarFeedStatus,
		planCalendarFeedUrl,
		revokePlanCalendarFeed,
		rotatePlanCalendarFeed,
		webcalUrl,
		type PlanCalendarFeedStatus,
	} from '#lib/training/plan_calendar_feed.ts';

	let loading = $state(true);
	let loadFailed = $state(false);
	let status = $state<PlanCalendarFeedStatus | null>(null);
	// The token exists in this component only between minting it and leaving
	// the page: the server keeps its hash and nothing can read it back.
	let freshUrl = $state<string | null>(null);
	let busy = $state(false);
	let actionError = $state<string | null>(null);
	let copied = $state(false);
	let confirming = $state<'rotate' | 'revoke' | null>(null);

	const subscribeUrl = $derived(freshUrl ? webcalUrl(freshUrl) : null);

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			status = await fetchPlanCalendarFeedStatus(supabase);
		} catch (e) {
			console.error('plan calendar feed: status failed', e);
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	onMount(load);

	async function mint() {
		busy = true;
		actionError = null;
		copied = false;
		try {
			const token = await rotatePlanCalendarFeed(supabase);
			freshUrl = planCalendarFeedUrl(PUBLIC_SUPABASE_URL, token);
			status = { createdAt: new Date().toISOString(), lastFetchedAt: null };
		} catch (e) {
			console.error('plan calendar feed: rotate failed', e);
			actionError =
				rateLimitErrorMessage(m, e as { code?: string; message?: string }) ??
				m('planCalendarFeed.createFailed');
		} finally {
			busy = false;
			confirming = null;
		}
	}

	async function revoke() {
		busy = true;
		actionError = null;
		try {
			await revokePlanCalendarFeed(supabase);
			status = null;
			freshUrl = null;
			copied = false;
		} catch (e) {
			console.error('plan calendar feed: revoke failed', e);
			actionError = m('planCalendarFeed.revokeFailed');
		} finally {
			busy = false;
			confirming = null;
		}
	}

	async function copy() {
		if (!freshUrl) return;
		try {
			await navigator.clipboard.writeText(freshUrl);
			copied = true;
		} catch (e) {
			console.error('plan calendar feed: copy failed', e);
			actionError = m('planCalendarFeed.copyFailed');
		}
	}
</script>

<section class="card feed-card" data-testid="plan-calendar-feed-card">
	<h2>{m('planCalendarFeed.title')}</h2>
	<p class="card-sub">{m('planCalendarFeed.description')}</p>

	{#if loading}
		<p class="card-sub" role="status">{m('planCalendarFeed.loading')}</p>
	{:else if loadFailed}
		<p class="error" role="alert" data-testid="plan-calendar-feed-load-error">
			{m('planCalendarFeed.loadFailed')}
		</p>
		<button type="button" class="btn btn-outline btn-sm" onclick={load}>
			{m('planCalendarFeed.retry')}
		</button>
	{:else if status === null}
		<button
			type="button"
			class="btn btn-primary btn-sm"
			onclick={mint}
			disabled={busy}
			data-testid="plan-calendar-feed-create"
		>
			{m('planCalendarFeed.create')}
		</button>
	{:else}
		{#if freshUrl}
			<label class="url-label" for="plan-calendar-feed-url">{m('planCalendarFeed.urlLabel')}</label>
			<input
				id="plan-calendar-feed-url"
				class="url"
				type="text"
				readonly
				value={freshUrl}
				onfocus={(e) => e.currentTarget.select()}
				data-testid="plan-calendar-feed-url"
			/>
			<p class="note" data-testid="plan-calendar-feed-once">{m('planCalendarFeed.shownOnce')}</p>
			<div class="actions">
				<button type="button" class="btn btn-primary btn-sm" onclick={copy} data-testid="plan-calendar-feed-copy">
					{copied ? m('planCalendarFeed.copied') : m('planCalendarFeed.copy')}
				</button>
				{#if subscribeUrl}
					<a class="btn btn-outline btn-sm" href={subscribeUrl} data-testid="plan-calendar-feed-subscribe">
						{m('planCalendarFeed.subscribe')}
					</a>
				{/if}
			</div>
		{:else}
			<p class="card-sub" data-testid="plan-calendar-feed-active">
				{m('planCalendarFeed.activeSince', {
					when: formatRelativeTime(status.createdAt, Date.now(), currentLocale()),
				})}
				{status.lastFetchedAt
					? m('planCalendarFeed.lastRead', {
							when: formatRelativeTime(status.lastFetchedAt, Date.now(), currentLocale()),
						})
					: m('planCalendarFeed.neverRead')}
			</p>
			<p class="note">{m('planCalendarFeed.lostLink')}</p>
		{/if}
		<div class="actions">
			<button
				type="button"
				class="btn btn-outline btn-sm"
				onclick={() => (confirming = 'rotate')}
				disabled={busy}
				data-testid="plan-calendar-feed-rotate"
			>
				{m('planCalendarFeed.rotate')}
			</button>
			<button
				type="button"
				class="btn btn-outline btn-sm danger"
				onclick={() => (confirming = 'revoke')}
				disabled={busy}
				data-testid="plan-calendar-feed-revoke"
			>
				{m('planCalendarFeed.revoke')}
			</button>
		</div>
	{/if}

	{#if actionError}
		<p class="error" role="alert" data-testid="plan-calendar-feed-error">{actionError}</p>
	{/if}
	<p class="note">{m('planCalendarFeed.privacy')}</p>
</section>

<ConfirmDialog
	open={confirming === 'rotate'}
	title={m('planCalendarFeed.rotateTitle')}
	message={m('planCalendarFeed.rotateMessage')}
	confirmLabel={m('planCalendarFeed.rotate')}
	onconfirm={mint}
	oncancel={() => (confirming = null)}
/>
<ConfirmDialog
	open={confirming === 'revoke'}
	title={m('planCalendarFeed.revokeTitle')}
	message={m('planCalendarFeed.revokeMessage')}
	confirmLabel={m('planCalendarFeed.revoke')}
	danger
	onconfirm={revoke}
	oncancel={() => (confirming = null)}
/>

<style>
	.feed-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-top: var(--space-xl);
	}
	.feed-card h2 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0 0 var(--space-xs);
	}
	.card-sub,
	.note {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
		line-height: 1.45;
	}
	.note {
		font-size: 0.78rem;
	}
	.url-label {
		display: block;
		font-size: 0.85rem;
		font-weight: 600;
		margin-bottom: var(--space-2xs);
	}
	.url {
		width: 100%;
		box-sizing: border-box;
		font-family: var(--font-mono, monospace);
		font-size: 0.8rem;
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		margin-bottom: var(--space-xs);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin-bottom: var(--space-md);
	}
	.danger {
		color: var(--color-danger-text);
		border-color: var(--color-danger-text);
	}
	.error {
		color: var(--color-danger-text);
		font-size: 0.85rem;
		margin: 0 0 var(--space-md);
	}
</style>
