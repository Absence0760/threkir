<script lang="ts">
	// Naming disputes, each side's view (issue #1363, decisions § 2441). The
	// owner of disputed content reads what a reviewer decided and any rename
	// deadline; a verified organiser reads what became of its reports. The
	// reviewer is never named: my_organiser_disputes does not return one.
	import EmptyState from '#lib/components/EmptyState.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { formatDate, formatRelativeTime } from '#lib/format/time.ts';
	import { fetchMyOrganiserDisputes, type MyOrganiserDispute } from '#lib/core/data.ts';
	import {
		deadlinePassed,
		disputeKindLabelKey,
		disputeStatusKey,
		disputeTargetHref,
	} from '#lib/social/organiser_dispute.ts';

	let rows = $state<MyOrganiserDispute[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	const mine = $derived(rows.filter((r) => r.side === 'owner'));
	const filed = $derived(rows.filter((r) => r.side === 'organiser'));

	async function load() {
		loading = true;
		loadError = null;
		try {
			rows = await fetchMyOrganiserDisputes();
		} catch (e) {
			loadError = errorCopy(e, m, 'disputes: loadError');
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		if (auth.loggedIn) load();
	});
</script>

<svelte:head>
	<title>{m('organiserDispute.pageTitle')}</title>
</svelte:head>

{#snippet item(r: MyOrganiserDispute)}
	<li class="row" data-testid="dispute-row">
		<div class="top">
			<span class="kind">{m(disputeKindLabelKey(r.target_kind))}</span>
			<a href={disputeTargetHref(r.target_kind, r.target_id)} class="target">
				{r.target_label ?? m('organiserDispute.untitled')}
			</a>
		</div>
		<p class="status" data-testid="dispute-status">
			{m(disputeStatusKey(r.action, r.side), { club: r.organiser_club_name })}
		</p>
		{#if r.action === 'rename_notice' && r.deadline_at}
			<p class="deadline" class:overdue={deadlinePassed(r.deadline_at)} data-testid="dispute-deadline">
				{deadlinePassed(r.deadline_at)
					? m('organiserDispute.deadlinePassed', { date: formatDate(r.deadline_at) })
					: m('organiserDispute.deadlineOn', { date: formatDate(r.deadline_at) })}
			</p>
		{/if}
		{#if r.note}
			<blockquote class="note">{r.note}</blockquote>
		{/if}
		<p class="when">{formatRelativeTime(r.acted_at)}</p>
	</li>
{/snippet}

<div class="page">
	<PageHeader flush title={m('organiserDispute.pageTitle')} subtitle={m('organiserDispute.pageTagline')} />

	{#if loading}
		<p class="muted" role="status">{m('profile.loadingShort')}</p>
	{:else if loadError !== null}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('organiserDispute.loadError')}</strong>
				{#if loadError}<span class="error-detail">{loadError}</span>{/if}
			</div>
			<button class="btn btn-outline" onclick={load}>{m('followRequests.retry')}</button>
		</div>
	{:else if rows.length === 0}
		<EmptyState
			icon="inbox"
			title={m('organiserDispute.emptyTitle')}
			text={m('organiserDispute.emptyText')}
			data-testid="disputes-empty"
		/>
	{:else}
		{#if mine.length > 0}
			<section aria-labelledby="disputes-mine">
				<h2 id="disputes-mine">{m('organiserDispute.sectionMine')}</h2>
				<ul class="list" data-testid="disputes-mine">
					{#each mine as r (r.target_kind + r.target_id + r.organiser_club_id)}
						{@render item(r)}
					{/each}
				</ul>
			</section>
		{/if}
		{#if filed.length > 0}
			<section aria-labelledby="disputes-filed">
				<h2 id="disputes-filed">{m('organiserDispute.sectionFiled')}</h2>
				<ul class="list" data-testid="disputes-filed">
					{#each filed as r (r.target_kind + r.target_id + r.organiser_club_id)}
						{@render item(r)}
					{/each}
				</ul>
			</section>
		{/if}
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 40rem;
		margin: 0 auto;
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	h2 {
		font-size: 1rem;
		margin: 0 0 var(--space-sm);
	}
	.muted,
	.when {
		color: var(--color-text-secondary);
		margin: 0;
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.row {
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
	}
	.top {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0.5rem;
	}
	.kind {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--color-text-secondary);
	}
	.target {
		font-weight: 600;
		color: var(--color-primary);
		overflow-wrap: anywhere;
	}
	.status,
	.deadline {
		margin: 0;
		font-size: 0.9rem;
	}
	.deadline.overdue {
		color: var(--color-danger-text);
		font-weight: 600;
	}
	.note {
		margin: 0;
		padding: 0.4rem 0.7rem;
		border-inline-start: 3px solid var(--color-border);
		background: var(--color-bg-secondary);
		white-space: pre-wrap;
		font-size: 0.88rem;
	}
	.when {
		font-size: 0.78rem;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-danger-light);
		color: var(--color-danger-text);
	}
	.error-detail {
		display: block;
		font-size: 0.85rem;
	}
</style>
