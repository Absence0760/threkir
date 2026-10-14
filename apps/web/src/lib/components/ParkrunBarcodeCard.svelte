<script lang="ts">
	import { tick } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { normalizeParkrunAthleteNumber } from '#lib/integrations/parkrun_barcode.ts';
	import ParkrunBarcode from './ParkrunBarcode.svelte';

	interface Props {
		/** `user_profiles.parkrun_number` as stored, possibly empty or legacy junk. */
		storedNumber: string | null;
	}

	let { storedNumber }: Props = $props();

	const stored = $derived((storedNumber ?? '').trim());
	const number = $derived(normalizeParkrunAthleteNumber(stored));

	let fullScreen = $state(false);
	let closeBtn = $state<HTMLButtonElement | null>(null);
	let opener: HTMLElement | null = null;

	async function openFullScreen(e: MouseEvent) {
		opener = e.currentTarget as HTMLElement;
		fullScreen = true;
		await tick();
		closeBtn?.focus();
		// Best effort: the overlay already fills the viewport, and browsers
		// refuse the API outside a user gesture or inside some frames.
		try {
			await document.documentElement.requestFullscreen?.();
		} catch (err) {
			console.debug('parkrun barcode: fullscreen refused', err);
		}
	}

	async function closeFullScreen() {
		if (!fullScreen) return;
		fullScreen = false;
		try {
			if (document.fullscreenElement) await document.exitFullscreen();
		} catch (err) {
			console.debug('parkrun barcode: exit fullscreen failed', err);
		}
		opener?.focus();
	}

	// A browser in API fullscreen takes Escape for itself and exits, so the
	// overlay follows the document out rather than waiting for a keydown.
	function onFullscreenChange() {
		if (!document.fullscreenElement) void closeFullScreen();
	}

	function onKey(e: KeyboardEvent) {
		if (fullScreen && e.key === 'Escape') {
			e.preventDefault();
			void closeFullScreen();
		}
	}
</script>

<svelte:window onkeydown={onKey} />
<svelte:document onfullscreenchange={onFullscreenChange} />

<section class="card barcode-card" data-testid="parkrun-barcode-card">
	<h2>{m('parkrunBarcode.title')}</h2>
	{#if number}
		<p class="card-sub">{m('parkrunBarcode.description')}</p>
		<div class="barcode-frame">
			<ParkrunBarcode {number} />
		</div>
		<div class="actions">
			<button
				type="button"
				class="btn btn-primary btn-sm"
				onclick={openFullScreen}
				data-testid="parkrun-barcode-fullscreen"
			>
				{m('parkrunBarcode.fullScreen')}
			</button>
			<a class="btn btn-outline btn-sm" href="/settings/account">{m('parkrunBarcode.editNumber')}</a>
		</div>
		<p class="note">{m('parkrunBarcode.paperNote')}</p>
	{:else if stored.length > 0}
		<p class="card-sub" role="status" data-testid="parkrun-barcode-invalid">
			{m('parkrunBarcode.invalid')}
		</p>
		<a class="btn btn-outline btn-sm" href="/settings/account">{m('parkrunBarcode.editNumber')}</a>
	{:else}
		<p class="card-sub" data-testid="parkrun-barcode-empty">{m('parkrunBarcode.empty')}</p>
		<a class="btn btn-outline btn-sm" href="/settings/account">{m('parkrunBarcode.addNumber')}</a>
	{/if}
</section>

{#if fullScreen && number}
	<div
		class="scan-view"
		role="dialog"
		aria-modal="true"
		aria-label={m('parkrunBarcode.title')}
		data-testid="parkrun-barcode-overlay"
	>
		<button
			type="button"
			class="close"
			bind:this={closeBtn}
			onclick={closeFullScreen}
			data-testid="parkrun-barcode-close"
		>
			<span class="material-symbols" aria-hidden="true">close</span>
			{m('parkrunBarcode.close')}
		</button>
		<div class="fullscreen-code">
			<ParkrunBarcode {number} heightModules={64} testId="parkrun-barcode-large" />
		</div>
		<p class="fullscreen-hint">{m('parkrunBarcode.brightnessHint')}</p>
	</div>
{/if}

<style>
	.barcode-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-top: var(--space-xl);
	}
	.barcode-card h2 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0 0 var(--space-xs);
	}
	.card-sub,
	.note {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		margin: 0 0 var(--space-md);
		line-height: 1.45;
	}
	.note {
		margin: var(--space-md) 0 0;
		font-size: 0.78rem;
	}
	.barcode-frame {
		max-width: 26rem;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		margin-top: var(--space-md);
	}
	.actions .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	/* Fixed white whatever the theme — the point of the view is a code a
	   scanner can read, so the whole viewport is the light the code needs. */
	.scan-view {
		position: fixed;
		inset: 0;
		z-index: 1000;
		background: #fff;
		color: #000;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: var(--space-md);
	}
	.fullscreen-code {
		width: min(100%, 40rem);
	}
	.fullscreen-hint {
		margin-top: var(--space-md);
		font-size: 0.9rem;
		text-align: center;
	}
	.close {
		position: absolute;
		top: var(--space-md);
		inset-inline-end: var(--space-md);
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: 44px;
		padding: 0 var(--space-md);
		background: #fff;
		color: #000;
		border: 2px solid #000;
		border-radius: var(--radius-pill);
		font: inherit;
		cursor: pointer;
	}
</style>
