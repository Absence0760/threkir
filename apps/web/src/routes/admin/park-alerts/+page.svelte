<script lang="ts">
	// Site-admin review of the NPS alerts the daily closures sweep flagged
	// against park courses (issue #1313 Phase 6, decisions § 2454). A flag never
	// changes a course: the admin reads the alert and closes the course here,
	// or files the flag. Every RPC hard-denies a non-admin at the database;
	// amIAdmin only picks the page chrome.
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import Modal from '#lib/components/Modal.svelte';
	import {
		amIAdmin,
		fetchParkNpsAlerts,
		reviewParkNpsAlert,
		type ParkNpsAlert,
		type ParkNpsAlertStatus,
	} from '#lib/core/data.ts';
	import { m as t, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { regionSlug } from '#lib/parks/park_courses.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	let isAdmin = $state<boolean | null>(null);
	let loading = $state(true);
	let view = $state<ParkNpsAlertStatus>('pending');
	let rows = $state<ParkNpsAlert[]>([]);
	let loadError = $state<string | null>(null);
	let busy = $state<number | null>(null);

	let closing = $state<ParkNpsAlert | null>(null);
	let note = $state('');
	let closeError = $state<string | null>(null);

	const views: ParkNpsAlertStatus[] = ['pending', 'reviewed', 'dismissed'];
	const viewLabel: Record<ParkNpsAlertStatus, MessageKey> = {
		pending: 'admin.parkAlerts.tabPending',
		reviewed: 'admin.parkAlerts.tabReviewed',
		dismissed: 'admin.parkAlerts.tabDismissed',
	};

	function fmtDate(iso: string): string {
		return new Intl.DateTimeFormat(currentLocale(), { dateStyle: 'medium' }).format(new Date(iso));
	}

	function courseHref(row: ParkNpsAlert): string {
		return `/parks/${regionSlug(row.region_code)}/${row.park_slug}/${row.course_slug}`;
	}

	// Tabs switch faster than the queue answers, so only the newest request may
	// land, and the actions follow the tab the rows were read for, not the one
	// that is selected while the next tab is still loading.
	let loadSeq = 0;
	let rowsView = $state<ParkNpsAlertStatus>('pending');

	async function load() {
		const seq = ++loadSeq;
		const requested = view;
		let nextRows: ParkNpsAlert[] = [];
		let nextError: string | null = null;
		try {
			nextRows = await fetchParkNpsAlerts(requested);
		} catch (e) {
			nextError = t('admin.parkAlerts.loadFailed', { error: errorCopy(e, t, 'park alerts queue failed') });
		} finally {
			if (seq === loadSeq) {
				rows = nextRows;
				rowsView = requested;
				loadError = nextError;
			}
		}
	}

	async function selectView(next: ParkNpsAlertStatus) {
		view = next;
		await load();
	}

	async function file(row: ParkNpsAlert, action: 'reviewed' | 'dismissed') {
		if (busy !== null) return;
		busy = row.id;
		try {
			await reviewParkNpsAlert(row.id, action);
			showToast(t('admin.parkAlerts.done'), 'success');
			await load();
		} catch (e) {
			showToast(t('admin.reports.course.failed', { error: errorCopy(e, t, 'park alert review failed') }), 'error');
		} finally {
			busy = null;
		}
	}

	function openClose(row: ParkNpsAlert) {
		closing = row;
		note = '';
		closeError = null;
	}

	async function runClose() {
		if (!closing || busy !== null) return;
		if (note.trim() === '') {
			closeError = t('admin.parkAlerts.noteRequired');
			return;
		}
		busy = closing.id;
		closeError = null;
		try {
			await reviewParkNpsAlert(closing.id, 'close', note);
			closing = null;
			showToast(t('admin.reports.course.doneClose'), 'success');
			await load();
		} catch (e) {
			closeError = t('admin.reports.course.failed', { error: errorCopy(e, t, 'park alert close failed') });
		} finally {
			busy = null;
		}
	}

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) await load();
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.parkAlerts.title')}</title></svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="park-alerts-not-authorized">
			<h1>{t('admin.reports.notAuthorized')}</h1>
			<p class="muted">{t('admin.reports.notAuthorizedHint')}</p>
		</div>
	{:else}
		<header>
			<h1>{t('admin.parkAlerts.title')}</h1>
			<p class="muted">{t('admin.parkAlerts.subtitle')}</p>
		</header>

		<div class="tabs" role="group" aria-label={t('admin.parkAlerts.title')}>
			{#each views as v (v)}
				<button
					type="button"
					class="btn-secondary btn-sm"
					class:active={view === v}
					aria-pressed={view === v}
					onclick={() => selectView(v)}
					data-testid={`park-alerts-tab-${v}`}
				>
					{t(viewLabel[v])}
				</button>
			{/each}
		</div>

		{#if loadError}
			<EmptyState icon="error" tone="danger" title={loadError} role="alert" />
		{:else if rows.length === 0}
			<EmptyState icon="park" title={t('admin.parkAlerts.empty')} data-testid="park-alerts-empty" />
		{:else}
			<ul class="alert-queue">
				{#each rows as row (row.id)}
					<li class="card-elevated" data-testid="park-alert-row" data-course={row.course_slug}>
						<div class="row-head">
							<a href={courseHref(row)}><strong>{row.course_name}</strong></a>
							<span class="muted">{row.park_name}</span>
						</div>
						<p class="alert-title"><span class="category">{row.category}</span> {row.title}</p>
						{#if row.description}
							<p class="description">{row.description}</p>
						{/if}
						<p class="muted meta">
							{row.match === 'park_wide' ? t('admin.parkAlerts.matchParkWide') : t('admin.parkAlerts.matchNamed')}
							· {t('admin.parkAlerts.firstSeen', { date: fmtDate(row.first_seen_at) })}
							{#if row.gone_at}
								· <span data-testid="park-alert-gone">{t('admin.parkAlerts.gone')}</span>
							{/if}
						</p>
						{#if row.course_status === 'closed'}
							<p class="hint">{t('admin.parkAlerts.courseClosed')}</p>
						{/if}
						<div class="actions">
							{#if rowsView === 'pending' && row.course_status !== 'closed'}
								<button class="btn-danger btn-sm" type="button" onclick={() => openClose(row)} data-testid="park-alert-close">
									{t('admin.reports.course.close')}
								</button>
							{/if}
							{#if rowsView === 'pending'}
								<button
									class="btn-secondary btn-sm"
									type="button"
									disabled={busy === row.id}
									onclick={() => file(row, 'reviewed')}
									data-testid="park-alert-reviewed"
								>
									{t('admin.parkAlerts.markReviewed')}
								</button>
								<button
									class="btn-secondary btn-sm"
									type="button"
									disabled={busy === row.id}
									onclick={() => file(row, 'dismissed')}
									data-testid="park-alert-dismiss"
								>
									{t('admin.parkAlerts.dismiss')}
								</button>
							{/if}
							{#if row.url}
								<a class="btn-secondary btn-sm" href={row.url} target="_blank" rel="noopener noreferrer nofollow">
									{t('admin.parkAlerts.readAlert')}
								</a>
							{/if}
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<Modal
	open={closing !== null}
	onclose={() => (closing = null)}
	title={t('admin.reports.course.confirmCloseTitle')}
	narrow
	data-testid="park-alert-close-dialog"
>
	<form
		class="editor-form"
		onsubmit={(e) => {
			e.preventDefault();
			void runClose();
		}}
	>
		<p>{t('admin.parkAlerts.closeBody')}</p>
		<label for="park-alert-close-note">{t('admin.reports.course.noteLabel')}</label>
		<textarea
			id="park-alert-close-note"
			rows="3"
			maxlength="500"
			placeholder={t('admin.reports.course.notePlaceholder')}
			bind:value={note}
			data-testid="park-alert-close-note"
		></textarea>
		{#if closeError}
			<p class="error" role="alert">{closeError}</p>
		{/if}
		<div class="modal-actions">
			<button class="btn-secondary" type="button" onclick={() => (closing = null)}>{t('common.cancel')}</button>
			<button class="btn-danger" type="submit" disabled={busy !== null} data-testid="park-alert-close-confirm">
				{t('admin.reports.course.close')}
			</button>
		</div>
	</form>
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 64rem;
	}
	header h1,
	.not-authorized h1 {
		margin: 0 0 0.25rem;
		font-size: 1.4rem;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.not-authorized {
		padding: var(--space-xl);
		text-align: center;
	}
	.tabs {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.tabs .active {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.alert-queue {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.alert-queue li {
		padding: var(--space-lg);
	}
	.row-head {
		display: flex;
		gap: var(--space-sm);
		align-items: baseline;
		flex-wrap: wrap;
	}
	.alert-title {
		margin: var(--space-sm) 0 0;
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.category {
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-warning-text);
		margin-inline-end: 0.4rem;
	}
	.description {
		margin: var(--space-xs, 0.25rem) 0 0;
		overflow-wrap: anywhere;
	}
	.meta {
		margin: var(--space-sm) 0 0;
		font-size: 0.85rem;
	}
	.hint {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: var(--space-sm) 0 0;
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
		margin-top: var(--space-md);
	}
	.modal-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
	.error {
		color: var(--color-danger-text);
	}
</style>
