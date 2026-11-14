<script lang="ts">
	import { onMount } from 'svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { goto } from '$app/navigation';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchSessionPlans, type SessionPlan } from '#lib/core/data.ts';
	import ListCard from '#lib/components/ListCard.svelte';
	import Modal from '#lib/components/Modal.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import OfficialBadge from '#lib/components/OfficialBadge.svelte';
	import SessionPlanEditor from '#lib/components/SessionPlanEditor.svelte';
	import { m as t } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';

	let plans = $state<SessionPlan[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let showCreate = $state(false);

	// fetchSessionPlans rethrows the Postgres error, and `loading` used to be
	// cleared only on the success path — so any failure left the page on its
	// spinner forever, with nothing said and nothing to retry.
	async function load() {
		loading = true;
		loadError = null;
		try {
			plans = await fetchSessionPlans();
		} catch (e) {
			loadError = errorCopy(e, t, 'sessions: loadError');
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) {
			loading = false;
			return;
		}
		await load();
	});

	function onCreated(id: string) {
		showCreate = false;
		goto(`/sessions/${id}`);
	}
</script>

<svelte:head><title>{t('session.title')}</title></svelte:head>

<div class="page">
	<PageHeader back={{ href: '/gym', label: t('gym.back') }} title={t('session.title')}>
		{#snippet actions()}
			<button type="button" class="btn btn-primary" onclick={() => (showCreate = true)}>
				{t('session.new')}
			</button>
		{/snippet}
	</PageHeader>

	{#if loading}
		<p class="muted">…</p>
	{:else if loadError !== null}
		<div class="error-banner" role="alert" data-testid="sessions-load-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{t('session.loadError')}</strong>
				{#if loadError}<span class="error-detail">{loadError}</span>{/if}
			</div>
			<button class="btn btn-outline" onclick={load}>{t('session.run.retry')}</button>
		</div>
	{:else if plans.length === 0}
		<EmptyState
			icon="self_improvement"
			title={t('session.empty')}
			text={t('session.emptyHint')}
			data-testid="sessions-empty"
		/>
	{:else}
		<ul class="plan-list">
			{#each plans as plan (plan.id)}
				<li>
					<ListCard
						class="plan-row"
						href={`/sessions/${plan.id}`}
						title={plan.title || t('session.untitled')}
						subtitle={[
							plan.discipline,
							plan.est_duration_min
								? t('session.estDuration', { minutes: plan.est_duration_min })
								: null,
						]
							.filter(Boolean)
							.join(' · ') || undefined}
						chevron
					>
						{#snippet badge()}{#if plan.is_official}<OfficialBadge />{/if}{/snippet}
					</ListCard>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Modal open={showCreate} title={t('session.new')} onclose={() => (showCreate = false)}>
	<SessionPlanEditor oncreated={onCreated} oncancel={() => (showCreate = false)} />
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
	.plan-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
</style>
