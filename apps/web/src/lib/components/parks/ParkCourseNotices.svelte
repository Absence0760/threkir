<script lang="ts">
	// What a runner must know before setting off on a park course, in one
	// callout (issue #1352): a few plain lines, safety first (follow the
	// course line and pass every checkpoint), the give-way note when an
	// organised group shares the paths (decisions § 2460), the park-permit line
	// every course carries (a group or an event may need the park's permit),
	// then only the lines the course's data supports: a ford, a paved shared
	// trail, a park's closing time (courseNotices).
	// The required notices (a time trial, not a race; times are not event
	// results; not affiliated with the park) follow as one smaller line.
	// Each keeps the test id it had when they were separate pieces of fine
	// print (decisions § 2582).
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import { courseNotices, type CourseNoticeKey, type SharedUse } from '#lib/parks/park_courses.ts';
	import type { RouteGuide } from '#lib/parks/route_guide.ts';

	let {
		distanceM,
		sharedUse,
		surface,
		parkKind,
		guide,
		testidPrefix,
	}: {
		distanceM: number;
		sharedUse: SharedUse | null;
		surface: string | null;
		parkKind: 'park' | 'trail';
		guide: RouteGuide | null;
		testidPrefix: 'park-course' | 'share-course';
	} = $props();

	// Only what the course's data supports (courseNotices, decisions § 2582).
	const NOTICE: Record<CourseNoticeKey, { key: MessageKey; id: string }> = {
		ford: { key: 'parks.notice.ford', id: 'ford' },
		pavedTrail: { key: 'parks.notice.pavedTrail', id: 'paved-trail' },
		longTrail: { key: 'parks.notice.longTrail', id: 'long' },
		parkHours: { key: 'parks.noticeParkHours', id: 'hours' },
		parkHoursLong: { key: 'parks.notice.parkHoursLong', id: 'long' },
	};
	const lines = $derived(courseNotices({ parkKind, surface, distanceM, guide }));

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
		<li data-testid="{testidPrefix}-group-permit">{m('parks.groupPermitNotice')}</li>
		{#each lines as line (line)}
			<li data-testid="{testidPrefix}-{NOTICE[line].id}">{m(NOTICE[line].key)}</li>
		{/each}
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
