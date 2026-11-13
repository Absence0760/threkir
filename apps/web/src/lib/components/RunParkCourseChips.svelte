<script lang="ts">
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { currentLocale, m } from '#lib/i18n/store.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import { fetchRunParkCourseTimes } from '#lib/core/data.ts';
	import { boardPeriodParam, regionSlug, type RunParkCourseTime } from '#lib/parks/park_courses.ts';
	import { monthName } from '#lib/format/calendar.ts';

	interface Props {
		runId: string;
		runOwnerId: string;
		/// Bumped by the page when run detail's own scorer has written this
		/// run's efforts, so a course timed during this view shows up.
		refresh?: number;
	}
	let { runId, runOwnerId, refresh = 0 }: Props = $props();

	const isOwner = $derived(auth.user?.id === runOwnerId);

	let times = $state<RunParkCourseTime[]>([]);
	let failed = $state(false);
	let loading = $state(false);

	async function load() {
		loading = true;
		failed = false;
		try {
			times = await fetchRunParkCourseTimes(runId);
		} catch (e) {
			console.warn('run park course times read failed', e);
			failed = true;
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		void refresh;
		if (isOwner) void load();
	});

	/// The course on the effort's month board, the place the chip names first.
	function href(t: RunParkCourseTime): string {
		const period = boardPeriodParam({ kind: 'month', season: t.season, month: t.month });
		return `/parks/${regionSlug(t.region_code)}/${t.park_slug}/${t.course_slug}?period=${period}`;
	}

	/// "#2 in November, #9 in 2026": the place on the effort's month board
	/// where the park is, then on its season's, each when it holds one.
	function rank(t: RunParkCourseTime): string | null {
		const locale = currentLocale();
		const nf = new Intl.NumberFormat(locale, { useGrouping: false });
		const month = monthName(t.month - 1, locale);
		if (t.month_rank != null && t.season_rank != null) {
			return m('runDetail.parkCourseRanks', {
				monthRank: nf.format(t.month_rank),
				month,
				seasonRank: nf.format(t.season_rank),
				season: nf.format(t.season),
			});
		}
		if (t.month_rank != null) return m('runDetail.parkCourseMonthRank', { rank: nf.format(t.month_rank), month });
		if (t.season_rank != null) {
			return m('runDetail.parkCourseRank', { rank: nf.format(t.season_rank), season: nf.format(t.season) });
		}
		return null;
	}
</script>

{#if isOwner}
	{#if failed && !loading}
		<p class="park-course-error" role="status" data-testid="run-park-courses-error">
			<span>{m('runDetail.parkCoursesLoadFailed')}</span>
			<button type="button" class="retry" onclick={load}>{m('runs.retry')}</button>
		</p>
	{:else if times.length > 0}
		<ul class="park-course-chips" aria-label={m('runDetail.parkCourses')} data-testid="run-park-courses">
			{#each times as t (t.effort_id)}
				<li>
					<a class="park-course-chip" href={href(t)} data-testid="run-park-course-chip">
						<span class="material-symbols" aria-hidden="true">park</span>
						<span class="name">{t.course_name}</span>
						<span class="time">{formatDuration(t.time_seconds)}</span>
						{#if rank(t)}
							<span class="rank">{rank(t)}</span>
						{/if}
					</a>
				</li>
			{/each}
		</ul>
	{/if}
{/if}

<style>
	.park-course-chips {
		list-style: none;
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin: 0;
		padding: var(--space-sm) 0;
	}
	.park-course-chip {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		min-height: 2.75rem;
		padding: 0.35rem 0.8rem;
		background: var(--color-bg-tertiary);
		border-radius: 999px;
		font-size: 0.85rem;
		color: var(--color-text);
		text-decoration: none;
		max-width: 100%;
		min-width: 0;
	}
	.park-course-chip:hover,
	.park-course-chip:focus-visible {
		background: var(--color-primary-light);
	}
	.park-course-chip .material-symbols {
		font-size: 0.95rem;
		color: var(--color-success-text);
		flex-shrink: 0;
	}
	.name {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		min-width: 0;
	}
	.time {
		font-variant-numeric: tabular-nums;
		flex-shrink: 0;
	}
	.rank {
		color: var(--color-text-secondary);
		flex-shrink: 0;
	}
	.park-course-error {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin: var(--space-sm) 0;
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
	}
	.retry {
		background: transparent;
		border: 1px solid var(--color-border);
		border-radius: 999px;
		padding: 0.2rem 0.7rem;
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
	}
</style>
