<script lang="ts">
	// Organiser course alerts on a race or a route (issue #1190, decisions
	// § 2407): reroutes, closures, the course direction, notices. Anyone who
	// can see the course reads them; only an owner/admin of the verified club
	// that organises the race (or owns the route) is offered the form. The
	// RPCs re-check that, so this only decides what to show.
	import { formatDate } from '#lib/format/time.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { deferDestructive } from '#lib/stores/undo.svelte.ts';
	import {
		deleteCourseAlert,
		fetchCourseAlerts,
		fetchMyClubs,
		postCourseAlert,
		type CourseAlert,
		type CourseAlertTarget,
	} from '#lib/core/data.ts';
	import { organiserClubsOf } from '#lib/integrations/race_course_access.ts';
	import { COURSE_ALERT_KINDS, type CourseAlertKind } from '#lib/types.ts';

	interface Props {
		target: CourseAlertTarget;
		/// The club that may post: the race's organiser club or the route's
		/// owning club. Null hides the form.
		clubId: string | null;
		signedIn: boolean;
	}
	let { target, clubId, signedIn }: Props = $props();

	const MESSAGE_MAX = 500;

	let alerts = $state<CourseAlert[]>([]);
	let loadFailed = $state(false);
	let canPost = $state(false);
	let kind = $state<CourseAlertKind>('notice');
	let message = $state('');
	let busy = $state(false);

	const targetId = $derived(target.listingId ?? target.routeId);

	const KIND_ICONS: Record<CourseAlertKind, string> = {
		reroute: 'alt_route',
		closure: 'block',
		direction: 'route',
		notice: 'info',
	};

	function kindLabel(k: CourseAlertKind): string {
		switch (k) {
			case 'reroute':
				return m('courseAlerts.kindReroute');
			case 'closure':
				return m('courseAlerts.kindClosure');
			case 'direction':
				return m('courseAlerts.kindDirection');
			case 'notice':
				return m('courseAlerts.kindNotice');
		}
	}

	async function load(id: string | undefined) {
		loadFailed = false;
		try {
			const rows = await fetchCourseAlerts(target);
			if (id === targetId) alerts = rows;
		} catch (e) {
			console.error('course alerts: read failed', e);
			if (id === targetId) loadFailed = true;
		}
	}

	// Auxiliary: a failed membership read hides the form, never the page.
	async function loadAccess(id: string | undefined, club: string | null) {
		canPost = false;
		if (!signedIn || !club) return;
		try {
			const mine = organiserClubsOf(await fetchMyClubs());
			if (id === targetId) canPost = mine.some((c) => c.id === club);
		} catch (e) {
			console.error('course alerts: club read failed', e);
		}
	}

	$effect(() => {
		const id = targetId;
		alerts = [];
		void load(id);
		void loadAccess(id, clubId);
	});

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		const text = message.trim();
		if (!text || text.length > MESSAGE_MAX || busy) return;
		busy = true;
		try {
			await postCourseAlert(target, kind, text);
			message = '';
			kind = 'notice';
			showToast(m('courseAlerts.posted'), 'success');
			await load(targetId);
		} catch (err) {
			showToast(errorCopy(err, m, 'course alert post failed', 'courseAlerts.postFailed'), 'error');
		} finally {
			busy = false;
		}
	}

	// Removing an alert also withdraws the notices it sent, and posting it
	// again would notify everyone a second time, so the removal is held for
	// the undo window rather than run at once (conventions.md § Destructive
	// actions).
	function remove(alert: CourseAlert) {
		const before = alerts;
		alerts = alerts.filter((a) => a.id !== alert.id);
		deferDestructive({
			message: m('courseAlerts.removed'),
			commit: () => deleteCourseAlert(alert.id),
			restore: () => {
				alerts = before;
			},
			onCommitError: (err) =>
				showToast(errorCopy(err, m, 'course alert remove failed', 'courseAlerts.removeFailed'), 'error'),
		});
	}
</script>

{#if alerts.length > 0 || canPost || loadFailed}
	<section class="course-alerts" aria-labelledby="course-alerts-heading-{targetId}" data-testid="course-alerts">
		<h2 id="course-alerts-heading-{targetId}">{m('courseAlerts.heading')}</h2>
		{#if loadFailed}
			<div class="load-error" role="alert" data-testid="course-alerts-error">
				<span>{m('courseAlerts.loadFailed')}</span>
				<button type="button" class="btn btn-outline btn-sm" onclick={() => void load(targetId)}>
					{m('races.retry')}
				</button>
			</div>
		{/if}
		{#if alerts.length > 0}
			<ul class="alerts">
				{#each alerts as a (a.id)}
					<li class="alert alert-{a.kind}" data-testid="course-alert" data-kind={a.kind}>
						<span class="material-symbols alert-icon" aria-hidden="true">{KIND_ICONS[a.kind]}</span>
						<div class="alert-body">
							<p class="alert-head">
								<strong>{kindLabel(a.kind)}</strong>
								<span class="alert-date">{formatDate(a.createdAt.slice(0, 10))}</span>
							</p>
							<p class="alert-message">{a.message}</p>
						</div>
						{#if canPost}
							<button
								type="button"
								class="btn btn-outline btn-sm"
								onclick={() => remove(a)}
								data-testid="course-alert-remove"
								aria-label={m('courseAlerts.removeLabel', { kind: kindLabel(a.kind) })}
							>
								{m('courseAlerts.remove')}
							</button>
						{/if}
					</li>
				{/each}
			</ul>
		{:else if !loadFailed}
			<p class="hint" data-testid="course-alerts-empty">{m('courseAlerts.empty')}</p>
		{/if}
		{#if canPost}
			<form class="post" onsubmit={submit} data-testid="course-alert-form">
				<label class="field">
					<span>{m('courseAlerts.kindLabel')}</span>
					<select bind:value={kind} data-testid="course-alert-kind">
						{#each COURSE_ALERT_KINDS as k (k)}
							<option value={k}>{kindLabel(k)}</option>
						{/each}
					</select>
				</label>
				<label class="field">
					<span>{m('courseAlerts.messageLabel')}</span>
					<textarea
						bind:value={message}
						maxlength={MESSAGE_MAX}
						rows="3"
						required
						data-testid="course-alert-message"
					></textarea>
				</label>
				<p class="hint">{m('courseAlerts.postHint')}</p>
				<button
					type="submit"
					class="btn btn-primary"
					disabled={busy || message.trim().length === 0}
					data-testid="course-alert-post"
				>
					{busy ? m('courseAlerts.posting') : m('courseAlerts.post')}
				</button>
			</form>
		{/if}
	</section>
{/if}

<style>
	.course-alerts {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.course-alerts h2 {
		font-size: 1.1rem;
		margin: 0;
	}
	.alerts {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.alert {
		display: flex;
		align-items: flex-start;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-inline-start-width: 4px;
		border-radius: var(--radius-md);
	}
	.alert-closure {
		border-inline-start-color: var(--color-danger-text);
	}
	.alert-reroute,
	.alert-direction {
		border-inline-start-color: var(--color-warning-text);
	}
	.alert-icon {
		font-size: 20px;
	}
	.alert-body {
		flex: 1;
		min-width: 0;
	}
	.alert-head {
		display: flex;
		gap: var(--space-sm);
		align-items: baseline;
		margin: 0;
	}
	.alert-date {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.alert-message {
		margin: var(--space-xs) 0 0;
		white-space: pre-line;
		overflow-wrap: anywhere;
	}
	.post {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		max-width: 32rem;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.hint {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.load-error {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		color: var(--color-danger-text);
	}
</style>
