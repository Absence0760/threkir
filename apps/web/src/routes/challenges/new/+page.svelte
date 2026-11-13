<script lang="ts">
	import ChallengeEditor from '#lib/components/ChallengeEditor.svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { goto } from '$app/navigation';
</script>

<svelte:head>
	<title>{m('challenges.create')}</title>
</svelte:head>

<div class="page narrow">
	<PageHeader title={m('challenges.create')} />
	<ChallengeEditor
		oncreated={(ch) => goto(`/challenges/${ch.id}`)}
		oncancel={() => goto('/challenges')}
	/>
</div>

<style>
	.narrow {
		max-width: 40rem;
	}
</style>
