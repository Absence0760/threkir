<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { m } from '$lib/i18n/store.svelte';
	import {
		BODY_METRICS_PAGE,
		PREFERENCES_PAGES,
		legacyPreferencesTarget,
	} from '$lib/settings/preferences_ia';

	const groups = [...PREFERENCES_PAGES, BODY_METRICS_PAGE];

	// Every setting that used to live on this one page now lives on a topical
	// page. A link that names a section (an email footer, the coach chat, a
	// bookmark) is sent straight to that section; a bare link lands here, where
	// each group says what it holds.
	onMount(() => {
		const target = legacyPreferencesTarget(location.hash);
		if (target) void goto(target, { replaceState: true });
	});
</script>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('prefs.kicker')}</p>
		<h1>{m('prefs.heading')}</h1>
		<p class="tagline">{m('prefs.tagline')}</p>
	</header>

	<ul class="prefs-group-list" data-testid="preferences-groups">
		{#each groups as group (group.href)}
			<li>
				<a class="prefs-group" href={group.href}>
					<span class="material-symbols group-icon" aria-hidden="true">{group.icon}</span>
					<span class="group-text">
						<span class="group-label">{m(group.label)}</span>
						<span class="group-summary">{m(group.summary)}</span>
					</span>
					<span class="material-symbols group-chevron" aria-hidden="true">chevron_right</span>
				</a>
			</li>
		{/each}
	</ul>
</div>

<style>
	.page { padding: var(--page-padding-y) var(--page-padding-x); max-width: 64rem; }
	.page-head { margin-bottom: var(--space-xl); }
	.kicker {
		text-transform: uppercase;
		letter-spacing: 0.08em;
		font-size: var(--font-size-section-label);
		font-weight: 700;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	h1 { font-size: 1.6rem; font-weight: 700; margin: 0 0 var(--space-xs); }
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		margin: 0;
		max-width: 44rem;
	}
	.prefs-group-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: var(--space-sm);
		max-width: 44rem;
	}
	.prefs-group {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		color: var(--color-text);
		text-decoration: none;
		transition: border-color var(--transition-fast);
	}
	.prefs-group:hover { border-color: var(--color-primary); }
	.group-icon { font-size: 1.4rem; color: var(--color-primary); flex-shrink: 0; }
	.group-text { display: flex; flex-direction: column; gap: 0.15rem; flex: 1; min-width: 0; }
	.group-label { font-weight: 600; }
	.group-summary { font-size: 0.85rem; color: var(--color-text-secondary); line-height: 1.45; }
	.group-chevron { color: var(--color-text-tertiary); flex-shrink: 0; }
</style>
