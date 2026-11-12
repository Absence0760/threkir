<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';

	// `/settings` has no content of its own — it just bounces to the first
	// tab. A client-side redirect (mirroring /clubs, /feed, /explore) keeps
	// this a normal prerendered page whose only inline script is the
	// hash-covered SvelteKit hydration block. The previous server `redirect()`
	// (+page.ts, prerender=true) emitted a redirect STUB with an un-hashed
	// inline `location.href` script that rode the CloudFront header's
	// `unsafe-inline` — the one page the hash-based CSP couldn't cover
	// (audit-xss M2 / decisions §70). The <meta refresh> is the no-JS fallback,
	// and it sits inside <noscript> because <svelte:head> also inserts it on a
	// client-side navigation here, where the browser obeys it and does a full
	// reload before goto() can run.
	onMount(() => {
		goto('/settings/account', { replace: true });
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
	<noscript><meta http-equiv="refresh" content="0;url=/settings/account" /></noscript>
</svelte:head>

<div class="page">
	<p class="muted">{m('shell.loading')}</p>
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
