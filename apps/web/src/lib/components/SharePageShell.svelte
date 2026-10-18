<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { shareReturnFor, type ShareReturn } from '#lib/share/share_return.ts';

	interface Props {
		children: Snippet;
		/** The in-app view of this entity, offered to a signed-in visitor. */
		appHref?: string | null;
	}

	let { children, appHref = null }: Props = $props();

	// Effects never run during SSR or prerender, so the server markup — the
	// copy a crawler indexes — is the anonymous header, and the control only
	// appears once the client knows who is reading. The header's min-height
	// already fits it, so it lands without moving the page.
	let ret = $state<ShareReturn>(null);
	$effect(() => {
		ret = shareReturnFor({
			loggedIn: auth.loggedIn,
			referrer: document.referrer,
			origin: location.origin,
			historyLength: history.length,
			appHref,
		});
	});
</script>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
		{#if ret?.kind === 'back'}
			<button
				type="button"
				class="share-return"
				data-testid="share-return"
				onclick={() => history.back()}
			>
				<span class="material-symbols" aria-hidden="true">arrow_back</span>
				{m('shareRun.backToApp')}
			</button>
		{:else if ret?.kind === 'open'}
			<a href={ret.href} class="share-return" data-testid="share-return">
				{m('shareRun.openInApp')}
				<span class="material-symbols" aria-hidden="true">arrow_forward</span>
			</a>
		{/if}
	</header>

	{@render children()}

	<footer class="share-footer">
		<a href="/">{m('shareRun.footerHome')}</a>
		<span class="dot">&middot;</span>
		<a href="/login">{m('shareRun.signIn')}</a>
	</footer>
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.share-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
		min-height: calc(2.25rem + 2 * var(--space-sm) + 1px);
		box-sizing: border-box;
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.share-logo {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-primary);
		text-decoration: none;
	}

	.share-return {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		box-sizing: border-box;
		min-height: 2.25rem;
		padding: 0 var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font: inherit;
		font-size: 0.875rem;
		font-weight: 600;
		text-decoration: none;
		cursor: pointer;
	}

	.share-return:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.share-return .material-symbols {
		font-size: 1.125rem;
	}

	.share-footer {
		margin-top: auto;
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		background: var(--color-surface);
	}

	.share-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}

	.share-footer a:hover {
		color: var(--color-primary);
	}

	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}

	@media (min-width: 48rem) {
		.share-header {
			min-height: calc(2.25rem + 2 * var(--space-md) + 1px);
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
