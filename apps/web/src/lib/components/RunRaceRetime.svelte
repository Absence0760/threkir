<script lang="ts">
	import { onMount } from 'svelte';
	import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { refusalCode } from '#lib/core/supabase_error.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import {
		fetchRunRetimeContext,
		retimeEventResult,
		type RetimeResultRow,
		type RunRetimeContext,
	} from '#lib/core/data.ts';
	import { computeRetime, type RetimeCandidate, type RetimeOutcome } from '#lib/races/race_retime.ts';
	import type { TrackPoint } from '#lib/types.ts';

	// "Re-time from my track" (#1307 M11): the owner of a run linked to a race
	// result re-runs the line timing over the stored track, sees the result
	// beside the current one, confirms, and the row is rewritten with the
	// crossings for the server to derive the times from.

	interface Props {
		runId: string;
		runOwnerId: string;
		eventId: string | null;
		startedAt: string;
		distanceM: number;
		track: TrackPoint[] | null | undefined;
	}
	let { runId, runOwnerId, eventId, startedAt, distanceM, track }: Props = $props();

	const isOwner = $derived(auth.user?.id === runOwnerId);

	let ctx = $state<RunRetimeContext | null>(null);
	let loading = $state(true);
	let loadFailed = $state(false);
	let nowMs = $state(Date.now());
	let confirming = $state(false);
	let busy = $state(false);
	/// What the last write came back as: re-timed, kept by the lock rule, or
	/// refused because the window closed while the panel was open.
	let written = $state<'done' | 'review' | 'kept' | null>(null);
	let closedByServer = $state(false);

	async function load() {
		loading = true;
		loadFailed = false;
		try {
			ctx = await fetchRunRetimeContext({ id: runId, event_id: eventId, started_at: startedAt });
			nowMs = Date.now();
		} catch (e) {
			errorCopy(e, m, 'retime context load failed');
			loadFailed = true;
		} finally {
			loading = false;
		}
	}

	const outcome = $derived<RetimeOutcome | null>(
		ctx === null
			? null
			: closedByServer
				? { kind: 'closed' }
				: computeRetime({
						track: track ?? [],
						runStartedAt: startedAt,
						session: ctx.session
							? {
									status: ctx.session.effective_status ?? ctx.session.status,
									start_mode: ctx.session.start_mode ?? null,
									started_at: ctx.session.started_at,
									finished_at: ctx.session.finished_at,
									window_opens_at: ctx.session.window_opens_at ?? null,
									window_closes_at: ctx.session.window_closes_at ?? null,
									is_auto_approve: ctx.session.is_auto_approve ?? null,
								}
							: null,
						course: ctx.course,
						current: ctx.current,
						nowMs,
					})
	);

	const candidate = $derived<RetimeCandidate | null>(
		outcome && 'candidate' in outcome ? outcome.candidate : null
	);
	const selfTimed = $derived(ctx?.session?.start_mode === 'self_timed');
	const eventName = $derived(ctx?.eventTitle ?? m('raceRetime.thisRace'));

	function time(s: number | null | undefined): string {
		return s == null ? '—' : formatDuration(s);
	}

	function currentLabel(c: RetimeResultRow | null): string | null {
		if (c === null) return m('raceRetime.currentNone');
		if (c.finisher_status === 'dnf') return m('raceRetime.currentDnf');
		return null;
	}

	function startLabel(d: string | null | undefined): string {
		if (d === 'gate') return m('raceRetime.startGate');
		if (d === 'device') return m('raceRetime.startDevice');
		return '—';
	}

	function finishLabel(d: string | null | undefined, method?: string | null): string {
		if (d === 'gate') return m('raceRetime.finishGate');
		if (d === 'zone') return m('raceRetime.finishZone');
		if (method === 'manual') return m('raceRetime.finishManual');
		if (method === 'host') return m('raceRetime.finishHost');
		return '—';
	}

	/// Whether the row the server kept is the one this re-time sent: the lock
	/// rule returns the old row unchanged rather than refusing.
	function tookCandidate(row: RetimeResultRow | null, c: RetimeCandidate): boolean {
		return (
			row !== null &&
			row.finish_method === 'auto' &&
			row.start_detection === c.startDetection &&
			row.finish_detection === c.finishDetection &&
			row.duration_s === c.durationS
		);
	}

	async function retime() {
		const c = candidate;
		if (!ctx || !c || busy) return;
		busy = true;
		try {
			const row = await retimeEventResult({
				eventId: ctx.eventId,
				instanceStart: ctx.instanceStart,
				runId,
				distanceM,
				courseId: ctx.course?.course_id ?? null,
				candidate: c,
			});
			const took = tookCandidate(row, c);
			written = !took ? 'kept' : row?.organiser_approved === false ? 'review' : 'done';
			ctx = { ...ctx, current: row };
			confirming = false;
			showToast(m(written === 'kept' ? 'raceRetime.kept' : 'raceRetime.done'), took ? 'success' : 'info');
		} catch (e) {
			confirming = false;
			if (refusalCode(e) === 'race_result_window_closed') {
				closedByServer = true;
			} else {
				showToast(errorCopy(e, m, 'retime write failed', 'raceRetime.failed'), 'error');
			}
		} finally {
			busy = false;
		}
	}

	onMount(() => {
		if (isOwner) void load();
		else loading = false;
	});
</script>

{#if isOwner && !loading && (loadFailed || ctx)}
	<section class="section race-retime" data-testid="race-retime">
		<h2>{m('raceRetime.title')}</h2>
		{#if loadFailed}
			<p class="retime-note" role="alert">{m('raceRetime.loadFailed')}</p>
			<button type="button" class="btn btn-outline btn-sm" onclick={load}>{m('raceRetime.retry')}</button>
		{:else if ctx && outcome}
			<p class="retime-intro">{m('raceRetime.intro', { event: eventName })}</p>

			{#if candidate}
				<table class="retime-compare" data-testid="race-retime-compare">
					<thead>
						<tr>
							<th scope="col"><span class="visually-hidden">{m('raceRetime.colWhat')}</span></th>
							<th scope="col">{m('raceRetime.colCurrent')}</th>
							<th scope="col">{m('raceRetime.colNew')}</th>
						</tr>
					</thead>
					<tbody>
						{#if currentLabel(ctx.current)}
							<tr>
								<th scope="row">{m('raceRetime.result')}</th>
								<td data-testid="race-retime-current-status">{currentLabel(ctx.current)}</td>
								<td>{m('raceRetime.finished')}</td>
							</tr>
						{/if}
						{#if !selfTimed}
							<tr>
								<th scope="row">{m('raceRetime.gunTime')}</th>
								<td>{time(ctx.current?.finisher_status === 'finished' ? ctx.current.gun_time_s : null)}</td>
								<td data-testid="race-retime-new-gun">{time(candidate.gunTimeS)}</td>
							</tr>
						{/if}
						<tr>
							<th scope="row">{m('raceRetime.chipTime')}</th>
							<td>{time(ctx.current?.finisher_status === 'finished' ? ctx.current.chip_time_s : null)}</td>
							<td data-testid="race-retime-new-chip">{time(candidate.chipTimeS)}</td>
						</tr>
						<tr>
							<th scope="row">{m('raceRetime.startMethod')}</th>
							<td>{startLabel(ctx.current?.start_detection)}</td>
							<td data-testid="race-retime-new-start">{startLabel(candidate.startDetection)}</td>
						</tr>
						<tr>
							<th scope="row">{m('raceRetime.finishMethod')}</th>
							<td>{finishLabel(ctx.current?.finish_detection, ctx.current?.finish_method)}</td>
							<td data-testid="race-retime-new-finish">{finishLabel(candidate.finishDetection)}</td>
						</tr>
					</tbody>
				</table>
				{#if candidate.clockBasis === 'device'}
					<p class="retime-note" data-testid="race-retime-clock-device">{m('raceRetime.clockDevice')}</p>
				{/if}
				{#if candidate.gapped}
					<p class="retime-note">{m('raceRetime.gapped')}</p>
				{/if}
				{#if candidate.outsideWindow}
					<p class="retime-note">{m('raceRetime.outsideWindow')}</p>
				{/if}
			{/if}

			<div class="retime-state" data-testid="race-retime-state" data-state={outcome.kind}>
				{#if written === 'kept'}
					<p>{m('raceRetime.kept')}</p>
				{:else if written === 'review'}
					<p>{m('raceRetime.doneReview')}</p>
				{:else if written === 'done'}
					<p>{m('raceRetime.done')}</p>
				{:else if outcome.kind === 'ready'}
					{#if outcome.approval === 'pending'}
						<p class="retime-note">{m('raceRetime.approvalPending')}</p>
					{:else if outcome.approval === 'unknown'}
						<p class="retime-note">{m('raceRetime.approvalUnknown')}</p>
					{/if}
					<button
						type="button"
						class="btn btn-primary btn-sm"
						disabled={busy}
						onclick={() => (confirming = true)}
						data-testid="race-retime-action"
					>
						{m('raceRetime.action')}
					</button>
				{:else if outcome.kind === 'unchanged'}
					<p>{m('raceRetime.unchanged')}</p>
				{:else if outcome.kind === 'locked'}
					<p>
						{outcome.reason === 'host'
							? m('raceRetime.lockedHost')
							: selfTimed
								? m('raceRetime.lockedProtectedSelf')
								: m('raceRetime.lockedProtected')}
					</p>
				{:else if outcome.kind === 'closed'}
					<p>{m('raceRetime.closed')}</p>
				{:else if outcome.kind === 'no_crossing'}
					<p>{m('raceRetime.noCrossing')}</p>
				{:else if outcome.reason === 'no_session'}
					<p>{m('raceRetime.reasonNoSession')}</p>
				{:else if outcome.reason === 'no_course'}
					<p>{m('raceRetime.reasonNoCourse')}</p>
				{:else if outcome.reason === 'self_cross'}
					<p>{m('raceRetime.reasonSelfCross')}</p>
				{:else if outcome.reason === 'no_line'}
					<p>{m('raceRetime.reasonNoLine')}</p>
				{:else if outcome.reason === 'no_distance'}
					<p>{m('raceRetime.reasonNoDistance')}</p>
				{:else if outcome.reason === 'no_go'}
					<p>{m('raceRetime.reasonNoGo')}</p>
				{:else}
					<p>{m('raceRetime.reasonNoTrack')}</p>
				{/if}
			</div>
		{/if}
	</section>

	{#if candidate}
		<ConfirmDialog
			open={confirming}
			title={m('raceRetime.confirmTitle')}
			message={m('raceRetime.confirmBody', { event: eventName, time: time(candidate.durationS) })}
			confirmLabel={m('raceRetime.confirm')}
			onconfirm={retime}
			oncancel={() => (confirming = false)}
			data-testid="race-retime-confirm"
		/>
	{/if}
{/if}

<style>
	.retime-intro {
		margin: 0 0 var(--space-sm);
		color: var(--color-text-secondary);
	}
	.retime-compare {
		width: 100%;
		border-collapse: collapse;
		margin: 0 0 var(--space-sm);
		font-variant-numeric: tabular-nums;
	}
	.retime-compare th,
	.retime-compare td {
		text-align: left;
		padding: 0.35rem 0.5rem 0.35rem 0;
		border-bottom: 1px solid var(--color-border);
	}
	.retime-compare thead th {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
		font-weight: 600;
	}
	.retime-compare tbody th {
		font-weight: 500;
		color: var(--color-text-secondary);
	}
	.retime-compare td {
		font-weight: 600;
	}
	.retime-note {
		margin: 0 0 var(--space-sm);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.retime-state p {
		margin: 0 0 var(--space-sm);
	}
</style>
