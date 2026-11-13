<script lang="ts">
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchGymRoutinesWithError, type GymRoutineSummary } from '#lib/core/data.ts';
	import { formatDate } from '#lib/format/time.ts';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { m as t } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';

	let routines = $state<GymRoutineSummary[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);

	async function load() {
		loading = true;
		loadError = null;
		const result = await fetchGymRoutinesWithError(100);
		routines = result.routines;
		loadError = result.error ? errorCopy(result.error, t, 'gym routines: loadError') : null;
		loading = false;
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) return;
		await load();
	});
</script>

<svelte:head><title>{t('gym.routine.title')} — Threkir</title></svelte:head>

<div class="page">
	<PageHeader
		back={{ href: '/gym', label: t('gym.back') }}
		title={t('gym.routine.title')}
		subtitle={!loading && routines.length > 0 ? t('gym.routine.subtitle', { count: routines.length }) : undefined}
	>
		{#snippet actions()}
			<a class="btn btn-outline" href="/gym/routines/library" data-testid="routine-library">
				<span class="material-symbols" aria-hidden="true">public</span>
				{t('gymLibrary.link')}
			</a>
			<a class="btn btn-primary" href="/gym/routines/new" data-testid="routine-new">
				<span class="material-symbols" aria-hidden="true">add</span>
				{t('gym.routine.new')}
			</a>
		{/snippet}
	</PageHeader>

	{#if loading}
		<ul class="routine-list" aria-hidden="true" data-testid="routine-skeleton">
			{#each Array(4) as _, i (i)}
				<li class="card-elevated routine-row">
					<div class="row-main">
						<SkeletonBlock height="1rem" width="{40 + (i % 3) * 12}%" />
						<SkeletonBlock height="0.8rem" width="24%" />
					</div>
					<SkeletonBlock height="2rem" width="3rem" />
				</li>
			{/each}
		</ul>
		<p class="visually-hidden" role="status">{t('shell.loading')}</p>
	{:else if loadError}
		<div class="error-banner" role="alert">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{t('gym.routine.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{t('gym.routine.retry')}</button>
		</div>
	{:else if routines.length === 0}
		<EmptyState
			icon="list_alt"
			title={t('gym.routine.empty.title')}
			text={t('gym.routine.empty.body')}
			data-testid="routine-empty"
		/>
	{:else}
		<ul class="routine-list" data-testid="routine-list">
			{#each routines as r (r.id)}
				<li>
					<a class="card-elevated routine-row" href="/gym/routines/{r.id}">
						<div class="row-main">
							<span class="row-title">{r.title}</span>
							<span class="row-date">{formatDate(r.last_modified_at)}</span>
						</div>
						<div class="row-stats">
							<span class="stat">
								<span class="stat-value">{r.exercise_count}</span>
								<span class="stat-label section-label"
									>{t('gym.exercisesLabel')}</span
								>
							</span>
							<span class="material-symbols chevron" aria-hidden="true">chevron_right</span>
						</div>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.routine-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.routine-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md);
		text-decoration: none;
		color: inherit;
	}
	.row-main {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.row-title {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.row-date {
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}
	.row-stats {
		display: flex;
		align-items: center;
		gap: var(--space-md);
	}
	.stat {
		display: flex;
		flex-direction: column;
		align-items: center;
	}
	.stat-value {
		font-weight: 600;
	}
	.chevron {
		color: var(--color-text-tertiary);
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
	.error-banner .material-symbols {
		color: var(--color-danger-text);
		font-size: 1.4rem;
	}
</style>
