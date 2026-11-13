<script lang="ts">
	import { onMount } from 'svelte';
	import PageHeader from '#lib/components/PageHeader.svelte';
	import ListRow from '#lib/components/ListRow.svelte';
	import { goto } from '$app/navigation';
	import { m } from '#lib/i18n/store.svelte.ts';
	import {
		BODY_METRICS_PAGE,
		PREFERENCES_PAGES,
		legacyPreferencesTarget,
	} from '#lib/settings/preferences_ia.ts';

	const groups = [...PREFERENCES_PAGES, BODY_METRICS_PAGE];

	// Every setting that used to live on this one page now lives on a topical
	// page. A link that names a section (an email footer, the coach chat, a
	// bookmark) is sent straight to that section; a bare link lands here, where
	// each group says what it holds.
	onMount(() => {
		const target = legacyPreferencesTarget(location.hash);
		if (target) void goto(target, { replace: true });
	});
</script>

<div class="page">
	<PageHeader kicker={m('prefs.kicker')} title={m('prefs.heading')} subtitle={m('prefs.tagline')} />

	<ul class="prefs-group-list" data-testid="preferences-groups">
		{#each groups as group (group.href)}
			<li>
				<ListRow kind="nav" icon={group.icon} title={m(group.label)} subtitle={m(group.summary)} href={group.href} />
			</li>
		{/each}
	</ul>
</div>

<style>
	.page { padding: var(--page-padding-y) var(--page-padding-x); max-width: 64rem; }
	.prefs-group-list {
		list-style: none;
		margin: 0;
		padding: var(--space-2xs);
		max-width: 44rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.prefs-group-list li + li {
		border-top: 1px solid var(--color-border);
	}
</style>
