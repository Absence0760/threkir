<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import SharePageShell from '#lib/components/SharePageShell.svelte';
	import { formatDistance } from '#lib/format/units.svelte.ts';
	import { formatDuration } from '#lib/format/time.ts';
	import { goalEventLabel, planLengthLabel } from '#lib/training/goal_event_label.ts';
	import { planPhaseLabel, workoutKindLabel } from '#lib/training/workout_labels.ts';
	import type { SharedPlanWorkout } from '#lib/share/share_plan_lookup.ts';
	import {
		buildPlanJsonLd,
		buildPlanShareCanonical,
		buildPlanShareDescription,
		buildPlanShareTitle,
		planAuthorCredit
	} from '#lib/share/share_plan_meta.ts';
	import { shareRefFromSearch, withShareRef } from '#lib/share/share_ref.ts';
	import { recordShareView } from '#lib/share/share_attribution.ts';

	let { data } = $props();

	let plan = $derived(data.plan);
	let credit = $derived(planAuthorCredit(plan?.author));
	let title = $derived(buildPlanShareTitle(plan));
	let description = $derived(buildPlanShareDescription(plan));
	let canonicalUrl = $derived(buildPlanShareCanonical(data.siteUrl, data.id));
	let jsonLd = $derived(buildPlanJsonLd(plan, { id: data.id, base: data.siteUrl }));

	// The in-app preview is where a signed-in runner picks a start date and
	// clones; a signed-out one signs up first and lands there afterwards.
	// The link's ref rides along, so a copy started there (after sign-up if
	// need be) is attributed to it (decisions § 2268).
	let startHref = $derived(
		withShareRef(`/plans/library/${data.id}`, shareRefFromSearch(page.url.search))
	);
	let returnTo = $derived(encodeURIComponent(startHref));

	onMount(() => {
		if (data.plan) void recordShareView('plan', data.id);
	});

	function runs(workouts: SharedPlanWorkout[]): SharedPlanWorkout[] {
		return workouts.filter((w) => w.kind !== 'rest');
	}

	function weekSummary(workouts: SharedPlanWorkout[]): string {
		const list = runs(workouts);
		const metres = list.reduce((sum, w) => sum + (w.target_distance_m ?? 0), 0);
		const count = m('planLibrary.previewWeekRuns', { n: list.length });
		return metres > 0 ? `${count} · ${formatDistance(metres)}` : count;
	}

	function workoutTarget(w: SharedPlanWorkout): string | null {
		if (w.target_distance_m != null && w.target_distance_m > 0) {
			return formatDistance(w.target_distance_m);
		}
		if (w.target_duration_seconds != null && w.target_duration_seconds > 0) {
			return formatDuration(w.target_duration_seconds);
		}
		return null;
	}
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="article" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content="/og-default.png" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content="/og-default.png" />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<SharePageShell appHref={startHref}>
	{#if plan}
		<section class="hero">
			<p class="kicker">{m('sharePlan.heroKicker')}</p>
			<h1>{plan.name}</h1>
			<p class="subtitle">
				{goalEventLabel(m, formatDistance, plan.goal_event, plan.goal_distance_m)}
				· {planLengthLabel(m, plan.weeks.length, plan.days_per_week)}
			</p>
			{#if credit}
				<p class="author" data-testid="share-plan-author">{m('planLibrary.byAuthor', { author: credit })}</p>
			{/if}
			<div class="start">
				{#if auth.loggedIn}
					<a class="btn btn-primary" href={startHref} data-testid="share-plan-start">
						{m('sharePlan.start')}
					</a>
				{:else}
					<a
						class="btn btn-primary"
						href="/login?signup=1&return_to={returnTo}"
						data-testid="share-plan-start"
					>
						{m('sharePlan.start')}
					</a>
					<a class="btn btn-outline" href="/login?return_to={returnTo}">{m('sharePlan.signIn')}</a>
				{/if}
			</div>
			{#if !auth.loggedIn}
				<p class="start-sub">{m('sharePlan.startSub')}</p>
			{/if}
		</section>

		<main class="content" id="main-content">
			<section class="weeks">
				<h2>{m('planLibrary.previewWeeks')}</h2>
				<ol class="week-list" data-testid="share-plan-weeks">
					{#each plan.weeks as week (week.week_index)}
						<li class="week">
							<details>
								<summary>
									<span class="week-label">
										{m('planLibrary.previewWeek', { n: week.week_index + 1 })}
										{#if week.phase}<span class="phase">{planPhaseLabel(week.phase)}</span>{/if}
									</span>
									<span class="week-count">{weekSummary(week.workouts)}</span>
								</summary>
								<ul class="workouts">
									{#each runs(week.workouts) as w, i (`${w.day}-${i}`)}
										<li>
											<span class="day">{m('sharePlan.day', { n: w.day + 1 })}</span>
											<span class="kind">{workoutKindLabel(w.kind)}</span>
											{#if workoutTarget(w)}<span class="target">{workoutTarget(w)}</span>{/if}
										</li>
									{/each}
								</ul>
							</details>
						</li>
					{/each}
				</ol>
			</section>
		</main>
	{:else}
		<main class="content" id="main-content">
			<div class="notfound-card">
				<p class="kicker">{m('shareSession.notFoundKicker')}</p>
				<h1>{m('sharePlan.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('sharePlan.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/plans/library">{m('sharePlan.browseLibrary')}</a>
					<a class="btn btn-outline" href="/">{m('shareSession.goToThrekir')}</a>
				</div>
			</div>
		</main>
	{/if}
</SharePageShell>

<style>
	.hero {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-xl) var(--space-md) var(--space-md);
		text-align: center;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.1em;
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
	}
	.hero h1 {
		font-size: 2rem;
		font-weight: 800;
		margin: 0 0 var(--space-sm);
		line-height: 1.15;
		overflow-wrap: anywhere;
	}
	.subtitle,
	.author {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-xs);
	}
	.start {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
		margin-top: var(--space-md);
	}
	.start-sub {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: var(--space-sm) auto 0;
		max-width: 30rem;
		line-height: 1.5;
	}
	.content {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
	}
	.weeks h2 {
		margin: 0 0 var(--space-sm);
		font-size: 1.1rem;
		font-weight: 600;
	}
	.week-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.week details {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.week summary {
		display: flex;
		justify-content: space-between;
		gap: var(--space-sm);
		flex-wrap: wrap;
		padding: var(--space-sm) var(--space-md);
		cursor: pointer;
		min-height: 44px;
		align-items: center;
	}
	.week-label {
		font-weight: 600;
		display: inline-flex;
		gap: var(--space-xs);
		align-items: baseline;
		flex-wrap: wrap;
	}
	.phase {
		font-size: 0.8rem;
		font-weight: 500;
		color: var(--color-text-secondary);
	}
	.week-count {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.workouts {
		list-style: none;
		margin: 0;
		padding: 0 var(--space-md) var(--space-sm);
		display: flex;
		flex-direction: column;
	}
	.workouts li {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
		padding: var(--space-2xs) 0;
		border-top: 1px solid var(--color-border);
	}
	.day {
		color: var(--color-text-tertiary);
		min-width: 4.5rem;
		font-variant-numeric: tabular-nums;
	}
	.kind {
		font-weight: 500;
	}
	.target {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.notfound-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl) var(--space-lg);
		margin-top: var(--space-xl);
		text-align: center;
	}
	.notfound-card h1 {
		font-size: 1.4rem;
		font-weight: 700;
		margin: 0 0 var(--space-sm);
	}
	.notfound-sub {
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		max-width: 28rem;
		margin: 0 auto var(--space-lg);
		line-height: 1.5;
	}
	.notfound-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
	@media (min-width: 48rem) {
		.hero {
			padding: var(--space-2xl) var(--space-xl) var(--space-lg);
		}
		.hero h1 {
			font-size: 2.5rem;
		}
		.content {
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
