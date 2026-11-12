<script lang="ts">
	// The landing page of a club verification's email proof (issue #1190 § 2,
	// decisions § 2398). The token rides in the URL fragment, so it reaches no
	// server log, and confirming takes a click: a mail scanner that opens the
	// link confirms nothing.
	import { onMount } from 'svelte';
	import { confirmClubVerificationEmail } from '#lib/core/data.ts';
	import { m } from '#lib/i18n/store.svelte.ts';

	type Phase = 'prompt' | 'working' | 'success' | 'failure' | 'missing';

	let token = $state<string | null>(null);
	let phase = $state<Phase>('prompt');
	let clubName = $state('');
	let clubSlug = $state<string | null>(null);
	// Prerendered: the button exists before Svelte wires it, so it stays
	// disabled until mount reads the fragment.
	let hydrated = $state(false);

	onMount(() => {
		const raw = new URLSearchParams(window.location.hash.replace(/^#/, '')).get('token');
		token = raw && /^[0-9a-f]{48}$/.test(raw) ? raw : null;
		if (!token) phase = 'missing';
		hydrated = true;
	});

	async function confirm() {
		if (!token) return;
		phase = 'working';
		try {
			const result = await confirmClubVerificationEmail(token);
			if (result.outcome === 'confirmed') {
				clubName = result.club_name ?? '';
				clubSlug = result.club_slug;
				phase = 'success';
				history.replaceState(null, '', window.location.pathname);
			} else {
				phase = 'failure';
			}
		} catch (e) {
			console.error('club verification confirm failed', e);
			phase = 'failure';
		}
	}

	const message = $derived(
		phase === 'prompt'
			? m('clubVerificationConfirm.prompt')
			: phase === 'working'
				? m('clubVerificationConfirm.working')
				: phase === 'success'
					? m('clubVerificationConfirm.success', { club: clubName })
					: phase === 'missing'
						? m('clubVerificationConfirm.missing')
						: m('clubVerificationConfirm.failure'),
	);
</script>

<svelte:head>
	<title>{m('clubVerificationConfirm.title')}</title>
</svelte:head>

<main class="confirm-card" id="main-content">
	<div class="card" data-testid="club-verification-confirm" data-state={phase}>
		<h1>{m('clubVerificationConfirm.title')}</h1>
		<p class:ok={phase === 'success'} class:bad={phase === 'failure' || phase === 'missing'} role="status">
			{message}
		</p>
		{#if phase === 'prompt'}
			<button
				class="btn-primary"
				onclick={confirm}
				disabled={!hydrated}
				data-testid="club-verification-confirm-button"
			>
				{m('clubVerificationConfirm.button')}
			</button>
		{:else if phase === 'success' && clubSlug}
			<a class="btn-primary" href={`/clubs/${clubSlug}`}>{m('clubVerificationConfirm.viewClub')}</a>
		{:else if phase !== 'working'}
			<a class="btn-primary" href="/">{m('clubVerificationConfirm.home')}</a>
		{/if}
	</div>
</main>

<style>
	.confirm-card {
		min-height: 100vh;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 1.5rem;
		background: var(--color-bg);
	}
	.card {
		max-width: 440px;
		width: 100%;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: 14px;
		padding: 2rem;
		box-shadow: var(--shadow-sm);
		text-align: center;
		color: var(--color-text);
	}
	h1 {
		margin: 0 0 1rem;
		font-size: 1.4rem;
	}
	p {
		margin: 0 0 1.5rem;
		line-height: 1.5;
		color: var(--color-text);
	}
	p.ok {
		color: var(--color-primary);
	}
	p.bad {
		color: var(--color-danger-text);
	}
</style>
