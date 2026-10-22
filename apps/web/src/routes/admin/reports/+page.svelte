<script lang="ts">
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import {
		amIAdmin,
		fetchPendingReports,
		fetchReportsForTarget,
		resolveTargetReports,
		adminUnhideTarget,
		fetchResolvedReports,
		setReportLegalHold,
		type PendingReportTarget,
		type ResolvedReportTarget,
		type TargetReport,
		type ReportTargetKind,
		type ReportResolution,
	} from '#lib/core/data.ts';
	import { formatDate, formatRelativeTime } from '#lib/format/time.ts';
	import Modal from '#lib/components/Modal.svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { m as t } from '#lib/i18n/store.svelte.ts';
	import { reportTargetHref, reportTargetLabelKey } from './report_target';

	type QueueTarget = Pick<
		PendingReportTarget,
		'target_kind' | 'target_id' | 'page_id' | 'shadow_hidden' | 'report_count'
	>;

	let isAdmin = $state<boolean | null>(null);
	let loading = $state(true);
	let view = $state<'pending' | 'resolved'>('pending');
	let queue = $state<PendingReportTarget[]>([]);
	let resolved = $state<ResolvedReportTarget[]>([]);
	let resolvedLoaded = $state(false);
	let resolvedLoading = $state(false);
	let resolvedError = $state<string | null>(null);

	let selected = $state<QueueTarget | null>(null);
	let detail = $state<TargetReport[]>([]);
	let detailLoading = $state(false);
	let resolution = $state('');
	let resolving = $state(false);
	let unhiding = $state(false);
	let confirm = $state<{ status: ReportResolution } | null>(null);
	let confirmUnhide = $state(false);
	let holdBusy = $state<string | null>(null);
	let confirmLiftHold = $state<TargetReport | null>(null);
	let hasPending = $derived(detail.some((r) => r.status === 'pending'));

	function kindLabel(kind: ReportTargetKind): string {
		const key = reportTargetLabelKey(kind);
		return key ? t(key) : kind;
	}

	function statusLabel(status: string): string {
		if (status === 'reviewed') return t('admin.reports.statusReviewed');
		if (status === 'dismissed') return t('admin.reports.statusDismissed');
		return t('admin.reports.statusPending');
	}

	async function loadQueue() {
		try {
			queue = await fetchPendingReports();
		} catch (e) {
			showToast(t('admin.reports.loadFailed', { error: thrownMessage(e) }), 'error');
		}
	}

	async function loadResolved() {
		resolvedLoading = true;
		resolvedError = null;
		try {
			resolved = await fetchResolvedReports();
			resolvedLoaded = true;
		} catch (e) {
			resolvedError = t('admin.reports.resolvedLoadFailed', { error: thrownMessage(e) });
		} finally {
			resolvedLoading = false;
		}
	}

	async function showView(next: 'pending' | 'resolved') {
		view = next;
		if (next === 'resolved' && !resolvedLoaded) await loadResolved();
	}

	async function setHold(report: TargetReport, hold: boolean) {
		if (holdBusy) return;
		holdBusy = report.id;
		try {
			await setReportLegalHold(report.id, hold);
			showToast(t(hold ? 'admin.reports.holdPlaced' : 'admin.reports.holdLifted'), 'success');
			if (selected) detail = await fetchReportsForTarget(selected.target_kind, selected.target_id);
			if (resolvedLoaded) await loadResolved();
		} catch (e) {
			showToast(t('admin.reports.holdFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			holdBusy = null;
		}
	}

	async function openTarget(target: QueueTarget) {
		selected = target;
		resolution = '';
		detail = [];
		detailLoading = true;
		try {
			detail = await fetchReportsForTarget(target.target_kind, target.target_id);
		} catch (e) {
			showToast(t('admin.reports.detailFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			detailLoading = false;
		}
	}

	function closeDetail() {
		selected = null;
		detail = [];
	}

	async function doResolve(status: ReportResolution) {
		if (!selected || resolving) return;
		resolving = true;
		const target = selected;
		try {
			const n = await resolveTargetReports(
				target.target_kind,
				target.target_id,
				status,
				resolution.trim() || null,
			);
			const msgKey = status === 'reviewed' ? 'admin.reports.resolvedReviewed' : 'admin.reports.resolvedDismissed';
			showToast(t(msgKey, { count: n }), 'success');
			closeDetail();
			await loadQueue();
			if (resolvedLoaded) await loadResolved();
		} catch (e) {
			showToast(t('admin.reports.resolveFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			resolving = false;
		}
	}

	async function doUnhide() {
		if (!selected || unhiding) return;
		unhiding = true;
		const target = selected;
		try {
			await adminUnhideTarget(target.target_kind, target.target_id);
			showToast(t('admin.reports.unhidden'), 'success');
			selected = { ...target, shadow_hidden: false };
			queue = queue.map((q) =>
				q.target_kind === target.target_kind && q.target_id === target.target_id
					? { ...q, shadow_hidden: false }
					: q,
			);
			resolved = resolved.map((q) =>
				q.target_kind === target.target_kind && q.target_id === target.target_id
					? { ...q, shadow_hidden: false }
					: q,
			);
		} catch (e) {
			showToast(t('admin.reports.unhideFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			unhiding = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) await loadQueue();
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.reports.title')}</title></svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="admin-not-authorized">
			<h1>{t('admin.reports.notAuthorized')}</h1>
			<p class="muted">{t('admin.reports.notAuthorizedHint')}</p>
		</div>
	{:else}
		<header>
			<h1>{t('admin.reports.title')}</h1>
			<p class="muted">{t('admin.reports.subtitle')}</p>
		</header>

		<div class="tabs" role="group" aria-label={t('admin.reports.title')}>
			<button
				type="button"
				class="tab"
				class:active={view === 'pending'}
				aria-pressed={view === 'pending'}
				data-testid="admin-tab-pending"
				onclick={() => showView('pending')}
			>{t('admin.reports.tabPending')}</button>
			<button
				type="button"
				class="tab"
				class:active={view === 'resolved'}
				aria-pressed={view === 'resolved'}
				data-testid="admin-tab-resolved"
				onclick={() => showView('resolved')}
			>{t('admin.reports.tabResolved')}</button>
		</div>

		{#if view === 'resolved'}
			{#if resolvedError}
				<div class="card-elevated empty" role="alert" data-testid="admin-resolved-error">
					<p class="muted">{resolvedError}</p>
					<button type="button" class="btn btn-outline btn-sm" onclick={loadResolved}>
						{t('admin.reports.retry')}
					</button>
				</div>
			{:else if resolvedLoading || !resolvedLoaded}
				<p class="muted">{t('admin.reports.loading')}</p>
			{:else if resolved.length === 0}
				<div class="card-elevated empty" data-testid="admin-resolved-empty">
					<p class="muted">{t('admin.reports.resolvedEmpty')}</p>
				</div>
			{:else}
				<div class="card-elevated">
					<table data-testid="admin-resolved">
						<thead>
							<tr>
								<th>{t('admin.reports.colTarget')}</th>
								<th>{t('admin.reports.colReports')}</th>
								<th>{t('admin.reports.colHeld')}</th>
								<th>{t('admin.reports.colResolved')}</th>
								<th>{t('admin.reports.colReview')}</th>
							</tr>
						</thead>
						<tbody>
							{#each resolved as target (target.target_kind + target.target_id)}
								<tr data-testid="admin-resolved-row">
									<td>
										<span class="kind">{kindLabel(target.target_kind)}</span>
										{#if reportTargetHref(target.target_kind, target.page_id)}
											<a href={reportTargetHref(target.target_kind, target.page_id)} class="target-link"
												>{target.target_id.slice(0, 8)}</a>
										{:else}
											<span class="target-link">{target.target_id.slice(0, 8)}</span>
										{/if}
									</td>
									<td>{target.report_count}</td>
									<td>
										{#if target.held_count > 0}
											<span class="hold-badge" aria-hidden="true">{target.held_count}</span>
											<span class="visually-hidden">{t('admin.reports.heldCount', { count: target.held_count })}</span>
										{:else}
											<span class="muted">0</span>
										{/if}
									</td>
									<td class="muted">{target.last_reviewed_at ? formatRelativeTime(target.last_reviewed_at) : ''}</td>
									<td>
										<button
											type="button"
											class="btn btn-outline btn-sm"
											data-testid="admin-resolved-review"
											onclick={() => openTarget(target)}
										>
											{t('admin.reports.review')}
										</button>
									</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		{:else if queue.length === 0}
			<div class="card-elevated empty" data-testid="admin-queue-empty">
				<p class="muted">{t('admin.reports.empty')}</p>
			</div>
		{:else}
			<div class="card-elevated">
				<table data-testid="admin-queue">
					<thead>
						<tr>
							<th>{t('admin.reports.colTarget')}</th>
							<th>{t('admin.reports.colReports')}</th>
							<th>{t('admin.reports.colReporters')}</th>
							<th>{t('admin.reports.colReasons')}</th>
							<th>{t('admin.reports.colLatest')}</th>
							<th>{t('admin.reports.colReview')}</th>
						</tr>
					</thead>
					<tbody>
						{#each queue as target (target.target_kind + target.target_id)}
							<tr
								class="row"
								data-testid="admin-queue-row"
								onclick={() => openTarget(target)}
							>
								<td>
									<span class="kind">{kindLabel(target.target_kind)}</span>
									{#if reportTargetHref(target.target_kind, target.page_id)}
										<a
											href={reportTargetHref(target.target_kind, target.page_id)}
											class="target-link"
											onclick={(e) => e.stopPropagation()}
										>{target.target_id.slice(0, 8)}</a>
									{:else}
										<span class="target-link">{target.target_id.slice(0, 8)}</span>
									{/if}
									{#if target.shadow_hidden}
										<span class="hidden-badge" data-testid="admin-hidden-badge">{t('admin.reports.hiddenBadge')}</span>
									{/if}
								</td>
								<td>{target.report_count}</td>
								<td>{target.reporter_count}</td>
								<td>
									<span class="reasons">
										{#each Object.entries(target.reasons) as [reason, n] (reason)}
											<span class="chip">{reason} · {n}</span>
										{/each}
									</span>
								</td>
								<td class="muted">{formatRelativeTime(target.latest_at)}</td>
								<td>
									<!-- The row's own onclick is a mouse convenience with no keyboard
									     equivalent, and the only focusable control in the row is the
									     target link — which goes somewhere else entirely (the reported
									     content, not this review panel). Without a real button a
									     keyboard-only moderator could not review or resolve anything. -->
									<button
										type="button"
										class="btn btn-outline btn-sm"
										data-testid="admin-queue-review"
										onclick={(e) => {
											e.stopPropagation();
											openTarget(target);
										}}
									>
										{t('admin.reports.review')}
									</button>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	{/if}
</div>

{#if selected}
	<Modal
		open={!!selected}
		title={t('admin.reports.detailTitle')}
		onclose={closeDetail}
		data-testid="admin-detail-modal"
	>
		<div class="detail-body">
			<div class="detail-head">
				<span class="kind">{kindLabel(selected.target_kind)}</span>
				{#if reportTargetHref(selected.target_kind, selected.page_id)}
					<a href={reportTargetHref(selected.target_kind, selected.page_id)} class="target-link">
						{t('admin.reports.viewTarget')}
					</a>
				{/if}
				{#if selected.shadow_hidden}
					<span class="hidden-badge" data-testid="admin-detail-hidden-badge">{t('admin.reports.hiddenBadge')}</span>
				{/if}
			</div>

			{#if selected.shadow_hidden}
				<div class="hidden-notice" data-testid="admin-hidden-notice">
					<p class="muted">{t('admin.reports.hiddenNotice')}</p>
					<button
						type="button"
						class="btn btn-secondary"
						disabled={unhiding}
						data-testid="admin-unhide"
						onclick={() => (confirmUnhide = true)}
					>{t('admin.reports.unhide')}</button>
				</div>
			{/if}

			{#if detailLoading}
				<p class="muted">…</p>
			{:else}
				<ul class="report-list">
					{#each detail as r (r.id)}
						<li class="report">
							<div class="report-top">
								<span class="reason chip">{r.reason}</span>
								<span class="status status-{r.status}">{statusLabel(r.status)}</span>
								<span class="muted when">{formatRelativeTime(r.created_at)}</span>
								{#if r.legal_hold}
									<span class="hold-badge" data-testid="admin-legal-hold-badge">{t('admin.reports.legalHoldBadge')}</span>
								{/if}
							</div>
							<p class="report-by muted">
								{r.reporter_id
									? t('admin.reports.reportBy', { id: r.reporter_id.slice(0, 8) })
									: t('admin.reports.reporterDeleted')}
							</p>
							<p class="notes">{r.notes || t('admin.reports.noNotes')}</p>
							{#if r.snapshot_body !== null}
								<blockquote class="snapshot" data-testid="admin-report-snapshot">
									<p class="muted">
										{t('admin.reports.snapshotBy', {
											id: (r.snapshot_author_id ?? '').slice(0, 8),
											when: r.snapshot_sent_at ? formatRelativeTime(r.snapshot_sent_at) : ''
										})}
									</p>
									<p>{r.snapshot_body}</p>
								</blockquote>
							{/if}
							<div class="hold-row">
								{#if r.purge_after}
									<span class="muted retention">{t('admin.reports.purgeAfter', { date: formatDate(r.purge_after) })}</span>
								{/if}
								<button
									type="button"
									class="btn btn-outline btn-sm"
									disabled={holdBusy !== null}
									data-testid="admin-legal-hold-toggle"
									onclick={() => (r.legal_hold ? (confirmLiftHold = r) : setHold(r, true))}
								>{t(r.legal_hold ? 'admin.reports.liftHold' : 'admin.reports.placeHold')}</button>
							</div>
						</li>
					{/each}
				</ul>

				{#if hasPending}
					<label class="resolution">
						<span>{t('admin.reports.resolutionLabel')}</span>
						<textarea
							bind:value={resolution}
							rows="2"
							placeholder={t('admin.reports.resolutionPlaceholder')}
							data-testid="admin-resolution-input"
						></textarea>
					</label>

					<div class="actions">
						<button
							type="button"
							class="btn btn-secondary"
							disabled={resolving}
							data-testid="admin-dismiss"
							onclick={() => (confirm = { status: 'dismissed' })}
						>{t('admin.reports.dismiss')}</button>
						<button
							type="button"
							class="btn btn-primary"
							disabled={resolving}
							data-testid="admin-mark-reviewed"
							onclick={() => (confirm = { status: 'reviewed' })}
						>{t('admin.reports.markReviewed')}</button>
					</div>
				{/if}
			{/if}
		</div>
	</Modal>
{/if}

<ConfirmDialog
	open={!!confirm}
	danger={confirm?.status === 'dismissed'}
	title={confirm?.status === 'dismissed'
		? t('admin.reports.confirmDismissTitle')
		: t('admin.reports.confirmReviewedTitle')}
	message={confirm?.status === 'dismissed'
		? t('admin.reports.confirmDismissMessage', { count: selected?.report_count ?? 0 })
		: t('admin.reports.confirmReviewedMessage', { count: selected?.report_count ?? 0 })}
	confirmLabel={confirm?.status === 'dismissed'
		? t('admin.reports.dismiss')
		: t('admin.reports.markReviewed')}
	data-testid="admin-resolve-confirm"
	onconfirm={() => {
		const status = confirm?.status;
		confirm = null;
		if (status) doResolve(status);
	}}
	oncancel={() => (confirm = null)}
/>

<ConfirmDialog
	open={!!confirmLiftHold}
	danger
	title={t('admin.reports.confirmLiftHoldTitle')}
	message={t('admin.reports.confirmLiftHoldMessage')}
	confirmLabel={t('admin.reports.liftHold')}
	data-testid="admin-lift-hold-confirm"
	onconfirm={() => {
		const report = confirmLiftHold;
		confirmLiftHold = null;
		if (report) setHold(report, false);
	}}
	oncancel={() => (confirmLiftHold = null)}
/>

<ConfirmDialog
	open={confirmUnhide}
	title={t('admin.reports.confirmUnhideTitle')}
	message={t('admin.reports.confirmUnhideMessage')}
	confirmLabel={t('admin.reports.unhide')}
	data-testid="admin-unhide-confirm"
	onconfirm={() => {
		confirmUnhide = false;
		doUnhide();
	}}
	oncancel={() => (confirmUnhide = false)}
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	header h1,
	.not-authorized h1 {
		margin: 0 0 0.25rem;
		font-size: 1.4rem;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.not-authorized,
	.empty {
		padding: var(--space-xl);
		text-align: center;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	th {
		text-align: start;
		padding: var(--space-sm);
		color: var(--color-text-secondary);
		font-weight: 600;
		border-bottom: 1px solid var(--color-border);
	}
	td {
		padding: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	.row {
		cursor: pointer;
	}
	.row:hover {
		background: color-mix(in srgb, var(--color-text) 6%, transparent);
	}
	.kind {
		display: inline-block;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--color-text-secondary);
		margin-inline-end: 0.4rem;
	}
	.target-link {
		font-family: var(--font-mono);
		color: var(--color-primary);
	}
	.reasons,
	.report-top {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		align-items: center;
	}
	.chip {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--chip-bg);
		color: var(--chip-fg);
		font-size: 0.78rem;
	}
	.detail-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.detail-head {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.hidden-badge {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		background: var(--color-warning-strong);
		color: #fff;
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		margin-inline-start: 0.4rem;
	}
	.tabs {
		display: flex;
		gap: 0.4rem;
		border-bottom: 1px solid var(--color-border);
		overflow-x: auto;
	}
	.tab {
		background: none;
		border: none;
		padding: 0.6rem 0.25rem;
		margin-inline-end: 1rem;
		font: inherit;
		font-weight: 600;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		white-space: nowrap;
	}
	.tab:hover {
		color: var(--color-text);
	}
	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}
	.hold-badge {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		border: 1px solid var(--color-primary);
		color: var(--color-primary);
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.hold-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		margin-top: 0.25rem;
	}
	.retention {
		font-size: 0.78rem;
	}
	.hidden-notice {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
		padding: var(--space-sm);
		border: 1px solid var(--color-warning);
		border-radius: var(--radius-sm);
		background: var(--color-warning-light);
	}
	.hidden-notice p {
		margin: 0;
		font-size: 0.84rem;
	}
	.report-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		max-height: 40vh;
		overflow-y: auto;
	}
	.report {
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.status {
		font-size: 0.74rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.status-pending {
		color: var(--color-warning-text);
	}
	.report-by,
	.when {
		font-size: 0.78rem;
	}
	.snapshot {
		margin: 0.4rem 0 0;
		padding: 0.4rem 0.7rem;
		border-inline-start: 3px solid var(--color-border);
		background: var(--color-bg-secondary);
		white-space: pre-wrap;
	}
	.snapshot p {
		margin: 0;
	}
	.notes {
		margin: 0;
		font-size: 0.88rem;
	}
	.resolution {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 0.84rem;
	}
	.resolution textarea {
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		font: inherit;
		resize: vertical;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
