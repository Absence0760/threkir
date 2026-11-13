<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { activeFormatLocale } from '#lib/format/time.ts';
	import { fmtKm, fmtPace } from '#lib/format/units.svelte.ts';
	import { m as t } from '#lib/i18n/store.svelte.ts';
	import type { YearInRunningRecap } from '#lib/runs/recap.ts';
	import { RECAP_SITE, recapActiveMonths, recapBadgeText } from '#lib/share/recap_card_text.ts';
	import { formatHoursMinutes } from '#lib/format/time.ts';
	import type { RecapSlideFormat } from '#lib/share/recap_slideshow.ts';
	import type { VideoEncoderPlan } from '#lib/video/video_encoder.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';

	interface Props {
		recap: YearInRunningRecap;
		/** Uppercase eyebrow over the hero (e.g. "My 2026 in running"). */
		kicker: string;
		/** Closing-section CTA label (e.g. "Share my 2026"). */
		shareLabel: string;
		onshare: () => void;
		/** Optional 9:16 story image share, shown beside the square one. */
		onsharestory?: (() => void) | null;
		/** Optional "publish a public link" action shown alongside the image share. */
		onpublish?: (() => void) | null;
		publishing?: boolean;
		/// Offers the 9:16 slideshow video (decisions § 2269). `autoStart` is
		/// the phone's Video option arriving with `?video=1`.
		video?: { title: string; fileStem: string; autoStart?: boolean } | null;
		/// The parks the owner ran courses in this period (`recapParkSummary`),
		/// owner pages only: a published snapshot carries the counts, never a park.
		parks?: { parkId: string; name: string; regionCode: string; courseCount: number }[];
	}

	let {
		recap,
		kicker,
		shareLabel,
		onshare,
		onsharestory = null,
		onpublish = null,
		publishing = false,
		video = null,
		parks = [],
	}: Props = $props();

	type VideoState =
		| { step: 'idle' }
		| { step: 'rendering'; progress: number }
		| { step: 'ready'; blob: Blob; url: string };

	/// undefined while the browser is being asked; null when it can encode
	/// nothing, which hides the action behind a note rather than a dead button.
	let encoderPlan = $state<VideoEncoderPlan | null | undefined>(undefined);
	let videoState = $state<VideoState>({ step: 'idle' });
	let videoAbort: AbortController | null = null;

	onMount(async () => {
		if (!video) return;
		try {
			const { pickVideoEncoder } = await import('#lib/video/encode_video.ts');
			encoderPlan = await pickVideoEncoder();
		} catch (e) {
			console.warn('recap: no video encoder', e);
			encoderPlan = null;
		}
		if (encoderPlan && video.autoStart) void makeVideo();
	});

	onDestroy(() => discardVideo());

	function slideFormat(): RecapSlideFormat {
		const locale = activeFormatLocale();
		return {
			t,
			kicker,
			distance: (meters) => fmtKm(meters),
			pace: (s) => fmtPace(s),
			weekOf: fmtWeekStart,
			monthName: (mo) => new Date(recap.year, mo - 1, 1).toLocaleDateString(locale, { month: 'long' }),
			monthLetter: (mo) => new Date(recap.year, mo - 1, 1).toLocaleDateString(locale, { month: 'narrow' }),
			count: (n) => n.toLocaleString(locale),
			url: RECAP_SITE,
		};
	}

	async function makeVideo() {
		const plan = encoderPlan;
		if (!plan || !video || videoState.step === 'rendering') return;
		discardVideo();
		const abort = new AbortController();
		videoAbort = abort;
		videoState = { step: 'rendering', progress: 0 };
		try {
			const { renderRecapSlideshow } = await import('#lib/share/recap_slideshow_video.ts');
			const blob = await renderRecapSlideshow({
				recap,
				format: slideFormat(),
				plan,
				signal: abort.signal,
				onprogress: (f) => {
					if (videoAbort === abort) videoState = { step: 'rendering', progress: f };
				},
			});
			if (videoAbort !== abort) return;
			videoState = { step: 'ready', blob, url: URL.createObjectURL(blob) };
		} catch (e) {
			if (videoAbort !== abort) return;
			videoState = { step: 'idle' };
			if ((e as { name?: string })?.name === 'AbortError') return;
			console.error('recap: video export failed', e);
			showToast(t('recap.videoFailed'), 'error');
		} finally {
			if (videoAbort === abort) videoAbort = null;
		}
	}

	function discardVideo() {
		videoAbort?.abort();
		videoAbort = null;
		if (videoState.step === 'ready') URL.revokeObjectURL(videoState.url);
		videoState = { step: 'idle' };
	}

	async function saveVideo() {
		if (videoState.step !== 'ready' || !video) return;
		const { blob } = videoState;
		try {
			const { deliverVideo } = await import('#lib/video/encode_video.ts');
			const how = await deliverVideo(blob, video.fileStem, video.title);
			if (how === 'downloaded') showToast(t('recap.videoSaved'), 'success');
		} catch (e) {
			if ((e as { name?: string })?.name === 'AbortError') return;
			console.error('recap: video share failed', e);
			showToast(t('recap.videoFailed'), 'error');
		}
	}

	function fmtWeekStart(iso: string): string {
		const d = new Date(iso + 'T00:00:00');
		return d.toLocaleDateString(activeFormatLocale(), { day: 'numeric', month: 'short' });
	}

	function maxMonthlyDistance(monthly: YearInRunningRecap['monthly']): number {
		return Math.max(1, ...monthly.map((m) => m.distanceM));
	}

	const MONTH_LABELS = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
</script>

<header class="hero">
	<p class="kicker">{kicker}</p>
	<h1 class="bignum">{fmtKm(recap.totalDistanceM)}</h1>
	<p class="subhead">
		{t('recap.acrossRuns', { n: recap.runCount })}
	</p>
	<div class="hero-meta">
		<span class="hero-meta-item">
			<span class="material-symbols">timer</span>
			{t('recap.onFoot', { time: formatHoursMinutes(recap.totalDurationS) })}
		</span>
		<span class="hero-meta-divider" aria-hidden="true"></span>
		<span class="hero-meta-item">
			<span class="material-symbols">terrain</span>
			{t('recap.climbed', { meters: Math.round(recap.totalElevationM).toLocaleString() })}
		</span>
		{#if recap.month == null}
			<span class="hero-meta-divider" aria-hidden="true"></span>
			<span class="hero-meta-item">
				<span class="material-symbols">calendar_month</span>
				{t(
					'recap.activeInMonths',
					{ n: recapActiveMonths(recap) }
				)}
			</span>
		{/if}
	</div>
	<div class="hero-actions">
		<button type="button" class="btn share-btn" onclick={onshare}>
			<span class="material-symbols">ios_share</span>
			{t('recap.shareRecap')}
		</button>
		{#if onsharestory}
			<button type="button" class="btn share-btn" data-testid="recap-share-story" onclick={onsharestory}>
				<span class="material-symbols" aria-hidden="true">smartphone</span>
				{t('recap.shareStory')}
			</button>
		{/if}
		{#if onpublish}
			<button
				type="button"
				class="btn publish-btn"
				onclick={onpublish}
				disabled={publishing}
			>
				<span class="material-symbols">link</span>
				{publishing ? t('recap.publishing') : t('recap.publishAndShare')}
			</button>
		{/if}
		{#if video && encoderPlan && videoState.step === 'idle'}
			<button type="button" class="btn share-btn" data-testid="recap-make-video" onclick={makeVideo}>
				<span class="material-symbols" aria-hidden="true">movie</span>
				{t('recap.makeVideo')}
			</button>
		{/if}
	</div>
	{#if video && encoderPlan === null}
		<p class="publish-note" data-testid="recap-video-unsupported">{t('recap.videoUnsupported')}</p>
	{:else if videoState.step === 'rendering'}
		<div class="video-row">
			<p role="status" data-testid="recap-video-progress">
				{t('recap.videoRendering', { percent: Math.floor(videoState.progress * 100) })}
			</p>
			<button type="button" class="btn share-btn" onclick={discardVideo}>{t('common.cancel')}</button>
		</div>
	{:else if videoState.step === 'ready'}
		<div class="video-row">
			<!-- svelte-ignore a11y_media_has_caption -->
			<video
				class="video-preview"
				src={videoState.url}
				controls
				muted
				playsinline
				aria-label={t('recap.videoPreviewLabel')}
				data-testid="recap-video-preview"
			></video>
			<p role="status">{t('recap.videoReady')}</p>
			<button type="button" class="btn share-btn" data-testid="recap-save-video" onclick={saveVideo}>
				<span class="material-symbols" aria-hidden="true">ios_share</span>
				{t('recap.videoSave')}
			</button>
			<button type="button" class="btn share-btn" onclick={discardVideo}>{t('recap.videoDiscard')}</button>
		</div>
	{/if}
	{#if onpublish}
		<p class="publish-note">{t('recap.makePublicExplain')}</p>
	{/if}
</header>

<section class="cards">
	<div class="card">
		<span class="card-label">{t('recap.longestRun')}</span>
		<span class="card-value">{fmtKm(recap.longestRunM)}</span>
		<span class="card-sub">{t('recap.singleOuting')}</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.fastestPace')}</span>
		<span class="card-value">{fmtPace(recap.fastestPaceSecPerKm)}</span>
		<span class="card-sub">{t('recap.fastestPaceSub')}</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.bestStreak')}</span>
		<span class="card-value">{recap.bestStreakDays} <small>{t('recap.days')}</small></span>
		<span class="card-sub">{t('recap.consecutiveRunDays')}</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.topWeek')}</span>
		<span class="card-value">{fmtKm(recap.topWeek?.distanceM ?? 0)}</span>
		<span class="card-sub">
			{#if recap.topWeek}
				{t('recap.weekOf', { date: fmtWeekStart(recap.topWeek.weekStart) })}
			{:else}
				{t('recap.noWeeklyData')}
			{/if}
		</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.routesRun')}</span>
		<span class="card-value">{recap.uniqueRouteCount}</span>
		<span class="card-sub">{t('recap.distinctSavedRoutes')}</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.earliestStart')}</span>
		<span class="card-value">{recap.earliestStartLocal ?? '—'}</span>
		<span class="card-sub">{t('recap.localTime')}</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.personalRecords')}</span>
		<span class="card-value">{recap.personalRecordCount}</span>
		<span class="card-sub">{t('recap.setThisYear')}</span>
	</div>
	<div class="card">
		<span class="card-label">{t('recap.photos')}</span>
		<span class="card-value">{recap.photoCount}</span>
		<span class="card-sub">{t('recap.momentsCaptured')}</span>
	</div>
	{#if recap.parkCourseCount > 0}
		<div class="card" data-testid="recap-park-courses">
			<span class="card-label">{t('recap.parkCourses')}</span>
			<span class="card-value">{recap.parkCourseCount}</span>
			<span class="card-sub">{t('recap.parkCoursesSub', { n: recap.parkCount })}</span>
		</div>
	{/if}
</section>

{#if parks.length > 0}
	<section class="badges" data-testid="recap-parks">
		<header class="badges-head">
			<h2>{t('recap.parksHeading')}</h2>
		</header>
		<ul class="park-list">
			{#each parks as p (p.parkId)}
				<li>
					<span class="material-symbols" aria-hidden="true">park</span>
					<span class="park-name">{p.name}</span>
					<span class="badge-detail">{t('recap.parkCourseCount', { n: p.courseCount })}</span>
				</li>
			{/each}
		</ul>
	</section>
{/if}

{#if recap.badges.length > 0}
	<section class="badges">
		<header class="badges-head">
			<h2>{t('recap.trophies')}</h2>
			<span class="badges-meta">
				{t('recap.earnedInYear', { n: recap.badges.length, year: recap.year })}
			</span>
		</header>
		<div class="badge-grid">
			{#each recap.badges as b (b.id)}
				{@const text = recapBadgeText(b, t)}
				<div class="badge">
					<span class="badge-icon material-symbols" aria-hidden="true">{b.icon}</span>
					<span class="badge-label">{text.label}</span>
					{#if text.detail}<span class="badge-detail">{text.detail}</span>{/if}
				</div>
			{/each}
		</div>
	</section>
{/if}

{#if recap.month == null}
	<section class="month-chart">
		<header class="month-chart-head">
			<h2>{t('recap.distanceByMonth')}</h2>
			<span class="month-chart-meta">
				{t('recap.peak', { distance: fmtKm(maxMonthlyDistance(recap.monthly)) })}
			</span>
		</header>
		<div class="bars">
			{#each recap.monthly as m (m.month)}
				{@const max = maxMonthlyDistance(recap.monthly)}
				{@const pct = (m.distanceM / max) * 100}
				<div
					class="bar-col"
					title={t('recap.barTitle', {
						distance: fmtKm(m.distanceM),
						n: m.runCount
					})}
				>
					<span class="bar-track">
						<span class="bar" class:bar-empty={m.runCount === 0} style="height: {pct}%"></span>
					</span>
					<span class="bar-label">{MONTH_LABELS[m.month - 1]}</span>
				</div>
			{/each}
		</div>
	</section>
{/if}

<section class="closing">
	<h2>{t('recap.wrapItUp')}</h2>
	<p>
		{t('recap.closingBody', { distance: fmtKm(recap.totalDistanceM) })}
	</p>
	<button type="button" class="btn btn-primary" onclick={onshare}>
		<span class="material-symbols">ios_share</span>
		{shareLabel}
	</button>
</section>

<style>
	.hero {
		position: relative;
		padding: var(--space-2xl) var(--space-xl);
		text-align: center;
		background:
			radial-gradient(
				circle at 80% 20%,
				color-mix(in srgb, var(--color-accent-orange) 30%, transparent),
				transparent 55%
			),
			radial-gradient(
				circle at 15% 90%,
				color-mix(in srgb, var(--color-secondary) 28%, transparent),
				transparent 55%
			),
			linear-gradient(
				135deg,
				var(--color-primary) 0%,
				color-mix(in srgb, var(--color-primary) 70%, #000) 100%
			);
		color: var(--color-bg);
		border-radius: var(--radius-xl);
		margin-bottom: var(--space-xl);
		overflow: hidden;
	}
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.12em;
		font-size: 0.78rem;
		font-weight: 700;
		opacity: 0.85;
		margin: 0 0 var(--space-md);
	}
	.bignum {
		font-size: clamp(3.5rem, 9vw, 6rem);
		font-weight: 900;
		margin: 0;
		line-height: 0.95;
		letter-spacing: -0.02em;
	}
	.subhead {
		font-size: 1.05rem;
		opacity: 0.92;
		margin: var(--space-sm) 0 var(--space-lg);
	}
	.hero-meta {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: center;
		gap: var(--space-sm) var(--space-md);
		padding: var(--space-sm) var(--space-lg);
		background: rgba(255, 255, 255, 0.12);
		border-radius: 999px;
		margin-bottom: var(--space-lg);
	}
	.hero-meta-item {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.9rem;
		font-weight: 600;
	}
	.hero-meta-item .material-symbols {
		font-size: 1.1rem;
	}
	.hero-meta-divider {
		width: 1px;
		height: 1rem;
		background: rgba(255, 255, 255, 0.25);
	}
	.hero-actions {
		display: inline-flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		justify-content: center;
	}
	.share-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: var(--color-bg);
		color: var(--color-primary);
		font-weight: 700;
		border-color: transparent;
		box-shadow: var(--shadow-md);
	}
	.share-btn:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-lg);
	}
	.share-btn .material-symbols,
	.publish-btn .material-symbols {
		font-size: 1.1rem;
	}
	.publish-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: rgba(255, 255, 255, 0.16);
		color: var(--color-bg);
		font-weight: 700;
		border-color: rgba(255, 255, 255, 0.4);
	}
	.publish-btn:hover:not(:disabled) {
		background: rgba(255, 255, 255, 0.24);
	}
	.video-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
	.video-row p {
		margin: 0;
		flex-basis: 100%;
		font-weight: 600;
	}
	.video-preview {
		width: min(12rem, 60vw);
		aspect-ratio: 9 / 16;
		border-radius: var(--radius-lg);
		background: var(--color-bg-secondary);
	}
	.publish-note {
		margin: var(--space-sm) auto 0;
		max-width: 30rem;
		font-size: 0.8rem;
		opacity: 0.85;
		line-height: 1.4;
	}

	.cards {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(15rem, 100%), 1fr));
		gap: var(--space-md);
		margin-bottom: var(--space-xl);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		transition: transform var(--transition-fast),
			border-color var(--transition-fast);
	}
	.card:hover {
		transform: translateY(-2px);
		border-color: color-mix(in srgb, var(--color-primary) 35%, var(--color-border));
	}
	.card-label {
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
	}
	.card-value {
		font-size: 1.85rem;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
		letter-spacing: -0.01em;
	}
	.card-value small {
		font-size: 0.95rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.card-sub {
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
		margin-top: var(--space-2xs);
	}

	.month-chart {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}
	.month-chart-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.month-chart h2 {
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.month-chart-meta {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.bars {
		display: grid;
		grid-template-columns: repeat(12, minmax(0, 1fr));
		gap: 0.4rem;
		align-items: end;
		height: 13rem;
	}
	.bar-col {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: end;
		height: 100%;
		gap: 0.4rem;
	}
	.bar-track {
		width: 100%;
		height: 100%;
		background: var(--color-bg-secondary);
		border-radius: var(--radius-sm);
		display: flex;
		align-items: flex-end;
		overflow: hidden;
	}
	.bar {
		width: 100%;
		min-height: 2px;
		background: linear-gradient(180deg, var(--color-secondary), var(--color-primary));
		border-radius: var(--radius-sm);
	}
	.bar-empty {
		background: transparent;
		min-height: 0;
	}
	.bar-label {
		font-size: 0.75rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}

	.badges {
		margin-bottom: var(--space-xl);
	}
	.badges-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
		margin-bottom: var(--space-md);
	}
	.badges h2 {
		font-size: 0.78rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-secondary);
		margin: 0;
	}
	.badges-meta {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		font-variant-numeric: tabular-nums;
	}
	.badge-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(11rem, 100%), 1fr));
		gap: var(--space-md);
	}
	.badge {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 0.3rem;
		transition: transform var(--transition-fast),
			border-color var(--transition-fast);
	}
	.badge:hover {
		transform: translateY(-2px);
		border-color: color-mix(in srgb, var(--color-accent-orange) 45%, var(--color-border));
	}
	.badge-icon {
		font-size: 2rem;
		color: var(--color-accent-orange-text);
		background: color-mix(in srgb, var(--color-accent-orange) 14%, transparent);
		width: 3.25rem;
		height: 3.25rem;
		display: grid;
		place-items: center;
		border-radius: 999px;
		margin-bottom: var(--space-2xs);
	}
	.badge-label {
		font-weight: 800;
		font-size: 0.98rem;
	}
	.badge-detail {
		font-size: 0.8rem;
		color: var(--color-text-tertiary);
		line-height: 1.35;
	}

	.park-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: var(--space-sm);
	}
	.park-list li {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-sm) var(--space-md);
	}
	.park-list .material-symbols {
		color: var(--color-accent-orange-text);
	}
	.park-name {
		font-weight: 700;
		flex: 1;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	.closing {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-xl);
		text-align: center;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
	}
	.closing h2 {
		margin: 0;
		font-size: 1.4rem;
		font-weight: 800;
	}
	.closing p {
		margin: 0 0 var(--space-sm);
		color: var(--color-text-secondary);
		max-width: 36rem;
		line-height: 1.5;
	}
	.closing .material-symbols {
		font-size: 1.1rem;
	}
	.closing .btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
</style>
