<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';
	import type { ParkCourseWithPark } from '#lib/core/data.ts';
	import { regionSlug } from '#lib/parks/park_courses.ts';
	import { AGENCY_LABEL, labelKey } from '#lib/parks/park_labels.ts';
	import { fmtCourseDistanceRange } from '#lib/parks/course_distance_format.ts';
	import ParkCourseLinesThumb from '#lib/components/parks/ParkCourseLinesThumb.svelte';
	import type { TrackPoint } from '#lib/types.ts';

	// One park as a card that opens its page: the course lines, the agency, and
	// how many courses at what distances. `courses` is empty while the course
	// read is out or after it failed, which leaves the name and agency.
	let { park, courses }: { park: ParkCourseWithPark['park']; courses: readonly ParkCourseWithPark[] } = $props();

	const agencyKey = $derived(labelKey(AGENCY_LABEL, park.agency));
	const range = $derived(fmtCourseDistanceRange(courses.map((c) => c.segment.distance_m)));
	const lines = $derived<TrackPoint[][]>(
		courses.map((c) => c.segment.waypoints.map((w) => ({ lat: Number(w.lat), lng: Number(w.lng) }))),
	);
</script>

<a href="/parks/{regionSlug(park.region_code)}/{park.slug}" class="park-card" data-testid="park-card">
	<span class="thumb" aria-hidden="true">
		{#if lines.some((l) => l.length >= 2)}
			<ParkCourseLinesThumb {lines} />
		{:else}
			<span class="material-symbols thumb-icon">park</span>
		{/if}
	</span>
	<span class="park-text">
		<span class="park-name">{park.name}</span>
		{#if agencyKey}<span class="park-agency">{m(agencyKey)}</span>{/if}
		{#if courses.length > 0}
			<span class="park-facts" data-testid="park-card-facts">
				{m('parks.courseCount', { n: courses.length })}{#if range}&nbsp;·&nbsp;{range}{/if}
			</span>
		{/if}
	</span>
</a>

<style>
	.park-card {
		display: flex;
		flex-direction: column;
		height: 100%;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		text-decoration: none;
		overflow: hidden;
	}
	.park-card:hover,
	.park-card:focus-visible {
		border-color: var(--color-primary);
	}
	.thumb {
		display: flex;
		align-items: center;
		justify-content: center;
		aspect-ratio: 2 / 1;
		background: var(--color-fill-subtle);
	}
	.thumb-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
	}
	.park-text {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		padding: var(--space-sm) var(--space-md) var(--space-md);
		min-width: 0;
	}
	.park-name {
		font-weight: 600;
		font-size: 1.05rem;
	}
	.park-agency {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
	}
	.park-facts {
		margin-top: var(--space-xs);
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
</style>
