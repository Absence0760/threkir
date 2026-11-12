<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import SharePageShell from '#lib/components/SharePageShell.svelte';
	import { joinChallenge } from '#lib/core/data.ts';
	import {
		challengeWindowLabel,
		formatChallengeGoal
	} from '#lib/format/challenge_labels.svelte.ts';
	import { runnerHandle } from '#lib/social/runner_handle.ts';
	import {
		buildChallengeJsonLd,
		buildChallengeOgImageUrl,
		buildChallengeShareCanonical,
		buildChallengeShareDescription,
		buildChallengeShareTitle
	} from '#lib/share/share_challenge_meta.ts';
	import { shareRefFromSearch, withShareRef } from '#lib/share/share_ref.ts';
	import { attributeShareStart, recordShareView } from '#lib/share/share_attribution.ts';

	let { data } = $props();

	let title = $derived(buildChallengeShareTitle(data.challenge));
	let description = $derived(buildChallengeShareDescription(data.challenge));
	let canonicalUrl = $derived(buildChallengeShareCanonical(data.siteUrl, data.id));
	let ogImage = $derived(buildChallengeOgImageUrl(data.siteUrl, data.id));
	let jsonLd = $derived(buildChallengeJsonLd(data.challenge, { id: data.id, base: data.siteUrl }));

	let appHref = $derived(`/challenges/${data.id}`);
	// Back here, not to the in-app page: /share/* skips the onboarding gates,
	// so a brand-new account lands on this Join button rather than the wizard.
	// The link's ref rides through sign-up, so the join is attributed to it.
	let arrivedRef = $derived(shareRefFromSearch(page.url.search));
	let returnTo = $derived(
		encodeURIComponent(withShareRef(`/share/challenge/${data.id}`, arrivedRef))
	);
	let busy = $state(false);
	let joinFailed = $state(false);

	const handleLabels = {
		handle: (slug: string) => m('live.runnerHandle', { slug }),
		anonymous: m('checkpoint.anonymousRunner')
	};
	function leaderName(row: { user_id: string | null; display_name: string | null }): string {
		return row.display_name ?? runnerHandle(row.user_id, handleLabels);
	}

	onMount(() => {
		if (data.challenge) void recordShareView('challenge', data.id);
	});

	async function join() {
		if (busy || !data.challenge) return;
		busy = true;
		joinFailed = false;
		try {
			await joinChallenge(data.challenge.id);
			if (arrivedRef) await attributeShareStart('challenge', data.challenge.id, arrivedRef);
			goto(appHref);
		} catch (e) {
			console.error('share challenge join failed', e);
			joinFailed = true;
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>{title}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonicalUrl} />
	<meta property="og:title" content={title} />
	<meta property="og:description" content={description} />
	<meta property="og:type" content="website" />
	<meta property="og:url" content={canonicalUrl} />
	<meta property="og:site_name" content="Threkir" />
	<meta property="og:image" content={ogImage} />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content={ogImage} />
	{@html `<script type="application/ld+json">${jsonLd}</script>`}
</svelte:head>

<SharePageShell {appHref}>
	{#if data.challenge}
		<main class="hero" id="main-content" data-testid="share-challenge">
			<p class="kicker">
				{data.creatorName
					? m('shareChallenge.kickerBy', { name: data.creatorName })
					: m('shareChallenge.kicker')}
			</p>
			<h1>{data.challenge.title}</h1>
			<div class="chips">
				<span class="chip">{challengeWindowLabel(data.challenge)}</span>
				{#if data.challenge.goal_value != null}
					<span class="chip goal">
						{formatChallengeGoal(data.challenge.metric, data.challenge.goal_value)}
					</span>
				{/if}
				<span class="chip">
					{m('challengeJoin.participants', { n: data.challenge.participant_count })}
				</span>
			</div>
			{#if data.challenge.description}
				<p class="desc">{data.challenge.description}</p>
			{/if}
			<div class="hero-actions">
				{#if auth.loggedIn}
					<button
						type="button"
						class="btn btn-primary"
						onclick={join}
						disabled={busy}
						data-testid="share-challenge-join"
					>
						{busy ? m('challengeJoin.joining') : m('challengeJoin.join')}
					</button>
					<a class="btn btn-outline" href={appHref}>{m('challengeJoin.openChallenge')}</a>
				{:else}
					<a
						class="btn btn-primary"
						href="/login?signup=1&return_to={returnTo}"
						data-testid="share-challenge-signup"
					>
						{m('shareChallenge.joinSignedOut')}
					</a>
					<a class="btn btn-outline" href="/login?return_to={returnTo}">
						{m('clubJoin.signIn')}
					</a>
				{/if}
			</div>
			{#if joinFailed}
				<p class="error" role="alert">{m('challenges.joinFailed')}</p>
			{/if}

			{#if data.leaders.length > 0}
				<section class="board" aria-labelledby="share-challenge-board">
					<h2 id="share-challenge-board">{m('challenges.leaderboard')}</h2>
					<ol>
						{#each data.leaders as row (row.user_id ?? row.rank)}
							<li>
								<span class="rank">{row.rank}</span>
								<span class="name">{leaderName(row)}</span>
								<span class="value">{formatChallengeGoal(data.challenge.metric, row.value)}</span>
							</li>
						{/each}
					</ol>
				</section>
			{/if}
		</main>
	{:else}
		<main class="content" id="main-content">
			<div class="notfound-card">
				<p class="kicker">{m('shareRun.notFoundKicker')}</p>
				<h1>{m('shareChallenge.notFoundTitle')}</h1>
				<p class="notfound-sub">{m('shareChallenge.notFoundSub')}</p>
				<div class="notfound-actions">
					<a class="btn btn-primary" href="/login">{m('shareRun.signIn')}</a>
					<a class="btn btn-outline" href="/">{m('shareRun.goToThrekir')}</a>
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
	}
	.desc {
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		max-width: 34rem;
		margin: 0 auto;
		line-height: 1.5;
	}
	.hero-actions {
		margin-top: var(--space-md);
	}
	.chips {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-xs);
		margin: 0 0 var(--space-md);
	}
	.chip {
		padding: 0.2rem 0.6rem;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 600;
		background: var(--color-bg-secondary);
		color: var(--color-text-secondary);
	}
	.chip.goal {
		background: var(--color-primary-light);
		color: var(--color-primary);
	}
	.hero-actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: center;
		flex-wrap: wrap;
	}
	.error {
		color: var(--color-danger-text);
		font-size: 0.88rem;
		margin: var(--space-sm) 0 0;
	}
	.board {
		margin: var(--space-xl) auto 0;
		max-width: 28rem;
		text-align: start;
	}
	.board h2 {
		font-size: 1.1rem;
		margin: 0 0 var(--space-sm);
	}
	.board ol {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.board li {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
	}
	.rank {
		font-weight: 700;
		min-width: 1.5rem;
		color: var(--color-text-tertiary);
	}
	.name {
		flex: 1;
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.value {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.content {
		max-width: 48rem;
		margin: 0 auto;
		width: 100%;
		padding: var(--space-md);
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
	}
</style>
