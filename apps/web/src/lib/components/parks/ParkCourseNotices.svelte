<script lang="ts">
	// Everything a runner should know before setting off on a park course, in
	// one callout (issue #1352): the safety notice first, then the give-way
	// note when an organised group shares the paths (decisions § 2460), the
	// long-course notice when it applies, then the times and not-affiliated
	// notes. Each line keeps the test id it had when they were separate pieces
	// of fine print.
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { isLongCourse, type SharedUse } from '#lib/parks/park_courses.ts';

	let {
		distanceM,
		sharedUse,
		testidPrefix,
	}: { distanceM: number; sharedUse: SharedUse | null; testidPrefix: 'park-course' | 'share-course' } = $props();

	const SHARED_USE_NOTE: Record<SharedUse, MessageKey> = {
		saturday_morning_group: 'parks.sharedUseSaturdayMorningGroup',
	};

	const headingId = $derived(`${testidPrefix}-notices-title`);
</script>

<aside class="notices" aria-labelledby={headingId} data-testid="{testidPrefix}-notices">
	<h2 class="notices-title" id={headingId}>
		<span class="material-symbols" aria-hidden="true">health_and_safety</span>
		{m('parks.noticesTitle')}
	</h2>
	<ul>
		<li data-testid="{testidPrefix}-safety">{m('parks.safetyNotice')}</li>
		{#if sharedUse}
			<li data-testid="{testidPrefix}-shared-use">{m(SHARED_USE_NOTE[sharedUse])}</li>
		{/if}
		{#if isLongCourse(distanceM)}
			<li data-testid="{testidPrefix}-long">{m('parks.longCourseNotice')}</li>
		{/if}
		<li class="quiet" data-testid="{testidPrefix}-times">{m('parks.timesNotEventResults')}</li>
		<li class="quiet" data-testid="{testidPrefix}-not-affiliated">{m('parks.notAffiliated')}</li>
	</ul>
</aside>

<style>
	.notices {
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-inline-start: 4px solid var(--color-warning);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		text-align: start;
	}
	.notices-title {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin: 0 0 var(--space-sm);
		font-size: 0.95rem;
		font-weight: 600;
	}
	.notices-title .material-symbols {
		font-size: 1.2rem;
		color: var(--color-warning-text);
	}
	ul {
		margin: 0;
		padding-inline-start: 1.1rem;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		font-size: 0.875rem;
		line-height: 1.5;
		color: var(--color-text);
	}
	.quiet {
		color: var(--color-text-secondary);
	}
</style>
