<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { fetchEventClubSlug } from '#lib/core/data.ts';

	let { data } = $props();
	let resolving = $state(true);

	// Stable-id event URL. The canonical event page is nested under its club's
	// slug, but the notification worker's row projection carries only event_id
	// (no join), so /events/{id} is the address every email + push CTA can
	// build — and it survives a club rename, which the nested URL does not.
	// Emails and push payloads already sent carry this shape too, so the route
	// has to keep resolving indefinitely.
	onMount(async () => {
		const slug = await fetchEventClubSlug(data.id);
		if (slug) {
			await goto(`/clubs/${slug}/events/${data.id}`, { replace: true });
			return;
		}
		resolving = false;
	});
</script>

<svelte:head>
	<title>{m('shell.redirecting')}</title>
</svelte:head>

<div class="page">
	{#if resolving}
		<p class="muted">{m('shell.loading')}</p>
	{:else}
		<EmptyState icon="event_busy" title={m('clubEvent.notFoundTitle')} text={m('clubEvent.notFoundBody')}>
			{#snippet actions()}
				<a href="/clubs" class="btn btn-primary">{m('clubJoin.browseClubs')}</a>
			{/snippet}
		</EmptyState>
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
