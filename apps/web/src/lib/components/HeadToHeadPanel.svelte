<script lang="ts">
	// The head-to-head share card's picker, preview and export: one friend's best
	// public attempt against the caller's on one route or segment (decisions
	// § 2267). The `head_to_head` read only returns friends every rule admits,
	// so the picker never offers someone who cannot be compared.
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { fetchHeadToHead } from '#lib/core/data.ts';
	import { headToHeadName, type HeadToHeadKind, type HeadToHeadRow } from '#lib/social/head_to_head.ts';
	import { headToHeadPreviewKey, paintHeadToHead } from '#lib/share/head_to_head_canvas.ts';
	import { canvasToPng, loadShareFonts } from '#lib/share/run_sticker_canvas.ts';

	interface Props {
		kind: HeadToHeadKind;
		targetId: string;
		activityType?: string | null;
	}

	let { kind, targetId, activityType = null }: Props = $props();

	let rows = $state<HeadToHeadRow[] | null>(null);
	let failed = $state(false);
	let friendId = $state<string | null>(null);
	let preview = $state<{ url: string; blob: Blob; key: string } | null>(null);
	let rendering = $state(false);
	let busy = $state(false);
	let canShare = $state(false);

	let selected = $derived(rows?.find((r) => r.friendId === friendId) ?? null);

	function nameOf(r: HeadToHeadRow): string {
		return headToHeadName(r.friendHandle, r.friendDisplayName) ?? m('headToHead.friendFallback');
	}

	let loadSeq = 0;
	async function load() {
		const seq = ++loadSeq;
		rows = null;
		failed = false;
		try {
			const got = await fetchHeadToHead(kind, targetId, { activityType });
			if (seq !== loadSeq) return;
			rows = got;
			friendId = got[0]?.friendId ?? null;
		} catch (e) {
			if (seq !== loadSeq) return;
			console.warn('head_to_head failed', e);
			failed = true;
		}
	}

	$effect(() => {
		void kind;
		void targetId;
		void activityType;
		canShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function';
		void load();
		return () => {
			loadSeq++;
			if (preview) URL.revokeObjectURL(preview.url);
			preview = null;
		};
	});

	let renderSeq = 0;
	$effect(() => {
		const r = selected;
		if (!r) return;
		const key = headToHeadPreviewKey(r);
		if (preview?.key === key) return;
		const seq = ++renderSeq;
		rendering = true;
		(async () => {
			await loadShareFonts();
			const canvas = paintHeadToHead({
				targetName: r.targetName,
				myName: m('headToHead.me'),
				friendName: nameOf(r),
				mySeconds: r.mySeconds,
				friendSeconds: r.friendSeconds,
				kicker: m('headToHead.title'),
				vs: m('headToHead.vs'),
				outcome: (winner, margin) =>
					winner === 'tie'
						? m('headToHead.tie')
						: winner === 'me'
							? m('headToHead.iWon', { margin })
							: m('headToHead.friendWon', { name: nameOf(r), margin }),
				wordmark: 'Threkir',
			});
			return canvasToPng(canvas);
		})()
			.then((blob) => {
				if (seq !== renderSeq) return;
				if (preview) URL.revokeObjectURL(preview.url);
				preview = { url: URL.createObjectURL(blob), blob, key };
			})
			.catch((e) => {
				if (seq !== renderSeq) return;
				console.warn('head-to-head render failed', e);
				showToast(m('runDetail.imageGenerateFailed', { error: errorCopy(e, m, 'runDetail.imageGenerateFailed') }), 'error');
			})
			.finally(() => {
				if (seq === renderSeq) rendering = false;
			});
	});

	let ready = $derived(selected !== null && preview?.key === headToHeadPreviewKey(selected) && !rendering && !busy);
	let fileName = $derived(`threkir-head-to-head-${kind}-${targetId}.png`);

	async function deliver(mode: 'share' | 'download') {
		if (!ready || !preview || !selected) return;
		busy = true;
		try {
			const file = new File([preview.blob], fileName, { type: 'image/png' });
			if (mode === 'share' && navigator.canShare?.({ files: [file] })) {
				await navigator.share({ title: selected.targetName, files: [file] });
				return;
			}
			const a = document.createElement('a');
			a.href = preview.url;
			a.download = fileName;
			a.click();
			showToast(m('runDetail.imageSaved'), 'success');
		} catch (e) {
			if (!(e instanceof DOMException && e.name === 'AbortError')) {
				showToast(m('runDetail.imageGenerateFailed', { error: errorCopy(e, m, 'runDetail.imageGenerateFailed') }), 'error');
			}
		} finally {
			busy = false;
		}
	}
</script>

<div class="h2h" data-testid="head-to-head-panel">
	{#if failed}
		<div class="state" role="alert" data-testid="head-to-head-error">
			<p>{m('headToHead.loadFailed')}</p>
			<button type="button" class="btn btn-outline btn-sm" onclick={() => void load()}>
				{m('headToHead.retry')}
			</button>
		</div>
	{:else if rows === null}
		<p class="state" role="status">{m('headToHead.loading')}</p>
	{:else if rows.length === 0}
		<p class="state" data-testid="head-to-head-empty">{m('headToHead.empty')}</p>
	{:else}
		<fieldset class="control">
			<legend>{m('headToHead.friend')}</legend>
			<div class="chip-row" role="radiogroup" aria-label={m('headToHead.friend')}>
				{#each rows as r (r.friendId)}
					<button
						type="button"
						role="radio"
						aria-checked={friendId === r.friendId}
						class="chip"
						class:active={friendId === r.friendId}
						disabled={busy}
						onclick={() => (friendId = r.friendId)}
						data-testid="head-to-head-friend">{nameOf(r)}</button
					>
				{/each}
			</div>
		</fieldset>
		<div class="preview" aria-busy={rendering}>
			{#if preview}
				<img
					src={preview.url}
					alt={m('headToHead.preview')}
					class:dim={rendering}
					data-testid="head-to-head-preview"
				/>
			{/if}
		</div>
		<p class="hint">{m('headToHead.privacy')}</p>
		<div class="actions">
			{#if canShare}
				<button
					type="button"
					class="btn btn-primary"
					onclick={() => deliver('share')}
					disabled={!ready}
					data-testid="head-to-head-share"
				>
					<span class="material-symbols" aria-hidden="true">ios_share</span>
					{m('runShare.share')}
				</button>
			{/if}
			<button
				type="button"
				class="btn"
				class:btn-primary={!canShare}
				class:btn-secondary={canShare}
				onclick={() => deliver('download')}
				disabled={!ready}
				data-testid="head-to-head-download"
			>
				<span class="material-symbols" aria-hidden="true">download</span>
				{m('runShare.download')}
			</button>
		</div>
	{/if}
</div>

<style>
	.h2h {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		min-width: 0;
	}
	.state {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-sm);
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.state p {
		margin: 0;
	}
	.chip-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.chip {
		display: inline-flex;
		align-items: center;
		padding: 0.4rem 0.9rem;
		min-height: 2.25rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
		max-width: 100%;
		overflow-wrap: anywhere;
	}
	.chip.active {
		background: var(--color-primary);
		color: var(--color-on-primary);
		border-color: var(--color-primary);
	}
	.chip:disabled {
		cursor: not-allowed;
		opacity: 0.55;
	}
	.control {
		border: 0;
		margin: 0;
		padding: 0;
		min-width: 0;
	}
	.control legend {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		padding: 0;
		margin-bottom: 0.4rem;
	}
	.preview {
		display: flex;
		align-items: center;
		justify-content: center;
		height: min(52vh, 440px);
		padding: var(--space-sm);
		border-radius: var(--radius-lg);
		background: var(--color-bg-tertiary);
		overflow: hidden;
	}
	.preview img {
		max-width: 100%;
		max-height: 100%;
		object-fit: contain;
		transition: opacity var(--transition-fast);
	}
	.preview img.dim {
		opacity: 0.6;
	}
	@media (prefers-reduced-motion: reduce) {
		.preview img {
			transition: none;
		}
	}
	.hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin: 0;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		justify-content: flex-end;
	}
	.actions .btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
	}
	@media (max-width: 480px) {
		.actions .btn {
			flex: 1 1 100%;
			justify-content: center;
		}
	}
</style>
