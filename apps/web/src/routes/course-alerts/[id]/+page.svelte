<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';
	import EmptyState from '#lib/components/EmptyState.svelte';
	import { fetchCourseAlertTarget } from '#lib/core/data.ts';

	let { data } = $props();
	let resolving = $state(true);

	// Stable-id address for an organiser's course alert (decisions § 2407).
	// The notification worker's row projection carries only course_alert_id,
	// so every email and push CTA links here, and this opens the race or the
	// route the alert is on. Notices already sent carry this shape, so it has
	// to keep resolving.
	onMount(async () => {
		try {
			const target = await fetchCourseAlertTarget(data.id);
			if (target?.listingId) {
				await goto(`/races/${target.listingId}`, { replace: true });
				return;
			}
			if (target?.routeId) {
				await goto(`/routes/${target.routeId}`, { replace: true });
				return;
			}
		} catch (e) {
			console.error('course alert resolve failed', e);
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
		<EmptyState
			icon="search_off"
			title={m('courseAlerts.notFoundTitle')}
			text={m('courseAlerts.notFoundBody')}
			data-testid="course-alert-not-found"
		>
			{#snippet actions()}
				<a href="/races" class="btn btn-primary">{m('courseAlerts.browseRaces')}</a>
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
