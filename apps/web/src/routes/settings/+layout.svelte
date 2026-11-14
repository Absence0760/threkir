<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { page } from '$app/state';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { supabase } from '#lib/core/supabase.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { BODY_METRICS_PAGE, PREFERENCES_PAGES } from '#lib/settings/preferences_ia.ts';
	import { shareAttributionEnabled } from '#lib/share/share_attribution.ts';
	import { searchSettings } from '#lib/settings/settings_search.ts';
	import { focusSettingFromHash } from '#lib/settings/setting_focus.ts';
	import AppSearchField from '#lib/components/AppSearchField.svelte';
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import ListRow from '#lib/components/ListRow.svelte';

	type Tab = { href: string; label: string; icon: string };
	type Section = { label: string; tabs: Tab[] };

	// "Finish setup" nudge — shows when a user who skipped fields
	// during the /onboarding wizard hasn't filled them in since. The
	// onboarded_at column is already populated (the wizard stamps it
	// on Finish OR Skip-onboarding so the gate doesn't re-trigger),
	// so we detect the fields directly. Conservative: only checks
	// the highest-impact unset values so we don't badger users who
	// deliberately left optional fields blank.
	let unsetFields = $state<string[]>([]);
	// Your shares is offered only while the share_attribution gate is open
	// (decisions § 2268).
	let sharesEnabled = $state(false);
	onMount(() => {
		void shareAttributionEnabled().then((on) => (sharesEnabled = on));
	});
	onMount(async () => {
		if (!auth.user) return;
		const checks: string[] = [];
		if (!auth.user.display_name) checks.push(m('settingsLayout.fieldDisplayName'));
		try {
			const { data } = await supabase
				.from('user_settings')
				.select('prefs')
				.eq('user_id', auth.user.id)
				.maybeSingle();
			const p = (data?.prefs ?? {}) as Record<string, unknown>;
			if (!p.body_weight_kg) checks.push(m('settingsLayout.fieldBodyWeight'));
			if (!p.privacy_default) checks.push(m('settingsLayout.fieldPrivacyDefault'));
		} catch (_) {
			/* L4 — if the read fails, just don't surface the nudge. */
		}
		unsetFields = checks;
	});

	const sections = $derived<Section[]>([
		{
			label: m('settingsLayout.sectionProfile'),
			tabs: [
				{ href: '/settings/account', label: m('settingsLayout.tabAccount'), icon: 'person' },
				{ href: BODY_METRICS_PAGE.href, label: m(BODY_METRICS_PAGE.label), icon: BODY_METRICS_PAGE.icon },
				{ href: '/settings/safety', label: m('safety.navTab'), icon: 'emergency' },
			],
		},
		{
			label: m('settingsLayout.sectionPreferences'),
			tabs: PREFERENCES_PAGES.map((p) => ({ href: p.href, label: m(p.label), icon: p.icon })),
		},
		{
			label: m('settingsLayout.sectionAppsData'),
			tabs: [
				{ href: '/settings/integrations', label: m('settingsLayout.tabIntegrations'), icon: 'link' },
				{ href: '/settings/devices', label: m('settingsLayout.tabDevices'), icon: 'devices' },
				{ href: '/settings/gear', label: m('settingsLayout.tabGear'), icon: 'directions_run' },
				{ href: '/settings/payouts', label: m('settingsLayout.tabPayouts'), icon: 'payments' },
				...(sharesEnabled
					? [{ href: '/settings/shares', label: m('shares.tab'), icon: 'share' }]
					: []),
			],
		},
		{
			label: m('settingsLayout.sectionAccountLegal'),
			tabs: [
				{ href: '/settings/upgrade', label: m('settingsLayout.tabProSupport'), icon: 'favorite' },
				{ href: '/settings/licenses', label: m('settingsLayout.tabAbout'), icon: 'description' },
			],
		},
	]);

	// Search over every settings page's rows (decisions § 2494): a result
	// lands on the row itself (`#setting-…`), scrolled into view, focused and
	// briefly highlighted. Only pages the nav shows are searched.
	let query = $state('');
	const results = $derived(
		query.trim() === ''
			? null
			: searchSettings(query, m, new Set(sections.flatMap((s) => s.tabs.map((tab) => tab.href)))),
	);

	// Every navigation whose fragment names a row lands on it, including a
	// direct load of a shared link; a result for the row already in the URL
	// changes nothing the effect reads, so its click lands on it directly.
	$effect(() => {
		const hash = page.url.hash;
		void page.url.pathname;
		return untrack(() => focusSettingFromHash(hash));
	});
	function pickResult(href: string) {
		query = '';
		if (href === page.url.pathname + page.url.hash) focusSettingFromHash(page.url.hash);
	}
</script>

<svelte:head>
	<title>{m('settingsLayout.pageTitle')}</title>
</svelte:head>

<div class="settings-shell">
	<nav class="settings-nav">
		<SectionHeader label={m('shell.settings')} class="settings-nav-title" />
		<div class="settings-search">
			<AppSearchField bind:value={query} label={m('settingsLayout.searchLabel')} testid="settings-search" />
		</div>
		{#if results}
			<ul class="search-results" data-testid="settings-search-results" aria-label={m('settingsLayout.searchLabel')}>
				{#each results as hit (hit.href + hit.title)}
					<li>
						<ListRow
							kind="nav"
							title={hit.title}
							subtitle={hit.where}
							href={hit.href}
							onclick={() => pickResult(hit.href)}
							testid="settings-search-result"
						/>
					</li>
				{/each}
			</ul>
			<p class="search-empty" aria-live="polite" data-testid="settings-search-empty">
				{results.length === 0 ? m('settingsLayout.searchEmpty', { query: query.trim() }) : ''}
			</p>
		{:else}
			{#each sections as section}
				<SectionHeader label={section.label} level={3} class="nav-section-label" flush />
				{#each section.tabs as tab}
					<a
						href={tab.href}
						class="nav-item"
						class:active={page.url.pathname.startsWith(tab.href)}
					>
						<span class="material-symbols">{tab.icon}</span>
						{tab.label}
					</a>
				{/each}
			{/each}
		{/if}
		<div class="legal-links">
			<a href="/privacy">{m('landing.footerPrivacy')}</a>
			<a href="/terms">{m('landing.footerTerms')}</a>
			<a href="/cookie-notice">{m('landing.footerCookies')}</a>
			<a href="/health-data-notice">{m('landing.footerHealthData')}</a>
		</div>
	</nav>
	<div class="settings-content">
		{#if unsetFields.length > 0}
			<aside class="finish-setup">
				<span class="material-symbols">info</span>
				<div class="finish-setup-text">
					<strong>{m('settingsLayout.finishSetupTitle')}</strong>
					<span>{m('settingsLayout.finishSetupBody', { fields: unsetFields.join(', ') })}</span>
				</div>
			</aside>
		{/if}
		<slot />
	</div>
</div>

<style>
	.settings-shell {
		display: flex;
		min-height: 100%;
	}
	/* Pinned to the viewport like the app's own rail (`+layout.svelte`'s
	   `.sidebar` is `position: fixed`), so switching section never costs a
	   scroll back up a long page such as /settings/account.

	   The three extra declarations are interdependent, not three tweaks.
	   `align-self` stops the default `stretch`, which had been sizing this
	   rail to the content column and so resolving `.legal-links`'
	   `margin-top: auto` against the whole page — the four legal links
	   rendered at the very bottom of a multi-thousand-pixel document rather
	   than at the foot of the rail. Once it no longer stretches it has no
	   height for `auto` to resolve against either, which is what
	   `height: 100vh` restores. And a fixed-height rail clips, so
	   `overflow-y` carries the case where the viewport is shorter than the
	   rail's own content — a large OS text scale, or a short laptop window.

	   The property name is written with its value rather than alone above
	   because every backticked bare word under apps/web/src that the icon
	   font can render is harvested into the subset by
	   scripts/gen_web_icon_font.mjs — and that property name happens to be a
	   real Material Symbols ligature. Quoting it alone bought a glyph
	   nothing renders, and failed build-web on subset drift. */
	.settings-nav {
		width: 14rem;
		flex-shrink: 0;
		padding: var(--space-xl) var(--space-lg);
		border-inline-end: 1px solid var(--color-border);
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		position: sticky;
		top: 0;
		align-self: flex-start;
		height: 100vh;
		overflow-y: auto;
	}
	.settings-nav :global(.settings-nav-title) {
		margin-bottom: var(--space-md);
	}
	.settings-search {
		margin-bottom: var(--space-sm);
	}
	.search-results {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}
	.search-empty {
		margin: var(--space-xs) 0.75rem;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
	}
	.search-empty:empty {
		display: none;
	}
	.settings-nav :global(.nav-section-label) {
		padding: var(--space-md) 0.75rem var(--space-2xs);
	}
	.settings-nav :global(.nav-section-label:first-of-type) {
		padding-top: 0;
	}
	.nav-item {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.5rem 0.75rem;
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		transition: all var(--transition-fast);
		text-decoration: none;
	}
	.nav-item:hover {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.nav-item.active {
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-weight: 600;
	}
	.nav-item .material-symbols {
		font-size: 1.15rem;
	}
	.legal-links {
		margin-top: auto;
		padding: var(--space-lg) 0.75rem 0;
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem 0.75rem;
		font-size: 0.75rem;
	}
	.legal-links a {
		color: var(--color-text-tertiary);
		text-decoration: none;
	}
	.legal-links a:hover {
		color: var(--color-text-secondary);
		text-decoration: underline;
	}
	.settings-content {
		flex: 1;
		min-width: 0;
	}
	/* The row a search result landed on (setting_focus.ts): a tint and a ring
	   that fade out, so the eye finds it among its neighbours. The tint sits
	   behind the row's own content; the ring replaces the focus ring the
	   programmatic focus would otherwise draw. */
	.settings-content :global(.setting-flash) {
		border-radius: var(--radius-md);
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
		animation: -global-setting-flash 2s ease-out forwards;
	}
	.settings-content :global([id^='setting-'][tabindex='-1']:focus:not(.setting-flash)) {
		outline: none;
	}
	@keyframes -global-setting-flash {
		0%,
		60% {
			background-color: var(--color-primary-light);
			outline-color: var(--color-primary);
		}
		100% {
			background-color: transparent;
			outline-color: transparent;
		}
	}
	/* Reduced motion: the same highlight, held still for its two seconds and
	   then removed, with no fade. */
	@media (prefers-reduced-motion: reduce) {
		.settings-content :global(.setting-flash) {
			animation: none;
			background-color: var(--color-primary-light);
		}
	}
	.finish-setup {
		display: flex;
		gap: 0.65rem;
		align-items: flex-start;
		margin: var(--space-lg) var(--space-2xl) 0;
		padding: var(--space-md);
		background: color-mix(in srgb, var(--color-primary) 7%, transparent);
		border: 1px solid color-mix(in srgb, var(--color-primary) 25%, transparent);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
	}
	.finish-setup .material-symbols {
		font-size: 1.2rem;
		color: var(--color-primary);
		flex-shrink: 0;
		margin-top: 0.1rem;
	}
	.finish-setup-text { display: flex; flex-direction: column; gap: 0.2rem; }
	.finish-setup-text strong { font-weight: 600; }
	.finish-setup-text span { color: var(--color-text-secondary); line-height: 1.45; }
	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		display: inline-block;
		line-height: 1;
	}

	/* Narrow viewports: a 14rem rail beside the app's own 4.5rem rail
	   leaves a 320px screen no content column at all. The two stack and
	   the section list wraps into rows — nothing is hidden and nothing
	   scrolls sideways, so the heading, the group labels and the legal
	   links all stay reachable. */
	@media (max-width: 60rem) {
		.settings-shell {
			flex-direction: column;
		}
		.settings-nav {
			width: auto;
			flex-direction: row;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-2xs);
			padding: var(--space-md) var(--page-padding-x);
			border-inline-end: none;
			border-block-end: 1px solid var(--color-border);
			/* Stacked, the rail is a wrapping row of rows above the content,
			   so pinning it would eat the top of a small screen. */
			position: static;
			align-self: auto;
			height: auto;
			overflow-y: visible;
		}
		.settings-nav :global(.settings-nav-title),
		.settings-nav :global(.nav-section-label),
		.legal-links {
			flex: 0 0 100%;
			margin: 0;
			padding: var(--space-2xs) 0 0;
		}
		.nav-item {
			flex: 0 0 auto;
		}
		.finish-setup {
			margin-inline: var(--page-padding-x);
		}
	}
</style>
