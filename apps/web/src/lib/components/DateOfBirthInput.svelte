<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { monthNames } from '#lib/format/calendar.ts';
	import {
		birthYearOptions,
		composeIsoDate,
		datePartOrder,
		daysInMonth,
		isFuture,
		isPartial,
		splitIsoDate,
		type DateParts,
	} from '#lib/format/birth_date.ts';

	let {
		value = $bindable(''),
		label,
		describedby = undefined,
		disabled = false,
		testid = 'date-of-birth',
		size = 'md',
	}: {
		/** `YYYY-MM-DD`, or '' for no date. */
		value?: string;
		label: string;
		describedby?: string;
		disabled?: boolean;
		testid?: string;
		/** `lg` matches the onboarding wizard's taller fields. */
		size?: 'md' | 'lg';
	} = $props();

	const uid = $props.id();
	const today = new Date();
	const years = birthYearOptions(today);

	let parts = $state<DateParts>(splitIsoDate(value));

	// A value set from outside (the page's async profile load, a reset) wins
	// over whatever is half-picked here.
	$effect(() => {
		const incoming = value;
		if (incoming !== (composeIsoDate(parts) ?? '')) parts = splitIsoDate(incoming);
	});

	const partial = $derived(isPartial(parts));
	const future = $derived(isFuture(parts, today));
	const order = $derived(datePartOrder(activeFormatLocale()));
	const months = $derived(monthNames(activeFormatLocale()));
	const dayCount = $derived(parts.month == null ? 31 : daysInMonth(parts.year, parts.month));

	// A half-picked or impossible date leaves `value` alone and says so,
	// rather than writing '' and having the next save clear a stored date.
	function commit(next: DateParts) {
		if (next.day != null && next.month != null && next.day > daysInMonth(next.year, next.month)) {
			next = { ...next, day: daysInMonth(next.year, next.month) };
		}
		parts = next;
		const iso = composeIsoDate(next);
		if (iso && !isFuture(next, today)) value = iso;
		else if (next.year == null && next.month == null && next.day == null) value = '';
	}

	function pick(part: keyof DateParts, raw: string) {
		commit({ ...parts, [part]: raw === '' ? null : Number(raw) });
	}

	const describedBy = $derived(
		[describedby, partial || future ? `${uid}-error` : null].filter(Boolean).join(' ') || undefined,
	);
</script>

<fieldset class="dob dob-{size}" {disabled} data-testid={testid} aria-describedby={describedBy}>
	<legend class="label-text">{label}</legend>
	<div class="dob-row">
		{#each order as part (part)}
			{#if part === 'month'}
				<select
					class="dob-month"
					aria-label={m('prefs.dobMonth')}
					aria-invalid={partial && parts.month == null}
					value={parts.month ?? ''}
					onchange={(e) => pick('month', e.currentTarget.value)}
					data-testid="{testid}-month"
				>
					<option value="">{m('prefs.dobMonth')}</option>
					{#each months as name, i (i)}
						<option value={i + 1}>{name}</option>
					{/each}
				</select>
			{:else if part === 'day'}
				<select
					class="dob-day"
					aria-label={m('prefs.dobDay')}
					aria-invalid={partial && parts.day == null}
					value={parts.day ?? ''}
					onchange={(e) => pick('day', e.currentTarget.value)}
					data-testid="{testid}-day"
				>
					<option value="">{m('prefs.dobDay')}</option>
					{#each Array.from({ length: dayCount }, (_, i) => i + 1) as d (d)}
						<option value={d}>{d}</option>
					{/each}
				</select>
			{:else}
				<select
					class="dob-year"
					aria-label={m('prefs.dobYear')}
					aria-invalid={partial && parts.year == null}
					value={parts.year ?? ''}
					onchange={(e) => pick('year', e.currentTarget.value)}
					data-testid="{testid}-year"
				>
					<option value="">{m('prefs.dobYear')}</option>
					{#each years as y (y)}
						<option value={y}>{y}</option>
					{/each}
				</select>
			{/if}
		{/each}
	</div>
	{#if partial || future}
		<p class="field-error" id="{uid}-error" data-testid="{testid}-error">
			{future ? m('prefs.dobFuture') : m('prefs.dobIncomplete')}
		</p>
	{/if}
</fieldset>

<style>
	.dob {
		border: 0;
		margin: 0;
		padding: 0;
		min-width: 0;
	}
	.dob legend {
		display: block;
		padding: 0;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-xs);
	}
	.dob-row {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
	}
	.dob select {
		flex: 1 1 auto;
		min-width: 0;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		background: var(--color-bg);
		color: var(--color-text);
	}
	.dob .dob-month { flex-basis: 8.5rem; }
	.dob .dob-day { flex-basis: 4.5rem; }
	.dob .dob-year { flex-basis: 5.5rem; }
	.dob-lg legend { font-size: 0.85rem; margin-bottom: var(--space-2xs); }
	.dob-lg select {
		min-height: 2.9rem;
		padding: 0.65rem 0.8rem;
		border-radius: var(--radius-lg);
		font-size: 1rem;
	}
	.dob select:focus { outline: none; border-color: var(--color-primary); }
	/* WCAG 2.4.7 + 2.4.11: the :focus rule drops the ring on a mouse click;
	   :focus-visible puts a real one back for keyboard focus. */
	.dob select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.dob select:disabled { opacity: 0.6; cursor: not-allowed; }
	.field-error {
		display: block;
		font-size: 0.78rem;
		color: var(--color-danger-text);
		line-height: 1.45;
		margin: var(--space-2xs) 0 0;
	}
</style>
