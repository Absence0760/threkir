<script lang="ts">
	// The event editor's race start mode (#1306, decisions § 2400). The times
	// are stored as offsets from each occurrence's start, so a moved occurrence
	// keeps them; here they are shown and typed as wall times on the event's
	// clock ("GO at 07:30", "opens the day after at 06:00"), and each occurrence's
	// session can still be delayed or extended on its own from the race panel.
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		RACE_WINDOW_MAX_S,
		localFromStartOffset,
		startOffsetFromLocal,
		validateStartSettings,
		type StartSettingsError
	} from '#lib/races/race_start_modes.ts';
	import type { SessionStartMode } from '#lib/races/course_gates.ts';

	interface Props {
		/// The occurrence's start time on the event's clock, "HH:MM".
		startTime: string;
		mode: SessionStartMode;
		scheduledOffsetS: number | null;
		windowOpenOffsetS: number | null;
		windowLengthS: number | null;
		/// null = the mode's default (on for Scheduled, off for Self-timed).
		autoApprove: boolean | null;
	}

	let {
		startTime,
		mode = $bindable(),
		scheduledOffsetS = $bindable(),
		windowOpenOffsetS = $bindable(),
		windowLengthS = $bindable(),
		autoApprove = $bindable()
	}: Props = $props();

	const minuteOf = (hhmm: string): number => {
		const [h, mi] = hhmm.split(':').map((x) => Number(x));
		return Number.isFinite(h) && Number.isFinite(mi) ? h * 60 + mi : 0;
	};
	const hhmm = (minute: number): string =>
		`${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;

	const startMinute = $derived(minuteOf(startTime));

	function pickMode(next: SessionStartMode) {
		mode = next;
		if (next === 'scheduled' && scheduledOffsetS == null) scheduledOffsetS = 0;
		if (next === 'self_timed' && windowOpenOffsetS == null) windowOpenOffsetS = 0;
		if (next !== 'host_go' && windowLengthS == null) {
			windowLengthS = next === 'scheduled' ? 3 * 3600 : 24 * 3600;
		}
	}

	const goLocal = $derived(localFromStartOffset(startMinute, scheduledOffsetS ?? 0));
	const openLocal = $derived(localFromStartOffset(startMinute, windowOpenOffsetS ?? 0));

	function setGo(day: number, time: string) {
		scheduledOffsetS = startOffsetFromLocal(startMinute, { dayOffset: day, minuteOfDay: minuteOf(time) });
	}
	function setOpen(day: number, time: string) {
		windowOpenOffsetS = startOffsetFromLocal(startMinute, { dayOffset: day, minuteOfDay: minuteOf(time) });
	}

	const lengthDays = $derived(Math.floor((windowLengthS ?? 0) / 86400));
	const lengthHours = $derived(Math.round(((windowLengthS ?? 0) % 86400) / 3600));
	function setLength(days: number, hours: number) {
		const s = Math.max(0, Math.floor(days || 0)) * 86400 + Math.max(0, Math.floor(hours || 0)) * 3600;
		windowLengthS = Math.min(s, RACE_WINDOW_MAX_S);
	}

	const errors = $derived<StartSettingsError[]>(
		validateStartSettings({ mode, scheduledOffsetS, windowOpenOffsetS, windowLengthS })
	);
	const autoApproveOn = $derived(autoApprove ?? mode !== 'self_timed');

	function errorCopy(e: StartSettingsError): string {
		switch (e) {
			case 'scheduled_offset_required':
			case 'scheduled_offset_range':
				return m('raceStart.errGoRange');
			case 'window_open_required':
			case 'window_open_range':
				return m('raceStart.errOpenRange');
			case 'window_length_required':
			case 'window_length_range':
				return m('raceStart.errLengthRange');
		}
	}

	const dayChoices = [-1, 0, 1, 2, 3, 4, 5, 6, 7];
	function dayLabel(d: number): string {
		if (d === 0) return m('raceStart.daySame');
		if (d === -1) return m('raceStart.dayBefore');
		return m('raceStart.dayAfter', { n: d });
	}
</script>

<fieldset class="start-mode" data-testid="race-start-mode">
	<legend>{m('raceStart.legend')}</legend>
	<p class="hint">{m('raceStart.explainer')}</p>
	<div class="modes" role="radiogroup" aria-label={m('raceStart.legend')}>
		{#each [
			{ value: 'host_go', label: m('raceStart.modeHostGo'), hint: m('raceStart.modeHostGoHint') },
			{ value: 'scheduled', label: m('raceStart.modeScheduled'), hint: m('raceStart.modeScheduledHint') },
			{ value: 'self_timed', label: m('raceStart.modeSelfTimed'), hint: m('raceStart.modeSelfTimedHint') }
		] as opt (opt.value)}
			<label class="mode">
				<input
					type="radio"
					name="race-start-mode"
					value={opt.value}
					checked={mode === opt.value}
					onchange={() => pickMode(opt.value as SessionStartMode)}
					data-testid={`race-start-mode-${opt.value}`}
				/>
				<span>
					<strong>{opt.label}</strong>
					<span class="hint">{opt.hint}</span>
				</span>
			</label>
		{/each}
	</div>

	{#if mode === 'scheduled'}
		<div class="row">
			<label>
				<span>{m('raceStart.goTime')}</span>
				<input
					type="time"
					value={hhmm(goLocal.minuteOfDay)}
					onchange={(e) => setGo(goLocal.dayOffset, (e.currentTarget as HTMLInputElement).value)}
					data-testid="race-go-time"
				/>
			</label>
			<label>
				<span>{m('raceStart.goDay')}</span>
				<select
					value={goLocal.dayOffset}
					onchange={(e) => setGo(Number((e.currentTarget as HTMLSelectElement).value), hhmm(goLocal.minuteOfDay))}
				>
					{#each [-1, 0, 1] as d (d)}
						<option value={d}>{dayLabel(d)}</option>
					{/each}
				</select>
			</label>
		</div>
		<p class="hint">{m('raceStart.autoEndHint')}</p>
	{:else if mode === 'self_timed'}
		<div class="row">
			<label>
				<span>{m('raceStart.opensTime')}</span>
				<input
					type="time"
					value={hhmm(openLocal.minuteOfDay)}
					onchange={(e) => setOpen(openLocal.dayOffset, (e.currentTarget as HTMLInputElement).value)}
					data-testid="race-open-time"
				/>
			</label>
			<label>
				<span>{m('raceStart.opensDay')}</span>
				<select
					value={openLocal.dayOffset}
					onchange={(e) => setOpen(Number((e.currentTarget as HTMLSelectElement).value), hhmm(openLocal.minuteOfDay))}
				>
					{#each dayChoices as d (d)}
						<option value={d}>{dayLabel(d)}</option>
					{/each}
				</select>
			</label>
		</div>
		<p class="hint">{m('raceStart.selfTimedLinesHint')}</p>
		<p class="hint warn">{m('raceStart.appVersionWarning')}</p>
	{/if}

	{#if mode !== 'host_go'}
		<div class="row">
			<label>
				<span>{mode === 'self_timed' ? m('raceStart.windowDays') : m('raceStart.autoEndDays')}</span>
				<input
					type="number"
					min="0"
					max="7"
					value={lengthDays}
					onchange={(e) => setLength(Number((e.currentTarget as HTMLInputElement).value), lengthHours)}
					data-testid="race-window-days"
				/>
			</label>
			<label>
				<span>{m('raceStart.windowHours')}</span>
				<input
					type="number"
					min="0"
					max="23"
					value={lengthHours}
					onchange={(e) => setLength(lengthDays, Number((e.currentTarget as HTMLInputElement).value))}
					data-testid="race-window-hours"
				/>
			</label>
		</div>
		<label class="checkbox-row">
			<input
				type="checkbox"
				checked={autoApproveOn}
				onchange={(e) => (autoApprove = (e.currentTarget as HTMLInputElement).checked)}
				data-testid="race-auto-approve"
			/>
			<span>
				{m('clubEvent.autoApproveResults')}
				{#if mode === 'self_timed'}<span class="hint">{m('raceStart.autoApproveSelfTimedHint')}</span>{/if}
			</span>
		</label>
		{#each errors as e (e)}
			<p class="error" role="alert" data-testid="race-start-error">{errorCopy(e)}</p>
		{/each}
	{/if}
</fieldset>

<style>
	.start-mode {
		display: grid;
		gap: 0.5rem;
	}
	.modes {
		display: grid;
		gap: 0.5rem;
	}
	.mode {
		display: flex;
		gap: 0.5rem;
		align-items: flex-start;
		min-height: 44px;
	}
	.mode span {
		display: grid;
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem;
	}
	.row label {
		display: grid;
		gap: 0.25rem;
	}
	.row input,
	.row select {
		min-height: 44px;
	}
	.checkbox-row {
		display: flex;
		gap: 0.5rem;
		align-items: flex-start;
	}
	.warn {
		color: var(--color-warning-text);
	}
	.error {
		color: var(--color-danger-text);
		margin: 0;
	}
</style>
