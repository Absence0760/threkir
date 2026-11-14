<script lang="ts">
	// Site-admin review of club verification requests (issue #1190 § 2,
	// decisions § 2398). Every RPC hard-denies a non-admin at the database;
	// amIAdmin only picks the page chrome.
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import {
		amIAdmin,
		approveClubVerification,
		fetchClubVerificationAudit,
		fetchClubVerificationQueue,
		rejectClubVerification,
		revokeClubVerification,
		type ClubVerificationAuditRow,
		type ClubVerificationQueueRow,
		type ClubVerificationQueueView,
	} from '#lib/core/data.ts';
	import { m as t, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import Modal from '#lib/components/Modal.svelte';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	type Action = { kind: 'approve' | 'reject' | 'revoke'; row: ClubVerificationQueueRow };

	let isAdmin = $state<boolean | null>(null);
	let loading = $state(true);
	let view = $state<ClubVerificationQueueView>('pending');
	let rows = $state<ClubVerificationQueueRow[]>([]);
	let loadError = $state<string | null>(null);

	let action = $state<Action | null>(null);
	let text = $state('');
	let actionError = $state<string | null>(null);
	let acting = $state(false);

	let historyFor = $state<ClubVerificationQueueRow | null>(null);
	let history = $state<ClubVerificationAuditRow[]>([]);
	let historyError = $state<string | null>(null);

	const views: ClubVerificationQueueView[] = ['pending', 'verified', 'closed'];
	const viewLabel: Record<ClubVerificationQueueView, MessageKey> = {
		pending: 'admin.clubVerification.tabPending',
		verified: 'admin.clubVerification.tabVerified',
		closed: 'admin.clubVerification.tabClosed',
	};

	function fmtDate(iso: string | null): string {
		if (!iso) return '';
		return new Intl.DateTimeFormat(currentLocale(), { dateStyle: 'medium' }).format(new Date(iso));
	}

	function methodLabel(method: string | null): string {
		switch (method) {
			case 'dns_txt':
				return t('clubVerification.method.dns_txt');
			case 'well_known':
				return t('clubVerification.method.well_known');
			case 'email':
				return t('clubVerification.method.email');
			case 'manual':
				return t('clubVerification.method.manual');
			default:
				return '';
		}
	}

	function auditLabel(a: string): string {
		return t(`admin.clubVerification.audit.${a}` as MessageKey);
	}

	async function load() {
		loadError = null;
		try {
			rows = await fetchClubVerificationQueue(view);
		} catch (e) {
			rows = [];
			loadError = t('admin.clubVerification.loadFailed', {
				error: errorCopy(e, t, 'club verification queue failed'),
			});
		}
	}

	async function selectView(next: ClubVerificationQueueView) {
		view = next;
		await load();
	}

	function openAction(kind: Action['kind'], row: ClubVerificationQueueRow) {
		action = { kind, row };
		text = '';
		actionError = null;
	}

	async function runAction() {
		if (!action || acting) return;
		const note = text.trim();
		if (action.kind !== 'approve' && note === '') {
			actionError = t('admin.clubVerification.reasonRequired');
			return;
		}
		if (action.kind === 'approve' && !action.row.proof_verified_at && note === '') {
			actionError = t('admin.clubVerification.approveNoteRequired');
			return;
		}
		acting = true;
		actionError = null;
		try {
			if (action.kind === 'approve') await approveClubVerification(action.row.request_id!, note || null);
			else if (action.kind === 'reject') await rejectClubVerification(action.row.request_id!, note);
			else await revokeClubVerification(action.row.club_id, note);
			action = null;
			await load();
		} catch (e) {
			actionError = t('admin.clubVerification.actionFailed', {
				error: errorCopy(e, t, 'club verification review failed'),
			});
		} finally {
			acting = false;
		}
	}

	async function openHistory(row: ClubVerificationQueueRow) {
		historyFor = row;
		history = [];
		historyError = null;
		try {
			history = await fetchClubVerificationAudit(row.club_id);
		} catch (e) {
			historyError = errorCopy(e, t, 'club verification history failed');
			showToast(historyError, 'error');
		}
	}

	const actionTitle = $derived(
		action === null
			? ''
			: action.kind === 'approve'
				? t('admin.clubVerification.approveTitle', { club: action.row.club_name })
				: action.kind === 'reject'
					? t('admin.clubVerification.rejectTitle', { club: action.row.club_name })
					: t('admin.clubVerification.revokeTitle', { club: action.row.club_name }),
	);
	const actionBody = $derived(
		action === null
			? ''
			: action.kind === 'approve'
				? t('admin.clubVerification.approveBody')
				: action.kind === 'reject'
					? t('admin.clubVerification.rejectBody')
					: t('admin.clubVerification.revokeBody'),
	);

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) await load();
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.clubVerification.title')}</title></svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="club-verification-not-authorized">
			<PageHeader flush title={t('admin.clubVerification.notAuthorized')} subtitle={t('admin.clubVerification.notAuthorizedHint')} />
		</div>
	{:else}
		<PageHeader flush title={t('admin.clubVerification.title')} subtitle={t('admin.clubVerification.subtitle')} />

		<div class="tabs" role="group" aria-label={t('admin.clubVerification.title')}>
			{#each views as v (v)}
				<button
					type="button"
					class="btn-secondary btn-sm"
					class:active={view === v}
					aria-pressed={view === v}
					onclick={() => selectView(v)}
					data-testid={`club-verification-tab-${v}`}
				>
					{t(viewLabel[v])}
				</button>
			{/each}
		</div>

		{#if loadError}
			<EmptyState icon="error" tone="danger" title={loadError} role="alert" />
		{:else if rows.length === 0}
			<EmptyState icon="verified" title={t('admin.clubVerification.empty')} data-testid="club-verification-empty" />
		{:else}
			<ul class="request-queue">
				{#each rows as row (row.request_id ?? row.club_id)}
					<li class="card-elevated" data-testid="club-verification-row" data-club={row.club_slug}>
						<div class="row-head">
							<a href={`/clubs/${row.club_slug}`}><strong>{row.club_name}</strong></a>
							<span class="muted">{t('admin.clubVerification.members', { n: row.member_count })}</span>
						</div>
						<dl>
							{#if row.organisation}
								<dt>{t('admin.clubVerification.organisation')}</dt>
								<dd>{row.organisation}</dd>
							{/if}
							{#if row.domain}
								<dt>{t('admin.clubVerification.domain')}</dt>
								<dd><code>{row.domain}</code></dd>
							{/if}
							{#if row.club_website_url}
								<dt>{t('admin.clubVerification.website')}</dt>
								<dd>
									<a href={row.club_website_url} target="_blank" rel="noopener noreferrer nofollow">{row.club_website_url}</a>
								</dd>
							{/if}
							{#if row.owner_name}
								<dt>{t('admin.clubVerification.owner')}</dt>
								<dd>{row.owner_name}</dd>
							{/if}
							{#if row.request_id}
								<dt>{t('admin.clubVerification.proof')}</dt>
								<dd data-testid="club-verification-row-proof">
									{row.proof_verified_at
										? `${methodLabel(row.proof_method)}${row.proof_detail ? ` · ${row.proof_detail}` : ''}`
										: t('admin.clubVerification.proofNone')}
								</dd>
							{/if}
							{#if row.note}
								<dt>{t('admin.clubVerification.note')}</dt>
								<dd>{row.note}</dd>
							{/if}
							{#if row.decision_reason}
								<dt>{t('admin.clubVerification.noteLabel')}</dt>
								<dd>{row.decision_reason}</dd>
							{/if}
							{#if row.close_reason}
								<dt>{t('admin.clubVerification.reasonLabel')}</dt>
								<dd>{row.close_reason}</dd>
							{/if}
						</dl>
						<p class="muted meta">
							{#if row.created_at}{t('admin.clubVerification.submitted', { date: fmtDate(row.created_at) })}{/if}
							{#if row.last_checked_at && view === 'verified'}
								· {t('admin.clubVerification.lastChecked', { date: fmtDate(row.last_checked_at) })}
							{/if}
							{#if row.check_failures > 0}
								· {t('admin.clubVerification.failures', { n: row.check_failures })}
							{/if}
							{#if view === 'verified' && !row.request_id}
								{t('admin.clubVerification.legacy')}
							{/if}
						</p>
						{#if view === 'pending'}
							<p class="hint">{t('admin.clubVerification.lookalikeHint')}</p>
						{/if}
						<div class="actions">
							{#if view === 'pending'}
								<button class="btn-primary btn-sm" type="button" onclick={() => openAction('approve', row)} data-testid="club-verification-approve">
									{t('admin.clubVerification.approve')}
								</button>
								<button class="btn-secondary btn-sm" type="button" onclick={() => openAction('reject', row)} data-testid="club-verification-reject">
									{t('admin.clubVerification.reject')}
								</button>
							{:else if view === 'verified'}
								<button class="btn-danger btn-sm" type="button" onclick={() => openAction('revoke', row)} data-testid="club-verification-revoke">
									{t('admin.clubVerification.revoke')}
								</button>
							{/if}
							<button class="btn-secondary btn-sm" type="button" onclick={() => openHistory(row)} data-testid="club-verification-history">
								{t('admin.clubVerification.history')}
							</button>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<Modal open={action !== null} onclose={() => (action = null)} title={actionTitle} narrow data-testid="club-verification-action-dialog">
	<form
		class="editor-form"
		onsubmit={(e) => {
			e.preventDefault();
			void runAction();
		}}
	>
		<p>{actionBody}</p>
		{#if action?.kind === 'approve' && !action.row.proof_verified_at}
			<p class="hint">{t('admin.clubVerification.proofNone')}</p>
		{/if}
		<label for="club-verification-action-text">
			{action?.kind === 'approve' ? t('admin.clubVerification.noteLabel') : t('admin.clubVerification.reasonLabel')}
		</label>
		<textarea id="club-verification-action-text" rows="3" maxlength="500" bind:value={text} data-testid="club-verification-action-text"></textarea>
		{#if actionError}
			<p class="error" role="alert">{actionError}</p>
		{/if}
		<div class="modal-actions">
			<button class="btn-secondary" type="button" onclick={() => (action = null)}>{t('common.cancel')}</button>
			<button
				class={action?.kind === 'approve' ? 'btn-primary' : 'btn-danger'}
				type="submit"
				disabled={acting}
				data-testid="club-verification-action-confirm"
			>
				{action?.kind === 'approve'
					? t('admin.clubVerification.approve')
					: action?.kind === 'reject'
						? t('admin.clubVerification.reject')
						: t('admin.clubVerification.revoke')}
			</button>
		</div>
	</form>
</Modal>

<Modal
	open={historyFor !== null}
	onclose={() => (historyFor = null)}
	title={historyFor ? t('admin.clubVerification.historyTitle', { club: historyFor.club_name }) : ''}
	data-testid="club-verification-history-dialog"
>
	{#if historyError}
		<p class="error" role="alert">{historyError}</p>
	{:else if history.length === 0}
		<p class="muted">{t('admin.clubVerification.empty')}</p>
	{:else}
		<ol class="history">
			{#each history as h (h.id)}
				<li>
					<strong>{auditLabel(h.action)}</strong>
					<span class="muted">· {h.actor_name ?? t('admin.clubVerification.system')} · {fmtDate(h.created_at)}</span>
					{#if h.detail}<div class="detail">{h.detail}</div>{/if}
				</li>
			{/each}
		</ol>
	{/if}
</Modal>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
		max-width: 64rem;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.not-authorized {
		padding: var(--space-xl);
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
	.request-queue {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.request-queue li {
		padding: var(--space-lg);
	}
	.row-head {
		display: flex;
		gap: var(--space-sm);
		align-items: baseline;
		flex-wrap: wrap;
		margin-bottom: var(--space-sm);
	}
	dl {
		display: grid;
		grid-template-columns: max-content minmax(0, 1fr);
		gap: 0.3rem 0.9rem;
		margin: 0;
	}
	dt {
		color: var(--color-text-secondary);
	}
	dd {
		margin: 0;
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
	.history {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.detail {
		font-size: 0.85rem;
		overflow-wrap: anywhere;
	}
</style>
