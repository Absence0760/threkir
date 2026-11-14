<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import SkeletonBlock from '#lib/components/SkeletonBlock.svelte';
	import type { PrefsLoadPhase } from '#lib/settings/prefs_page.svelte.ts';
	import type { PrefsSaveStatus } from '#lib/settings/prefs_save_queue.ts';

	let {
		heading,
		headingId,
		tagline,
		page,
		children,
	}: {
		heading: string;
		/// The page heading's id, when the heading is itself a settings-search
		/// result (`settingRowId`, settings_search.ts).
		headingId?: string;
		tagline: string;
		page: {
			readonly phase: PrefsLoadPhase;
			readonly error: string | null;
			readonly status: PrefsSaveStatus;
			reload: () => Promise<void>;
		};
		children: Snippet;
	} = $props();
</script>

<div class="page prefs-page">
	<header class="page-head">
		<p class="kicker">{m('prefs.kicker')}</p>
		<h1 id={headingId}>{heading}</h1>
		<p class="tagline">{tagline}</p>
		<p class="save-status" role="status" aria-live="polite" data-testid="save-status">
			{#if page.status === 'saving'}
				<span class="material-symbols spin" aria-hidden="true">progress_activity</span> {m('prefs.saving')}
			{:else if page.status === 'saved'}
				<span class="material-symbols" aria-hidden="true">check_circle</span> {m('prefs.saved')}
			{/if}
		</p>
	</header>

	{#if page.phase === 'loading'}
		<div class="skeleton-stack" aria-hidden="true">
			{#each Array(2) as _, i (i)}
				<div class="skel-card">
					<SkeletonBlock height="0.85rem" width="30%" />
					<div class="skel-grid">
						{#each Array(4) as _, j (j)}
							<SkeletonBlock height="2.4rem" radius="var(--radius-md)" />
						{/each}
					</div>
				</div>
			{/each}
		</div>
		<p class="visually-hidden" role="status">{m('prefs.loading')}</p>
	{:else if page.phase === 'failed'}
		<div class="load-error-banner" role="alert" data-testid="prefs-load-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{m('prefs.loadFailed')}</strong>
				<span class="load-error-detail">{page.error}</span>
			</div>
			<button class="btn btn-outline" type="button" onclick={() => void page.reload()} data-testid="prefs-load-retry">{m('prefs.retry')}</button>
		</div>
	{:else}
		{@render children()}
	{/if}
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
	.save-status {
		display: flex;
		align-items: center;
		gap: var(--space-2xs);
		min-height: 1.25rem;
		margin: var(--space-xs) 0 0;
		font-size: 0.8rem;
		font-weight: 600;
		color: var(--color-success-text);
	}
	.save-status .material-symbols {
		font-size: 1rem;
	}
	.save-status .spin {
		animation: prefs-spin 0.8s linear infinite;
	}
	@keyframes prefs-spin {
		to {
			transform: rotate(360deg);
		}
	}

	.skeleton-stack { display: flex; flex-direction: column; gap: var(--space-xl); }
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		pointer-events: none;
	}
	.skel-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-md);
	}
	.load-error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.load-error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.load-error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.load-error-banner .material-symbols {
		color: var(--color-danger-text);
		font-size: 1.4rem;
	}

	/* The field chrome every preferences page shares. Scoped under the shell's
	   root so it reaches the page's own markup without becoming a global
	   `.card` (conventions § Web cards). */
	.prefs-page :global {
		.prefs-section-head { margin-bottom: var(--space-lg); }
		.card { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-lg); margin-bottom: var(--space-xl); scroll-margin-top: var(--space-lg); }
		.form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(14rem, 100%), 1fr)); gap: var(--space-md); margin-bottom: var(--space-lg); }
		.form-grid.zones { grid-template-columns: repeat(auto-fit, minmax(min(7rem, 100%), 1fr)); }
		.form-stack { display: flex; flex-direction: column; gap: var(--space-md); margin-bottom: var(--space-lg); }
		.field { display: flex; flex-direction: column; }
		.hint {
			display: block;
			font-size: 0.78rem;
			color: var(--color-text-secondary);
			line-height: 1.45;
			margin-top: 0.2rem;
		}
		.label-text { display: block; font-size: 0.8rem; font-weight: 600; color: var(--color-text-secondary); margin-bottom: var(--space-xs); }
		input, select { width: 100%; padding: var(--space-sm) var(--space-md); border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.9rem; background: var(--color-bg); }
		input[type="checkbox"] { width: auto; padding: 0; flex-shrink: 0; }
		input:focus, select:focus { outline: none; border-color: var(--color-primary); }
		/* WCAG 2.4.7 + 2.4.11: the :focus rule drops the ring on a mouse
		   click; :focus-visible puts a real one back for keyboard focus. */
		input:focus-visible, select:focus-visible {
			outline: 2px solid var(--color-primary);
			outline-offset: 2px;
		}
		.toggle-row { display: flex; flex-wrap: wrap; gap: var(--space-sm); }
		.toggle-btn { flex: 1; padding: var(--space-sm) var(--space-md); border: 1.5px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg); font-size: 0.85rem; font-weight: 500; color: var(--color-text-secondary); cursor: pointer; transition: all var(--transition-fast); }
		.toggle-btn:hover { border-color: var(--color-primary); }
		.toggle-btn.active { background: var(--color-primary-light); border-color: var(--color-primary); color: var(--color-primary); }
		.section-desc { font-size: 0.85rem; color: var(--color-text-secondary); margin-bottom: var(--space-md); line-height: 1.5; }
		.section-hint { color: var(--color-text-secondary); font-size: 0.9rem; line-height: 1.5; margin: 0 0 var(--space-md) 0; }
		.field-error { display: block; font-size: 0.78rem; color: var(--color-danger-text); line-height: 1.45; margin-block-start: var(--space-2xs); }
		.consent-notice { background: var(--color-bg-tertiary); border-inline-start: 3px solid var(--color-primary); padding: var(--space-sm) var(--space-md); border-radius: var(--radius-sm); margin-top: var(--space-md); }
		.consent-checkbox { display: flex; gap: var(--space-sm); align-items: flex-start; font-size: 0.9rem; line-height: 1.45; margin-bottom: var(--space-md); padding: var(--space-sm) 0; }
		.consent-checkbox input { margin-top: 0.2rem; flex-shrink: 0; }
	}
</style>
