<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { m } from '#lib/i18n/store.svelte.ts';

	// The Coach's conversation moved into Messages (decisions § 2227). Links
	// to `/coach?plan=<id>` from mail, bookmarks and older builds still land
	// on the same plan, so the query string goes along. A client-side
	// redirect, as /settings does, keeps this a normal prerendered page with
	// no un-hashed inline script (decisions § 70); the <noscript> refresh is
	// the no-JS fallback and cannot carry the query.
	onMount(() => {
		goto(`/messages/coach${page.url.search}`, { replace: true });
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
	<noscript><meta http-equiv="refresh" content="0;url=/messages/coach" /></noscript>
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
