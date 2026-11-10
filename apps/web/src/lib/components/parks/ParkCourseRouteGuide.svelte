<script lang="ts">
	// A park course's route guide (issue #1344): its steps as an ordered list
	// in the reader's language and unit, under a note saying whether a person
	// has walked it at the park yet. Shared by the course page and its share
	// page, so the indexable page reads the same guide the runner does.
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { formatDistance, formatElevation } from '#lib/format/units.svelte.ts';
	import { formatGuideLine, routeGuideLines, type RouteGuide } from '#lib/parks/route_guide.ts';

	let {
		guide,
		checkedAt,
		testidPrefix,
	}: { guide: RouteGuide; checkedAt: string | null; testidPrefix: 'park-course' | 'share-course' } = $props();

	const headingId = $derived(`${testidPrefix}-guide-title`);
	const lines = $derived(
		routeGuideLines(guide).map((line) =>
			formatGuideLine(line, {
				message: (key, params) => m(`parks.guide.${key}`, params),
				distance: formatDistance,
				short: formatElevation,
			}),
		),
	);
	const checkedLabel = $derived.by(() => {
		if (!checkedAt) return null;
		const date = new Date(`${checkedAt}T00:00:00Z`);
		if (Number.isNaN(date.getTime())) return null;
		return new Intl.DateTimeFormat(currentLocale(), { dateStyle: 'medium', timeZone: 'UTC' }).format(date);
	});
</script>

<section class="guide" aria-labelledby={headingId} data-testid="{testidPrefix}-guide">
	<h2 class="title" id={headingId}>{m('parks.guide.title')}</h2>
	{#if checkedLabel}
		<p class="status" data-testid="{testidPrefix}-guide-checked">{m('parks.guide.checked', { date: checkedLabel })}</p>
	{:else}
		<p class="status pending" data-testid="{testidPrefix}-guide-pending">{m('parks.guide.pending')}</p>
	{/if}
	{#if guide.gettingThere}
		<h3 class="sub">{m('parks.guide.gettingThere')}</h3>
		<p class="getting-there" lang={guide.lang} data-testid="{testidPrefix}-guide-getting-there">{guide.gettingThere}</p>
	{/if}
	<ol data-testid="{testidPrefix}-guide-steps">
		{#each lines as line, i (i)}
			<li>{line}</li>
		{/each}
	</ol>
</section>

<style>
	.guide {
		text-align: left;
	}
	.title {
		margin: 0 0 var(--space-sm);
		font-size: var(--font-size-section-title);
		font-weight: 600;
	}
	.status {
		margin: 0 0 var(--space-sm);
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}
	.pending {
		padding: var(--space-xs) var(--space-sm);
		border-left: 4px solid var(--color-warning);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		color: var(--color-text);
	}
	.sub {
		margin: var(--space-sm) 0 var(--space-xs);
		font-size: 0.95rem;
		font-weight: 600;
	}
	.getting-there {
		margin: 0 0 var(--space-sm);
		line-height: 1.5;
	}
	ol {
		margin: 0;
		padding-left: 1.4rem;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		line-height: 1.5;
	}
</style>
