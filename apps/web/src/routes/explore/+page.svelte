<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';

	onMount(() => {
		goto('/routes?tab=explore', { replace: true });
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
	<noscript><meta http-equiv="refresh" content="0;url=/routes?tab=explore" /></noscript>
</svelte:head>
