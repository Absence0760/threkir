<script lang="ts">
	// The race panel for a Scheduled GO or Self-timed race (#1306, decisions
	// § 2400). The server fires GO, opens and closes the window; this shows
	// where the race is on the server clock and gives the organiser what each
	// mode allows: Delay and Cancel until a scheduled GO passes; Extend and End
	// early while a window is open. A runner gets the countdown, or the
	// Self-timed "Join and attempt" path (the attempt itself is timed by the
	// phone or watch, so the web says where to do it).
	import { onDestroy, onMount } from 'svelte';
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import {
		delayRaceStart,
		fetchServerClockOffsetMs,
		setRaceWindowClose,
		type RaceSessionRow
	} from '#lib/core/data.ts';
	import {
		RACE_WINDOW_MAX_S,
		effectiveRaceStatus,
		raceCountdownS,
		raceStartInstant,
		selfTimedAttemptState,
		type RaceStatus
	} from '#lib/races/race_start_modes.ts';
	import type { SessionStartMode } from '#lib/races/course_gates.ts';
	import { isKnownTimeZone, zoneOffsetMs } from '#lib/social/zoned_time.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import HelpLink from '#lib/components/help/HelpLink.svelte';

	interface Props {
		eventId: string;
		instanceStart: string;
		mode: Exclude<SessionStartMode, 'host_go'>;
		/// events.timezone; null for a legacy event, shown in UTC and labelled.
		timezone: string | null;
		session: RaceSessionRow | null;
		isDirector: boolean;
		going: boolean;
		courseCount: number;
		courseChosen: boolean;
		busy?: boolean;
		onsession: (row: RaceSessionRow) => void;
		onarm: () => void;
		oncancel: () => void;
		onend: () => void;
		onjoin: () => void;
	}

	let {
		eventId,
		instanceStart,
		mode,
		timezone,
		session,
		isDirector,
		going,
		courseCount,
		courseChosen,
		busy = false,
		onsession,
		onarm,
		oncancel,
		onend,
		onjoin
	}: Props = $props();

	let offsetMs = $state(0);
	let clockSampled = $state(false);
	let nowMs = $state(Date.now());
	let working = $state(false);
	let error = $state<string | null>(null);
	let delayMin = $state<number>(15);
	let extendHours = $state<number>(1);
	let timer: ReturnType<typeof setInterval> | null = null;

	onMount(() => {
		void fetchServerClockOffsetMs().then((o) => {
			if (o != null) {
				offsetMs = o;
				clockSampled = true;
			}
		});
		timer = setInterval(() => (nowMs = Date.now()), 1000);
	});
	onDestroy(() => {
		if (timer) clearInterval(timer);
	});

	const zone = $derived(isKnownTimeZone(timezone) ? timezone : 'UTC');
	const serverNow = $derived(nowMs + offsetMs);

	const status = $derived<RaceStatus | null>(
		session
			? effectiveRaceStatus(
					{
						status: session.status,
						startMode: session.start_mode ?? mode,
						scheduledStartAt: session.scheduled_start_at ?? null,
						windowOpensAt: session.window_opens_at ?? null,
						windowClosesAt: session.window_closes_at ?? null
					},
					serverNow
				)
			: null
	);
	const startIso = $derived(
		session
			? raceStartInstant({
					status: session.status,
					startMode: session.start_mode ?? mode,
					scheduledStartAt: session.scheduled_start_at ?? null,
					windowOpensAt: session.window_opens_at ?? null,
					windowClosesAt: session.window_closes_at ?? null
				})
			: null
	);
	const countdownS = $derived(status === 'armed' ? raceCountdownS(startIso, nowMs, offsetMs) : null);
	const closesIso = $derived(session?.window_closes_at ?? null);
	const attempt = $derived(
		mode === 'self_timed' && status
			? selfTimedAttemptState({ effectiveStatus: status, going, courseCount, courseChosen })
			: null
	);

	/// An instant in the event's zone, with the viewer's own clock beside it
	/// when the two read differently (m14).
	function when(iso: string | null): string {
		if (!iso) return '';
		const t = Date.parse(iso);
		const locale = currentLocale();
		const opts: Intl.DateTimeFormatOptions = {
			weekday: 'short',
			day: 'numeric',
			month: 'short',
			hour: '2-digit',
			minute: '2-digit'
		};
		const there = new Intl.DateTimeFormat(locale, { ...opts, timeZone: zone }).format(t);
		const label = isKnownTimeZone(timezone) ? zone : 'UTC';
		let viewerZone: string | null = null;
		try {
			viewerZone = Intl.DateTimeFormat().resolvedOptions().timeZone ?? null;
		} catch {
			viewerZone = null;
		}
		if (viewerZone && isKnownTimeZone(viewerZone) && zoneOffsetMs(t, viewerZone) !== zoneOffsetMs(t, zone)) {
			const here = new Intl.DateTimeFormat(locale, { hour: '2-digit', minute: '2-digit' }).format(t);
			return m('raceStart.whenWithLocal', { time: there, zone: label, local: here });
		}
		return m('raceStart.when', { time: there, zone: label });
	}

	async function run(action: () => Promise<RaceSessionRow>) {
		if (working) return;
		working = true;
		error = null;
		try {
			onsession(await action());
		} catch (e) {
			error = errorCopy(e, m, 'raceStart.changeFailed', 'raceStart.changeFailed');
		} finally {
			working = false;
		}
	}

	function delay() {
		if (!session || !startIso || !(delayMin > 0)) return;
		const next = new Date(Math.max(Date.parse(startIso), serverNow) + delayMin * 60_000).toISOString();
		void run(() => delayRaceStart(eventId, instanceStart, mode, next));
	}

	function extend() {
		if (!session || !closesIso || !startIso || !(extendHours > 0)) return;
		const cap = Date.parse(startIso) + RACE_WINDOW_MAX_S * 1000;
		const next = Math.min(Date.parse(closesIso) + extendHours * 3_600_000, cap);
		void run(() => setRaceWindowClose(eventId, instanceStart, new Date(next).toISOString()));
	}

	const canExtend = $derived(
		!!closesIso && !!startIso && Date.parse(closesIso) < Date.parse(startIso) + RACE_WINDOW_MAX_S * 1000
	);
</script>

<section class="card race-mode-panel" data-testid="race-mode-panel" data-race-mode={mode} data-race-status={status ?? 'none'}>
	<div class="head">
		<h3>{mode === 'scheduled' ? m('raceStart.scheduledTitle') : m('raceStart.selfTimedTitle')}</h3>
		<a class="btn-link" href={`/live/event/${eventId}/${encodeURIComponent(instanceStart)}`} target="_blank" rel="noopener">
			{m('clubEvent.spectatorView')}
			<span class="material-symbols external-mark" aria-hidden="true">arrow_outward</span>
		</a>
	</div>
	{#if isDirector}
		<HelpLink guide="choose-how-your-race-starts" />
	{:else if mode === 'self_timed'}
		<HelpLink guide="run-a-self-timed-race" />
	{/if}

	{#if !session}
		<p class="muted" data-testid="race-mode-not-created">
			{mode === 'scheduled' ? m('raceStart.scheduledNotYet') : m('raceStart.selfTimedNotYet')}
		</p>
		{#if isDirector}
			<button type="button" class="btn btn-primary-sm" onclick={onarm} disabled={busy || working} data-testid="race-arm-early">
				{m('raceStart.armEarly')}
			</button>
		{/if}
	{:else if status === 'armed'}
		{#if mode === 'scheduled'}
			<p class="state armed">
				<span class="dot armed-dot"></span>
				<strong>{m('raceStart.goAt', { when: when(startIso) })}</strong>
			</p>
			{#if countdownS != null}
				<p class="countdown" data-testid="race-countdown">
					{m('raceStart.countdown', { time: formatDuration(countdownS) })}
				</p>
			{/if}
			{#if !clockSampled}
				<p class="hint">{m('raceStart.deviceClock')}</p>
			{/if}
		{:else}
			<p class="state armed">
				<span class="dot armed-dot"></span>
				<strong>{m('raceStart.opensAt', { when: when(startIso) })}</strong>
			</p>
			<p class="hint">{m('raceStart.closesAt', { when: when(closesIso) })}</p>
		{/if}
		{#if isDirector}
			<div class="actions">
				<label class="inline">
					<span>{m('raceStart.delayBy')}</span>
					<input type="number" min="1" max="1440" bind:value={delayMin} aria-label={m('raceStart.delayMinutes')} />
					<span>{m('raceStart.minutes')}</span>
				</label>
				<button type="button" class="btn btn-secondary btn-sm" onclick={delay} disabled={busy || working} data-testid="race-delay">
					{m('raceStart.delay')}
				</button>
				<button type="button" class="btn-link" onclick={oncancel} disabled={busy || working} data-testid="race-cancel">
					{m('clubEvent.cancel')}
				</button>
			</div>
		{/if}
	{:else if status === 'running'}
		{#if mode === 'scheduled'}
			<p class="state running">
				<span class="dot running-dot"></span>
				<strong>{m('raceStart.liveSince', { when: when(startIso) })}</strong>
			</p>
			<p class="hint">{m('raceStart.autoEnds', { when: when(closesIso) })}</p>
		{:else}
			<p class="state running" data-testid="race-window-open">
				<span class="dot running-dot"></span>
				<strong>{m('raceStart.openUntil', { when: when(closesIso) })}</strong>
			</p>
			<p class="hint">{m('raceStart.selfTimedHow')}</p>
		{/if}
		{#if isDirector}
			<div class="actions">
				{#if mode === 'self_timed'}
					<label class="inline">
						<span>{m('raceStart.extendBy')}</span>
						<input type="number" min="1" max="168" bind:value={extendHours} aria-label={m('raceStart.extendHours')} />
						<span>{m('raceStart.hours')}</span>
					</label>
					<button type="button" class="btn btn-secondary btn-sm" onclick={extend} disabled={busy || working || !canExtend} data-testid="race-extend">
						{m('raceStart.extend')}
					</button>
				{/if}
				<button type="button" class="btn btn-danger" onclick={onend} disabled={busy || working} data-testid="race-end-early">
					{mode === 'self_timed' ? m('raceStart.endEarly') : m('clubEvent.endRace')}
				</button>
			</div>
		{/if}
	{:else}
		<p class="muted">{m('raceStart.closed')}</p>
	{/if}

	{#if attempt && attempt !== 'closed' && attempt !== 'not_open' && !isDirector}
		<div class="attempt" data-testid="self-timed-banner" data-attempt={attempt}>
			{#if attempt === 'join'}
				<p>{m('raceStart.joinHint')}</p>
				<button type="button" class="btn btn-primary-sm" onclick={onjoin} disabled={busy} data-testid="self-timed-join">
					{courseCount > 1 ? m('raceStart.joinChooseCourse') : m('raceStart.joinAndAttempt')}
				</button>
			{:else if attempt === 'choose_course'}
				<p>{m('raceStart.chooseCourseHint')}</p>
			{:else}
				<p>{m('raceStart.attemptOnDevice')}</p>
			{/if}
		</div>
	{/if}

	{#if error}
		<p class="error" role="alert">{error}</p>
	{/if}
</section>

<style>
	.external-mark {
		font-size: inherit;
		vertical-align: -0.125em;
	}
	.race-mode-panel .head {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		gap: var(--space-sm, 0.5rem);
	}
	.state {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		margin: 0.5rem 0;
	}
	.countdown {
		font-size: 1.5rem;
		font-variant-numeric: tabular-nums;
		margin: 0.25rem 0;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem;
		margin-top: 0.5rem;
	}
	.inline {
		display: inline-flex;
		align-items: center;
		gap: 0.375rem;
	}
	.inline input {
		width: 5rem;
		min-height: 44px;
	}
	.attempt {
		margin-top: 0.75rem;
		padding-top: 0.75rem;
		border-top: 1px solid var(--color-border);
	}
	.dot {
		width: 0.625rem;
		height: 0.625rem;
		border-radius: 50%;
		display: inline-block;
	}
	.armed-dot {
		background: var(--color-primary);
	}
	.running-dot {
		background: var(--color-success);
	}
	.error {
		color: var(--color-danger-text);
	}
</style>
