<script lang="ts">
	import PageHeader from '#lib/components/PageHeader.svelte';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { fetchGymExerciseNames } from '#lib/core/data.ts';
	import RoutineEditor from '#lib/components/RoutineEditor.svelte';
	import { m as t } from '#lib/i18n/store.svelte.ts';

	let suggestions = $state<string[]>([]);

	onMount(async () => {
		await auth.ready();
		if (!auth.user) return;
		suggestions = await fetchGymExerciseNames();
	});

	function onCreated(id: string) {
		goto(`/gym/routines/${id}`);
	}
</script>

<svelte:head><title>{t('gym.routine.editor.newTitle')} — Threkir</title></svelte:head>

<div class="page">
	<PageHeader back={{ href: '/gym/routines', label: t('gym.routine.back') }} title={t('gym.routine.editor.newTitle')} />

	<div class="editor-wrap">
		<RoutineEditor {suggestions} oncreated={onCreated} oncancel={() => goto('/gym/routines')} />
	</div>
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.editor-wrap {
		margin-top: var(--space-md);
	}
</style>
