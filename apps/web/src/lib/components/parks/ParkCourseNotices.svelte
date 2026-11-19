<script lang="ts">
	// What a runner must know before setting off on a park course, in one
	// callout (issue #1352): at most a couple of plain lines, safety first
	// (stay on the trail and pass every checkpoint), the give-way note when an
	// organised group shares the paths (decisions § 2460), then finish before
	// the park closes, or the long-course notice that says so with more.
	// The required notices (a time trial, not a race; times are not event
	// results; not affiliated with the park) follow as one smaller line.
	// Each keeps the test id it had when they were separate pieces of fine
	// print (decisions § 2581).
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
		{:else}
			<li data-testid="{testidPrefix}-hours">{m('parks.noticeParkHours')}</li>
		{/if}
	</ul>
	<p class="fine">
		<span data-testid="{testidPrefix}-open-trail">{m('parks.noticeOpenTrail')}</span>
		<span data-testid="{testidPrefix}-times">{m('parks.timesNotEventResults')}</span>
		<span data-testid="{testidPrefix}-not-affiliated">{m('parks.notAffiliated')}</span>
	</p>
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
		font-size: 0.95rem;
		line-height: 1.5;
		color: var(--color-text);
	}
	.fine {
		margin: var(--space-sm) 0 0;
		font-size: 0.78rem;
		line-height: 1.45;
		color: var(--color-text-secondary);
	}
</style>
