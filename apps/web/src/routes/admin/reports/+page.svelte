<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import {
		amIAdmin,
		fetchPendingReports,
		fetchReportsForTarget,
		resolveTargetReports,
		adminUnhideTarget,
		fetchResolvedReports,
		setReportLegalHold,
		resolveOrganiserDispute,
		fetchOrganiserDisputeHistory,
		fetchAdminParkCourse,
		fetchAdminReportConversation,
		type ReportConversation,
		adminSetParkCourseStatus,
		fetchParkCourseStatusHistory,
		fetchParkNpsAlerts,
		type AdminParkCourse,
		type ParkCourseStatusHistoryEntry,
		type OrganiserDisputeHistoryEntry,
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
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { reportTargetHref, reportTargetLabelKey } from './report_target';
	import {
		DISPUTE_DEADLINE_DEFAULT_DAYS,
		DISPUTE_DEADLINE_MAX_DAYS,
		DISPUTE_DEADLINE_MIN_DAYS,
		deadlineDaysOrNull,
		deadlinePassed,
	} from '#lib/social/organiser_dispute.ts';
	import type { OrganiserDisputeTargetKind } from '#lib/types.ts';
	import { courseReportMailto, landManagerDueAt, rightsHolderDueAt } from '#lib/parks/course_report.ts';
	import { regionSlug } from '#lib/parks/park_courses.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';

	type QueueTarget = Pick<
		PendingReportTarget,
		'target_kind' | 'target_id' | 'page_id' | 'shadow_hidden' | 'report_count'
	> &
		Partial<
			Pick<
				PendingReportTarget,
				| 'organiser_dispute'
				| 'organiser_clubs'
				| 'rename_deadline_at'
				| 'land_manager_since'
				| 'rights_holder_since'
			>
		>;

	type DisputeAction = 'takedown' | 'rename_notice' | 'dismiss';
	const DISPUTE_KINDS: readonly string[] = ['club', 'route', 'training_plan', 'gym_routine', 'challenge', 'race_listing'];

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
	let hasPending = $derived(detail.some((r) => r.status === 'pending' && r.reason !== 'organiser_dispute'));
	let hasPendingDispute = $derived(
		detail.some((r) => r.status === 'pending' && r.reason === 'organiser_dispute') &&
			!!selected &&
			DISPUTE_KINDS.includes(selected.target_kind),
	);
	let disputeNote = $state('');
	let deadlineDays = $state<string | number | null>(DISPUTE_DEADLINE_DEFAULT_DAYS);
	let disputeBusy = $state(false);
	let confirmDispute = $state<DisputeAction | null>(null);
	let history = $state<OrganiserDisputeHistoryEntry[]>([]);
	const deadlineValid = $derived(deadlineDaysOrNull(deadlineDays) !== null);

	// Park course reports (decisions § 2449): a report never closes a course;
	// the admin does, here, with the note the course page shows.
	let course = $state<AdminParkCourse | null>(null);
	// The audience a reported message went to: a 1:1 thread or a group, with
	// the group's name and size (group_messages.md § 6). Null when unknown.
	let conversation = $state<ReportConversation | null>(null);
	let conversationFailed = $state(false);
	let courseHistory = $state<ParkCourseStatusHistoryEntry[]>([]);
	let courseNote = $state('');
	let courseBusy = $state(false);
	let confirmCourse = $state<'closed' | 'open' | null>(null);
	const CATALOGUE_NOTE = 'Removed from the park catalogue.';
	const courseHref = $derived(
		course?.park ? `/parks/${regionSlug(course.park.region_code)}/${course.park.slug}/${course.slug}` : null,
	);
	const pendingLandManager = $derived(
		detail
			.filter((r) => r.status === 'pending' && r.reason === 'land_manager_request')
			.map((r) => r.created_at)
			.sort()[0] ?? null,
	);
	const pendingRightsHolder = $derived(
		detail
			.filter((r) => r.status === 'pending' && r.reason === 'rights_holder_request')
			.map((r) => r.created_at)
			.sort()[0] ?? null,
	);

	const COURSE_REASON_LABELS: Record<string, MessageKey> = {
		course_hazard: 'admin.reports.reason.courseHazard',
		course_closure: 'admin.reports.reason.courseClosure',
		course_off_trail: 'admin.reports.reason.courseOffTrail',
		land_manager_request: 'admin.reports.reason.landManagerRequest',
		rights_holder_request: 'admin.reports.reason.rightsHolderRequest',
	};

	function reasonLabel(reason: string): string {
		const key = COURSE_REASON_LABELS[reason];
		return key ? t(key) : reason;
	}

	function landManagerDue(receivedIso: string): { text: string; overdue: boolean } {
		const due = landManagerDueAt(receivedIso);
		const overdue = due.getTime() < Date.now();
		const date = formatDate(due.toISOString());
		return {
			text: overdue ? t('admin.reports.course.overdue', { date }) : t('admin.reports.course.dueOn', { date }),
			overdue,
		};
	}

	function rightsHolderDue(receivedIso: string): { text: string; overdue: boolean } {
		const due = rightsHolderDueAt(receivedIso);
		const overdue = due.getTime() < Date.now();
		const date = formatDate(due.toISOString());
		return {
			text: overdue ? t('admin.reports.course.overdue', { date }) : t('admin.reports.course.acknowledgeBy', { date }),
			overdue,
		};
	}

	async function loadCourse(courseId: string) {
		course = await fetchAdminParkCourse(courseId);
		courseHistory = course ? await fetchParkCourseStatusHistory(courseId) : [];
	}

	async function doCourseStatus(status: 'closed' | 'open') {
		if (!selected || !course || courseBusy) return;
		courseBusy = true;
		const target = selected;
		try {
			await adminSetParkCourseStatus(course.id, status, courseNote.trim() || null);
			showToast(t(status === 'closed' ? 'admin.reports.course.doneClose' : 'admin.reports.course.doneReopen'), 'success');
			courseNote = '';
			await loadCourse(course.id);
			detail = await fetchReportsForTarget(target.target_kind, target.target_id);
			await loadQueue();
			if (resolvedLoaded) await loadResolved();
		} catch (e) {
			showToast(t('admin.reports.course.failed', { error: errorCopy(e, t, 'admin.reports.course.failed') }), 'error');
		} finally {
			courseBusy = false;
		}
	}

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
			showToast(t('admin.reports.loadFailed', { error: errorCopy(e, t, 'admin.reports.loadFailed') }), 'error');
		}
	}

	async function loadResolved() {
		resolvedLoading = true;
		resolvedError = null;
		try {
			resolved = await fetchResolvedReports();
			resolvedLoaded = true;
		} catch (e) {
			resolvedError = t('admin.reports.resolvedLoadFailed', { error: errorCopy(e, t, 'admin.reports.resolvedLoadFailed') });
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
			showToast(t('admin.reports.holdFailed', { error: errorCopy(e, t, 'admin.reports.holdFailed') }), 'error');
		} finally {
			holdBusy = null;
		}
	}

	async function openTarget(target: QueueTarget) {
		selected = target;
		resolution = '';
		disputeNote = '';
		deadlineDays = DISPUTE_DEADLINE_DEFAULT_DAYS;
		history = [];
		course = null;
		courseHistory = [];
		courseNote = '';
		conversation = null;
		conversationFailed = false;
		detail = [];
		detailLoading = true;
		try {
			detail = await fetchReportsForTarget(target.target_kind, target.target_id);
			if (target.target_kind === 'park_course') await loadCourse(target.target_id);
			if (target.target_kind === 'direct_message') {
				// Auxiliary: a failed lookup says so and leaves the reports and
				// the actions on them standing (conventions.md § Layered resilience).
				try {
					conversation = await fetchAdminReportConversation(target.target_id);
				} catch (e) {
					console.warn('admin report conversation lookup failed', e);
					conversationFailed = true;
				}
			}
			if (detail.some((r) => r.reason === 'organiser_dispute') && DISPUTE_KINDS.includes(target.target_kind)) {
				history = await fetchOrganiserDisputeHistory(
					target.target_kind as OrganiserDisputeTargetKind,
					target.target_id,
				);
			}
		} catch (e) {
			showToast(t('admin.reports.detailFailed', { error: errorCopy(e, t, 'admin.reports.detailFailed') }), 'error');
		} finally {
			detailLoading = false;
		}
	}

	function closeDetail() {
		selected = null;
		conversation = null;
		detail = [];
		course = null;
		courseHistory = [];
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
			showToast(t('admin.reports.resolveFailed', { error: errorCopy(e, t, 'admin.reports.resolveFailed') }), 'error');
		} finally {
			resolving = false;
		}
	}

	async function doDisputeAction(action: DisputeAction) {
		if (!selected || disputeBusy) return;
		const days = deadlineDaysOrNull(deadlineDays);
		if (action === 'rename_notice' && days === null) return;
		disputeBusy = true;
		const target = selected;
		try {
			await resolveOrganiserDispute({
				targetKind: target.target_kind as OrganiserDisputeTargetKind,
				targetId: target.target_id,
				action,
				note: disputeNote.trim() || null,
				deadlineDays: days,
			});
			const key =
				action === 'takedown'
					? 'admin.reports.dispute.doneHide'
					: action === 'rename_notice'
						? 'admin.reports.dispute.doneRename'
						: 'admin.reports.dispute.doneDismiss';
			showToast(t(key), 'success');
			closeDetail();
			await loadQueue();
			if (resolvedLoaded) await loadResolved();
		} catch (e) {
			showToast(
				t('admin.reports.dispute.failed', { error: errorCopy(e, t, 'admin.reports.dispute.failed') }),
				'error',
			);
		} finally {
			disputeBusy = false;
		}
	}

	function historyActionLabel(action: OrganiserDisputeHistoryEntry['action']): string {
		switch (action) {
			case 'filed':
				return t('admin.reports.dispute.historyFiled');
			case 'takedown':
				return t('admin.reports.dispute.historyHide');
			case 'rename_notice':
				return t('admin.reports.dispute.historyRename');
			case 'dismiss':
				return t('admin.reports.dispute.historyDismiss');
			case 'unhide':
				return t('admin.reports.dispute.historyUnhide');
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
			showToast(t('admin.reports.unhideFailed', { error: errorCopy(e, t, 'admin.reports.unhideFailed') }), 'error');
		} finally {
			unhiding = false;
		}
	}

	// The NPS closures sweep's flags live on their own page; the count here
	// is how an admin working this queue learns some are waiting. A failed
	// read leaves the link off rather than the queue.
	let npsPending = $state(0);
	async function loadNpsPending() {
		try {
			npsPending = (await fetchParkNpsAlerts('pending')).length;
		} catch (e) {
			console.warn('park alerts count failed', e);
		}
	}

	onMount(async () => {
		await auth.ready();
		isAdmin = await amIAdmin();
		if (isAdmin) {
			void loadNpsPending();
			await loadQueue();
		}
		loading = false;
	});
</script>

<svelte:head><title>{t('admin.reports.title')}</title></svelte:head>

<div class="page">
	{#if loading}
		<p class="muted">…</p>
	{:else if !isAdmin}
		<div class="card-elevated not-authorized" data-testid="admin-not-authorized">
			<PageHeader flush title={t('admin.reports.notAuthorized')} subtitle={t('admin.reports.notAuthorizedHint')} />
		</div>
	{:else}
		<PageHeader flush title={t('admin.reports.title')} subtitle={t('admin.reports.subtitle')}>
			{#if npsPending > 0}
				<p class="nps-pending">
					<a href="/admin/park-alerts" data-testid="admin-park-alerts-link">
						{t('admin.parkAlerts.pendingLink', { count: npsPending })}
					</a>
				</p>
			{/if}
		</PageHeader>

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
				<EmptyState
					icon="error"
					tone="danger"
					title={resolvedError}
					role="alert"
					data-testid="admin-resolved-error"
				>
					{#snippet actions()}
						<button type="button" class="btn btn-outline" onclick={loadResolved}>
							{t('admin.reports.retry')}
						</button>
					{/snippet}
				</EmptyState>
			{:else if resolvedLoading || !resolvedLoaded}
				<p class="muted">{t('admin.reports.loading')}</p>
			{:else if resolved.length === 0}
				<EmptyState icon="inbox" title={t('admin.reports.resolvedEmpty')} data-testid="admin-resolved-empty" />
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
			<EmptyState icon="check_circle" title={t('admin.reports.empty')} data-testid="admin-queue-empty" />
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
									{#if target.land_manager_since}
										{@const due = landManagerDue(target.land_manager_since)}
										<div class="dispute-line" data-testid="admin-land-manager-row">
											<span class="dispute-badge">{t('admin.reports.course.landManagerBadge')}</span>
											<span class="muted">{t('admin.reports.course.receivedAgo', { when: formatRelativeTime(target.land_manager_since) })}</span>
											<span class="muted deadline" class:overdue={due.overdue} data-testid="admin-land-manager-due">{due.text}</span>
										</div>
									{/if}
									{#if target.rights_holder_since}
										{@const due = rightsHolderDue(target.rights_holder_since)}
										<div class="dispute-line" data-testid="admin-rights-holder-row">
											<span class="dispute-badge">{t('admin.reports.course.rightsHolderBadge')}</span>
											<span class="muted">{t('admin.reports.course.receivedAgo', { when: formatRelativeTime(target.rights_holder_since) })}</span>
											<span class="muted deadline" class:overdue={due.overdue} data-testid="admin-rights-holder-due">{due.text}</span>
										</div>
									{/if}
									{#if target.organiser_dispute}
										<div class="dispute-line" data-testid="admin-dispute-row">
											<span class="dispute-badge">{t('admin.reports.dispute.badge')}</span>
											{#each target.organiser_clubs as c (c.id)}
												<span class="dispute-club">
													{c.name}{#if c.is_verified}<span class="material-symbols verified" aria-label={t('admin.reports.dispute.verified')}>verified</span>{/if}
												</span>
											{/each}
											{#if target.rename_deadline_at}
												<span class="muted deadline" class:overdue={deadlinePassed(target.rename_deadline_at)}>
													{deadlinePassed(target.rename_deadline_at)
														? t('admin.reports.dispute.deadlinePassed', { date: formatDate(target.rename_deadline_at) })
														: t('admin.reports.dispute.deadlineOn', { date: formatDate(target.rename_deadline_at) })}
												</span>
											{/if}
										</div>
									{/if}
								</td>
								<td>{target.report_count}</td>
								<td>{target.reporter_count}</td>
								<td>
									<span class="reasons">
										{#each Object.entries(target.reasons) as [reason, n] (reason)}
											<span class="chip">{reasonLabel(reason)} · {n}</span>
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
			{#if selected.target_kind === 'direct_message' && !detailLoading}
				<p class="muted" data-testid="admin-report-conversation">
					{conversationFailed
						? t('admin.reports.conversationFailed')
						: conversation === null
						? t('admin.reports.conversationGone')
						: conversation.kind === 'group'
							? t('admin.reports.conversationGroup', {
									title: conversation.title ?? '',
									count: conversation.memberCount,
								})
							: t('admin.reports.conversationDirect')}
				</p>
			{/if}

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
								<span class="reason chip">{reasonLabel(r.reason)}</span>
								<span class="status status-{r.status}">{statusLabel(r.status)}</span>
								<span class="muted when">{formatRelativeTime(r.created_at)}</span>
								{#if r.legal_hold}
									<span class="hold-badge" data-testid="admin-legal-hold-badge">{t('admin.reports.legalHoldBadge')}</span>
								{/if}
							</div>
							<p class="report-by muted">
								{r.reporter_id
									? t('admin.reports.reportBy', { id: r.reporter_id.slice(0, 8) })
									: r.signed_out
										? t('admin.reports.course.signedOut')
										: t('admin.reports.reporterDeleted')}
							</p>
							{#if r.contact_email}
								<p class="report-by" data-testid="admin-report-contact">
									<a href={courseReportMailto(r.contact_email)}>{t('admin.reports.course.contact', { email: r.contact_email })}</a>
								</p>
							{/if}
							{#if r.organiser_club}
								<p class="report-by" data-testid="admin-report-organiser">
									{t('admin.reports.dispute.filedFor', { club: r.organiser_club.name })}
									{#if r.organiser_club.is_verified}
										<span class="material-symbols verified" aria-label={t('admin.reports.dispute.verified')}>verified</span>
									{:else}
										<span class="muted">{t('admin.reports.dispute.noLongerVerified')}</span>
									{/if}
								</p>
							{/if}
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
									{#if r.snapshot_original_body !== null}
										<p class="muted">{t('admin.reports.snapshotOriginal')}</p>
										<p data-testid="admin-report-snapshot-original">{r.snapshot_original_body}</p>
									{/if}
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

				{#if selected.target_kind === 'park_course'}
					<section class="dispute-panel" data-testid="admin-course-panel">
						<h3>{t('admin.reports.course.panelTitle')}</h3>
						{#if !course}
							<p class="muted">{t('admin.reports.course.missing')}</p>
						{:else}
							<p>
								<strong>{course.name}</strong>{#if course.park}&nbsp;·&nbsp;{course.park.name}{/if}
								{#if courseHref}<a href={courseHref} class="target-link">{t('admin.reports.course.viewCourse')}</a>{/if}
							</p>
							<p data-testid="admin-course-status">
								{course.status === 'closed'
									? t('parks.statusClosed')
									: course.status === 'seasonal'
										? t('parks.statusSeasonal')
										: t('parks.statusOpen')}{#if course.status_note}: {course.status_note}{/if}
							</p>
							<p class="muted">{t('admin.reports.course.panelHint')}</p>
							{#if pendingLandManager}
								{@const due = landManagerDue(pendingLandManager)}
								<p class="deadline" class:overdue={due.overdue}>{due.text}</p>
							{/if}
							{#if pendingRightsHolder}
								{@const due = rightsHolderDue(pendingRightsHolder)}
								<p class="muted" data-testid="admin-rights-holder-hint">{t('admin.reports.course.rightsHolderHint')}</p>
								<p class="deadline" class:overdue={due.overdue} data-testid="admin-rights-holder-panel-due">{due.text}</p>
							{/if}
							{#if detail.some((r) => r.contact_email)}
								<p class="muted">{t('admin.reports.course.replyHint')}</p>
							{/if}
							{#if course.status === 'closed' && course.status_note === CATALOGUE_NOTE}
								<p class="muted">{t('admin.reports.course.catalogueClosed')}</p>
							{:else}
								<label class="resolution">
									<span>{course.status === 'closed' ? t('admin.reports.course.reopenNoteLabel') : t('admin.reports.course.noteLabel')}</span>
									<textarea
										bind:value={courseNote}
										rows="2"
										maxlength="500"
										placeholder={course.status === 'closed' ? '' : t('admin.reports.course.notePlaceholder')}
										data-testid="admin-course-note"
									></textarea>
								</label>
								<div class="actions">
									{#if course.status === 'closed'}
										<button
											type="button"
											class="btn btn-secondary"
											disabled={courseBusy}
											data-testid="admin-course-reopen"
											onclick={() => (confirmCourse = 'open')}
										>{t('admin.reports.course.reopen')}</button>
									{:else}
										<button
											type="button"
											class="btn btn-danger"
											disabled={courseBusy || courseNote.trim().length === 0 || courseNote.trim() === CATALOGUE_NOTE}
											data-testid="admin-course-close"
											onclick={() => (confirmCourse = 'closed')}
										>{t('admin.reports.course.close')}</button>
									{/if}
								</div>
							{/if}
							{#if courseHistory.length > 0}
								<h4>{t('admin.reports.course.historyTitle')}</h4>
								<ul class="history" data-testid="admin-course-history">
									{#each courseHistory as h (h.id)}
										<li>
											<strong>{h.action === 'close' ? t('admin.reports.course.historyClose') : t('admin.reports.course.historyReopen')}</strong>
											<span class="muted">· {formatRelativeTime(h.created_at)}</span>
											{#if h.note}<p class="notes">{h.note}</p>{/if}
										</li>
									{/each}
								</ul>
							{/if}
						{/if}
					</section>
				{/if}

				{#if hasPendingDispute}
					<section class="dispute-panel" data-testid="admin-dispute-panel">
						<h3>{t('admin.reports.dispute.panelTitle')}</h3>
						<p class="muted">{t('admin.reports.dispute.panelHint')}</p>
						{#if selected.rename_deadline_at}
							<p class="deadline" class:overdue={deadlinePassed(selected.rename_deadline_at)}>
								{deadlinePassed(selected.rename_deadline_at)
									? t('admin.reports.dispute.deadlinePassed', { date: formatDate(selected.rename_deadline_at) })
									: t('admin.reports.dispute.deadlineOn', { date: formatDate(selected.rename_deadline_at) })}
							</p>
						{/if}
						<label class="resolution">
							<span>{t('admin.reports.dispute.noteLabel')}</span>
							<textarea
								bind:value={disputeNote}
								rows="2"
								maxlength="1000"
								placeholder={t('admin.reports.dispute.notePlaceholder')}
								data-testid="admin-dispute-note"
							></textarea>
						</label>
						<label class="deadline-field">
							<span>{t('admin.reports.dispute.deadlineLabel')}</span>
							<input
								type="number"
								inputmode="numeric"
								min={DISPUTE_DEADLINE_MIN_DAYS}
								max={DISPUTE_DEADLINE_MAX_DAYS}
								step="1"
								bind:value={deadlineDays}
								aria-invalid={!deadlineValid}
								data-testid="admin-dispute-deadline"
							/>
						</label>
						<div class="actions">
							<button
								type="button"
								class="btn btn-secondary"
								disabled={disputeBusy}
								data-testid="admin-dispute-dismiss"
								onclick={() => (confirmDispute = 'dismiss')}
							>{t('admin.reports.dispute.dismiss')}</button>
							<button
								type="button"
								class="btn btn-secondary"
								disabled={disputeBusy || !deadlineValid}
								data-testid="admin-dispute-rename"
								onclick={() => (confirmDispute = 'rename_notice')}
							>{t('admin.reports.dispute.rename')}</button>
							<button
								type="button"
								class="btn btn-primary"
								disabled={disputeBusy}
								data-testid="admin-dispute-hide"
								onclick={() => (confirmDispute = 'takedown')}
							>{t('admin.reports.dispute.hide')}</button>
						</div>
						{#if history.length > 0}
							<h4>{t('admin.reports.dispute.historyTitle')}</h4>
							<ul class="history" data-testid="admin-dispute-history">
								{#each history as h (h.id)}
									<li>
										<strong>{historyActionLabel(h.action)}</strong>
										<span class="muted">· {h.organiser_club_name} · {formatRelativeTime(h.created_at)}</span>
										{#if h.actor_id}
											<span class="muted">· {t('admin.reports.reportBy', { id: h.actor_id.slice(0, 8) })}</span>
										{/if}
										{#if h.deadline_at}
											<span class="muted">· {t('admin.reports.dispute.deadlineOn', { date: formatDate(h.deadline_at) })}</span>
										{/if}
										{#if h.note}<p class="notes">{h.note}</p>{/if}
									</li>
								{/each}
							</ul>
						{/if}
					</section>
				{/if}

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
	open={!!confirmDispute}
	danger={confirmDispute === 'takedown'}
	title={confirmDispute === 'takedown'
		? t('admin.reports.dispute.confirmHideTitle')
		: confirmDispute === 'rename_notice'
			? t('admin.reports.dispute.confirmRenameTitle')
			: t('admin.reports.dispute.confirmDismissTitle')}
	message={confirmDispute === 'takedown'
		? t('admin.reports.dispute.confirmHideMessage')
		: confirmDispute === 'rename_notice'
			? t('admin.reports.dispute.confirmRenameMessage', { days: deadlineDaysOrNull(deadlineDays) ?? DISPUTE_DEADLINE_DEFAULT_DAYS })
			: t('admin.reports.dispute.confirmDismissMessage')}
	confirmLabel={confirmDispute === 'takedown'
		? t('admin.reports.dispute.hide')
		: confirmDispute === 'rename_notice'
			? t('admin.reports.dispute.rename')
			: t('admin.reports.dispute.dismiss')}
	data-testid="admin-dispute-confirm"
	onconfirm={() => {
		const action = confirmDispute;
		confirmDispute = null;
		if (action) doDisputeAction(action);
	}}
	oncancel={() => (confirmDispute = null)}
/>

<ConfirmDialog
	open={!!confirmCourse}
	danger={confirmCourse === 'closed'}
	title={confirmCourse === 'closed' ? t('admin.reports.course.confirmCloseTitle') : t('admin.reports.course.confirmReopenTitle')}
	message={confirmCourse === 'closed'
		? t('admin.reports.course.confirmCloseMessage')
		: t('admin.reports.course.confirmReopenMessage')}
	confirmLabel={confirmCourse === 'closed' ? t('admin.reports.course.close') : t('admin.reports.course.reopen')}
	data-testid="admin-course-confirm"
	onconfirm={() => {
		const status = confirmCourse;
		confirmCourse = null;
		if (status) doCourseStatus(status);
	}}
	oncancel={() => (confirmCourse = null)}
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
	.nps-pending {
		margin: 0;
	}
	.muted {
		color: var(--color-text-secondary);
	}
	.not-authorized {
		padding: var(--space-xl);
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
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: 0.5rem;
	}
	.dispute-line {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.35rem;
		margin-top: 0.3rem;
		font-size: 0.8rem;
	}
	.dispute-badge {
		display: inline-block;
		padding: 0.1rem 0.45rem;
		border-radius: var(--radius-sm);
		border: 1px solid var(--color-primary);
		color: var(--color-primary);
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.dispute-club {
		display: inline-flex;
		align-items: center;
		gap: 0.15rem;
	}
	.verified {
		font-size: 1rem;
		color: var(--color-primary);
		vertical-align: middle;
	}
	.deadline.overdue {
		color: var(--color-danger-text);
		font-weight: 600;
	}
	.dispute-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-sm);
		border: 1px solid var(--color-primary);
		border-radius: var(--radius-sm);
	}
	.dispute-panel h3,
	.dispute-panel h4,
	.dispute-panel p {
		margin: 0;
	}
	.dispute-panel h3 {
		font-size: 1rem;
	}
	.dispute-panel h4 {
		font-size: 0.85rem;
	}
	.deadline-field {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.84rem;
	}
	.deadline-field input {
		width: 5rem;
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
		font: inherit;
	}
	.history {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		font-size: 0.82rem;
	}
</style>
