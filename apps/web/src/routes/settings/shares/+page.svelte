<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import {
		fetchMyShareStats,
		shareAttributionEnabled,
		type ShareStat,
	} from '#lib/share/share_attribution.ts';
	import type { TrackedShareKind } from '#lib/share/share_ref.ts';

	type Load = { kind: 'loading' } | { kind: 'off' } | { kind: 'failed' } | { kind: 'ready'; rows: ShareStat[] };

	let view = $state<Load>({ kind: 'loading' });

	const KIND_LABELS: Record<TrackedShareKind, MessageKey> = {
		plan: 'shares.kindPlan',
		challenge: 'shares.kindChallenge',
		profile: 'shares.kindProfile',
		session: 'shares.kindSession',
		workout: 'shares.kindWorkout',
	};

	function rowTitle(row: ShareStat): string {
		if (row.kind === 'profile') return m('shares.yourProfile');
		return row.title?.trim() || m('shares.untitled');
	}

	function shareHref(row: ShareStat): string {
		return `/share/${row.kind}/${row.entityId}`;
	}

	async function load() {
		view = { kind: 'loading' };
		try {
			if (!(await shareAttributionEnabled())) {
				view = { kind: 'off' };
				return;
			}
			view = { kind: 'ready', rows: await fetchMyShareStats() };
		} catch (e) {
			console.error('my_share_stats failed', e);
			view = { kind: 'failed' };
		}
	}

	onMount(load);
</script>

<svelte:head>
	<title>{m('shares.heading')} — Threkir</title>
</svelte:head>

<div class="page">
	<header>
		<h1>{m('shares.heading')}</h1>
		<p class="tagline">{m('shares.tagline')}</p>
	</header>

	{#if view.kind === 'loading'}
		<p class="state" role="status">{m('shares.loading')}</p>
	{:else if view.kind === 'off'}
		<p class="state" data-testid="shares-off">{m('shares.unavailable')}</p>
	{:else if view.kind === 'failed'}
		<div class="state" role="alert">
			<p>{m('shares.loadFailed')}</p>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>{m('shares.retry')}</button>
		</div>
	{:else if view.rows.length === 0}
		<p class="state" data-testid="shares-empty">{m('shares.empty')}</p>
	{:else}
		<ul class="links" data-testid="shares-list">
			{#each view.rows as row (`${row.kind}:${row.entityId}`)}
				<li class="card" data-testid="share-row">
					<div class="head">
						<span class="kind">{m(KIND_LABELS[row.kind])}</span>
						<a class="title" href={shareHref(row)}>{rowTitle(row)}</a>
					</div>
					<dl class="stats">
						<div>
							<dt>{m('shares.visits')}</dt>
							<dd data-testid="share-visits">{row.visits}</dd>
							{#if row.refVisits > 0}
								<dd class="sub">{m('shares.viaYourLink', { n: row.refVisits })}</dd>
							{/if}
						</div>
						<div>
							<dt>{m('shares.signups')}</dt>
							<dd data-testid="share-signups">{row.signups}</dd>
						</div>
						{#if row.kind === 'plan'}
							<div>
								<dt>{m('shares.starts')}</dt>
								<dd data-testid="share-starts">{row.starts}</dd>
								{#if row.refStarts > 0}
									<dd class="sub">{m('shares.viaYourLink', { n: row.refStarts })}</dd>
								{/if}
							</div>
						{:else if row.kind === 'challenge'}
							<div>
								<dt>{m('shares.joins')}</dt>
								<dd data-testid="share-joins">{row.joins}</dd>
								{#if row.refJoins > 0}
									<dd class="sub">{m('shares.viaYourLink', { n: row.refJoins })}</dd>
								{/if}
							</div>
						{/if}
					</dl>
					{#if row.botVisits > 0}
						<p class="bots">{m('shares.botVisits', { n: row.botVisits })}</p>
					{/if}
				</li>
			{/each}
		</ul>
		<p class="footnote">{m('shares.footnote')}</p>
	{/if}
</div>

<style>
	.page {
		max-width: 48rem;
		padding: var(--space-lg) var(--space-md);
	}
	h1 {
		font-size: 1.5rem;
		margin: 0 0 var(--space-xs);
	}
	.tagline,
	.footnote,
	.bots {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.5;
		margin: 0;
	}
	header {
		margin-bottom: var(--space-lg);
	}
	.state {
		color: var(--color-text-secondary);
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
	}
	.links {
		list-style: none;
		margin: 0 0 var(--space-md);
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.kind {
		font-size: 0.75rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
	}
	.title {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.stats {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-md) var(--space-xl);
		margin: 0;
	}
	.stats dt {
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.stats dd {
		margin: 0;
		font-size: 1.25rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.stats dd.sub {
		font-size: 0.8rem;
		font-weight: 400;
		color: var(--color-text-secondary);
	}
</style>
