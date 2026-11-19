<script lang="ts">
	// A park course's route guide (issue #1344): a short list a runner reads in
	// seconds (the start, the laps, the turns where the trail changes, the
	// finish), with every step folded away under it, grouped by lap or by
	// stretch (routeGuideView, decisions § 2581), in the reader's language and
	// unit, under a note saying whether a person has walked it at the park
	// yet. Shared by the course page and its share page, so the indexable page
	// reads the same guide the runner does.
	import { m, currentLocale } from '#lib/i18n/store.svelte.ts';
	import { formatDistance, formatElevation } from '#lib/format/units.svelte.ts';
	import { formatGuideLine, routeGuideView, type GuideLine, type RouteGuide } from '#lib/parks/route_guide.ts';

	let {
		guide,
		checkedAt,
		testidPrefix,
	}: { guide: RouteGuide; checkedAt: string | null; testidPrefix: 'park-course' | 'share-course' } = $props();

	const headingId = $derived(`${testidPrefix}-guide-title`);
	const text = (line: GuideLine) =>
		formatGuideLine(line, {
			message: (key, params) => m(`parks.guide.${key}`, params),
			distance: formatDistance,
			short: formatElevation,
		});
	const view = $derived(routeGuideView(guide));
	const summary = $derived(view.summary.map(text));
	const sections = $derived(
		view.sections.map((s) => ({
			title:
				s.lap !== null
					? m('parks.guide.lapHeader', { n: s.lap })
					: m('parks.guide.kmHeader', { from: formatDistance(s.from), to: formatDistance(s.to) }),
			lines: s.lines.map(text),
		})),
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
		{#each summary as line, i (i)}
			<li>{line}</li>
		{/each}
	</ol>
	<details class="all" data-testid="{testidPrefix}-guide-all">
		<summary>{m('parks.guide.showAll')}</summary>
		{#each sections as section, i (i)}
			<h3 class="sub">{section.title}</h3>
			<ul>
				{#each section.lines as line, j (j)}
					<li>{line}</li>
				{/each}
			</ul>
		{/each}
	</details>
</section>

<style>
	.guide {
		text-align: start;
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
		border-inline-start: 4px solid var(--color-warning);
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
	.all {
		margin-top: var(--space-sm);
	}
	.all summary {
		cursor: pointer;
		font-weight: 600;
	}
	ol,
	ul {
		margin: 0;
		padding-inline-start: 1.4rem;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		line-height: 1.5;
	}
</style>
