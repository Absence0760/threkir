<script lang="ts">
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { formatDate } from '#lib/format/time.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { racePlanPreset } from '#lib/training/race_plan_preset.ts';
	import { racePlanHref } from '#lib/training/race_plan_prefill.ts';
	import { todayISO } from '#lib/training/training.ts';
	import type { RaceListingResult } from '#lib/core/data.ts';

	interface Props {
		race: RaceListingResult;
		onimport?: (race: RaceListingResult) => void;
	}
	let { race, onimport }: Props = $props();

	let awayLabel = $derived(
		race.distance_m_away == null
			? null
			: m('races.kmAway', { distance: formatDistance(race.distance_m_away) })
	);

	// Only offer to build a plan when one can actually be built for this race
	// — a past or too-close race gets no CTA rather than a link that lands on
	// a refusal. The wizard re-derives from the same helper, so a link that
	// goes stale in an open tab is caught there too.
	// A result exists only from race day on; before that the import can only
	// come back empty, so the action is not offered.
	let canImport = $derived(race.race_date <= todayISO());

	let planHref = $derived.by(() => {
		const preset = racePlanPreset({
			raceDateIso: race.race_date,
			distanceM: race.distance_m,
			todayIso: todayISO()
		});
		if (!preset.ok) return null;
		return racePlanHref({
			race: { name: race.name, raceDateIso: race.race_date, distanceM: race.distance_m }
		});
	});
</script>

<li class="card-elevated race" data-testid="race-card">
	<div class="race-main">
		<a class="race-title" href="/races/{race.id}" data-testid="race-detail-link">{race.name}</a>
		<span class="race-meta">
			{formatDate(race.race_date)}
			{#if race.distance_m}· {formatDistance(race.distance_m)}{/if}
			{#if race.location_label}· {race.location_label}{/if}
			{#if awayLabel}· <span class="race-away" data-testid="race-away">{awayLabel}</span>{/if}
		</span>
		{#if !race.is_verified}
			<span class="race-unverified" data-testid="race-unverified">{m('races.unverified')}</span>
		{/if}
	</div>
	<div class="race-actions">
		{#if planHref}
			<a class="btn btn-outline btn-sm" href={planHref} data-testid="race-train-for">
				{m('races.trainForThis')}
			</a>
		{/if}
		{#if race.entry_url}
			<a
				class="btn btn-outline btn-sm"
				href={race.entry_url}
				target="_blank"
				rel="noopener noreferrer"
				data-testid="race-register"
			>
				{m('races.register')}
			</a>
		{/if}
		{#if race.results_url}
			<a
				class="btn btn-outline btn-sm"
				href={race.results_url}
				target="_blank"
				rel="noopener noreferrer"
				data-testid="race-view-results"
			>
				{m('races.viewResults')}
			</a>
		{/if}
		{#if canImport}
			<button
				type="button"
				class="btn btn-primary btn-sm"
				onclick={() => onimport?.(race)}
				data-testid="race-import"
			>
				{m('races.importResult')}
			</button>
		{/if}
	</div>
</li>

<style>
	/* The whole card opens the race: the title link's ::after is stretched over
	   the card, and each action is lifted above it so it stays its own target.
	   One link, one tab stop, no interactive element nested in another. */
	.race {
		position: relative;
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		transition:
			box-shadow var(--transition-base),
			border-color var(--transition-base);
	}
	.race:hover {
		border-color: var(--color-primary);
	}
	.race:has(.race-title:focus-visible) {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.race-main {
		flex: 1 1 18rem;
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 0;
	}
	.race-title {
		font-size: 1rem;
		font-weight: 700;
		color: var(--color-text);
		text-decoration: none;
		/* Two lines, then an ellipsis: a long event name no longer pushes the
		   date and distance off the first screen. The full name is the detail
		   page's heading. Overflow here does not clip the stretched ::after,
		   whose containing block is the positioned card. */
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		overflow: hidden;
		overflow-wrap: anywhere;
	}
	.race-title::after {
		content: '';
		position: absolute;
		inset: 0;
		border-radius: var(--radius-lg);
	}
	.race-title:focus-visible {
		outline: none;
	}
	.race:hover .race-title,
	.race-title:focus-visible {
		text-decoration: underline;
	}
	.race-meta {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		overflow-wrap: anywhere;
	}
	.race-away {
		font-weight: 600;
		color: var(--color-text);
	}
	.race-unverified {
		align-self: flex-start;
		font-size: 0.72rem;
		font-weight: 600;
		padding: 0.1rem 0.45rem;
		border-radius: 999px;
		background: var(--color-fill-subtle);
		color: var(--color-text-secondary);
	}
	.race-actions {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	.race-actions:empty {
		display: none;
	}
	.race-actions > :global(*) {
		position: relative;
		z-index: 1;
	}
	@media (max-width: 40rem) {
		.race {
			padding: var(--space-md);
			gap: var(--space-sm);
		}
		.race-actions {
			justify-content: flex-start;
		}
		.race-actions > :global(*) {
			min-height: var(--tap-target-min);
		}
	}
</style>
