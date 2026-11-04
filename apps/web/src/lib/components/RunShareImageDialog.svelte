<script lang="ts">
	// The run share-image editor: the map card, the runner's own photo, or a
	// transparent sticker, in the layouts, inks, aspects and stats the phone's
	// share sheet offers (run_share_card.dart). The preview IS the export: each
	// change re-renders the PNG that Share and Download hand over.
	import { untrack } from 'svelte';
	import Modal from '#lib/components/Modal.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { currentLocale } from '#lib/i18n/store.svelte.ts';
	import { getUnit } from '#lib/format/units.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import type { TrackPoint } from '#lib/types.ts';
	import {
		availableShareStats,
		runShareStats,
		type RunShareStatKind,
		type ShareableRun,
	} from '#lib/share/run_share_stats.ts';
	import {
		DEFAULT_SHARE_STATS,
		MAX_SHARE_STATS,
		RUN_PHOTO_ASPECTS,
		RUN_SHARE_INKS,
		RUN_STICKER_LAYOUTS,
		loadShareLook,
		saveShareLook,
		shareLookEquals,
		toggleShareStat,
		type RunShareLook,
	} from '#lib/share/share_look.ts';
	import { canvasToPng, loadShareFonts, paintPhoto, paintSticker } from '#lib/share/run_sticker_canvas.ts';
	import HeadToHeadPanel from '#lib/components/HeadToHeadPanel.svelte';
	import type { HeadToHeadKind } from '#lib/social/head_to_head.ts';
	import { formatPrImprovement, type PrBracket, type PrCardEntry } from '#lib/share/pr_card.ts';
	import { paintPrCard, type PrCardText } from '#lib/share/pr_card_canvas.ts';
	import { formatShareDuration } from '#lib/share/run_share_stats.ts';

	type Style = 'card' | 'photo' | 'sticker' | 'pr' | 'versus';

	interface Props {
		open: boolean;
		onclose: () => void;
		run: ShareableRun;
		title: string;
		/// The clipped share line (`shareCardTrack`), never a raw track.
		line: TrackPoint[];
		/// The map card's PNG, rasterised from the page's off-screen card.
		captureCard: (mark: boolean) => Promise<Blob>;
		fileBase: string;
		/// The route this run is on, which offers the Versus style: the
		/// caller's best there against a mutual-follow friend's (§ 2267).
		headToHead?: { kind: HeadToHeadKind; targetId: string } | null;
		/// The personal records this run set (`prCardEntries`), longest first;
		/// the PR style is offered only when there is one.
		records?: PrCardEntry[];
		/// The run's date as the PR card prints it.
		recordDate?: string;
		/// The style the editor opens on, e.g. `pr` from a PR notification.
		initialStyle?: Style;
	}

	let {
		open,
		onclose,
		run,
		title,
		line,
		captureCard,
		fileBase,
		records = [],
		recordDate = '',
		initialStyle = 'card',
		headToHead = null,
	}: Props = $props();

	const STYLES: { value: Style; label: MessageKey; icon: string }[] = [
		{ value: 'card', label: 'runShare.styleCard', icon: 'map' },
		{ value: 'photo', label: 'runShare.stylePhoto', icon: 'photo' },
		{ value: 'sticker', label: 'runShare.styleSticker', icon: 'auto_awesome_motion' },
		{ value: 'pr', label: 'runShare.stylePr', icon: 'military_tech' },
	];
	const PR_LABELS: Record<PrBracket, MessageKey> = {
		'1_mile': 'planRecap.bracketMile',
		'5k': 'planRecap.bracket5k',
		'8k': 'planRecap.bracket8k',
		'10k': 'planRecap.bracket10k',
		'12k': 'planRecap.bracket12k',
		half_marathon: 'planRecap.bracketHalf',
		marathon: 'planRecap.bracketMarathon',
	};
	let styles = $derived([
		...STYLES.filter((s) => s.value !== 'pr' || records.length > 0),
		...(headToHead ? [{ value: 'versus' as const, label: 'headToHead.styleVersus' as MessageKey, icon: 'group' }] : []),
	]);
	let prIndex = $state(0);
	let record = $derived(records[Math.min(prIndex, records.length - 1)] ?? null);
	const LAYOUT_LABELS: Record<RunShareLook['layout'], MessageKey> = {
		stack: 'runShare.layoutStack',
		route: 'runShare.layoutRoute',
		strip: 'runShare.layoutStrip',
		hero: 'runShare.layoutHero',
	};
	const INK_LABELS: Record<RunShareLook['ink'], MessageKey> = {
		light: 'runShare.inkLight',
		dark: 'runShare.inkDark',
		brand: 'runShare.inkBrand',
	};
	const ASPECT_LABELS: Record<RunShareLook['aspect'], MessageKey> = {
		story: 'runShare.aspectStory',
		post: 'runShare.aspectPost',
	};

	let style = $state<Style>('card');
	let look = $state<RunShareLook>(loadShareLook());
	let photo = $state<ImageBitmap | null>(null);
	let picking = $state(false);
	let rendering = $state(false);
	let busy = $state(false);
	let preview = $state<{ url: string; blob: Blob; key: string } | null>(null);
	let cardBlob: { mark: boolean; blob: Blob } | null = null;
	let fileInput = $state<HTMLInputElement | null>(null);
	let canShare = $state(false);
	let photoSeq = $state(0);

	let available = $derived(availableShareStats(run));
	let usesSpeed = $derived(run.activity_type === 'cycle');

	/// `stored` with the stats this run cannot print taken out, so the cap
	/// counts what the image shows. The stored look keeps them for the next
	/// run that has them; only an edit here writes the narrowed set back.
	function forThisRun(stored: RunShareLook): RunShareLook {
		const printable = stored.stats.filter((k) => available.includes(k));
		return { ...stored, stats: printable.length > 0 ? printable : [...DEFAULT_SHARE_STATS] };
	}

	$effect(() => {
		if (!open) return;
		look = forThisRun(loadShareLook());
		// Read once per opening: records landing while the editor is open must
		// not reset the style the runner is on.
		style = untrack(() => (initialStyle === 'pr' && records.length === 0 ? 'card' : initialStyle));
		prIndex = 0;
		canShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function';
		return () => {
			cardBlob = null;
			if (preview) URL.revokeObjectURL(preview.url);
			preview = null;
			// A decoded photo holds its full-resolution pixels until closed.
			photo?.close();
			photo = null;
		};
	});

	function setLook(next: RunShareLook) {
		if (shareLookEquals(next, look)) return;
		look = next;
		saveShareLook(next);
	}

	function statLabel(kind: RunShareStatKind): string {
		switch (kind) {
			case 'distance':
				return m('runShare.statDistance');
			case 'pace':
				return usesSpeed ? m('runShare.statSpeed') : m('runShare.statPace');
			case 'time':
				return m('runShare.statTime');
			case 'climb':
				return m('runShare.statClimb');
			case 'heartRate':
				return m('runShare.statHeartRate');
		}
	}

	function prText(r: PrCardEntry): PrCardText {
		const distance = m(PR_LABELS[r.distance]);
		const improvement = formatPrImprovement(r);
		return {
			headline: m(r.kind === 'held' ? 'runShare.prHeld' : 'runShare.prHeadline'),
			distance,
			time: formatShareDuration(r.timeS),
			improvement: improvement ? m('runShare.prFaster', { time: improvement }) : null,
			detail:
				r.previousS != null
					? m('runShare.prPrevious', { time: formatShareDuration(r.previousS) })
					: r.kind === 'first'
						? m('runShare.prFirst', { distance })
						: null,
			date: recordDate,
		};
	}

	async function renderPng(s: Style, l: RunShareLook, p: ImageBitmap | null, r: PrCardEntry | null): Promise<Blob> {
		if (s === 'card') {
			if (cardBlob?.mark !== l.mark) cardBlob = { mark: l.mark, blob: await captureCard(l.mark) };
			return cardBlob.blob;
		}
		await loadShareFonts();
		if (s === 'pr') {
			if (!r) throw new Error('no personal record to draw');
			return canvasToPng(
				paintPrCard({ aspect: l.aspect, ink: l.ink, text: prText(r), track: line, wordmark: l.mark ? 'Threkir' : null }),
			);
		}
		const stats = runShareStats(
			{
				distance: m('runShare.statDistance'),
				pace: m('runShare.statPace'),
				speed: m('runShare.statSpeed'),
				time: m('runShare.statTime'),
				climb: m('runShare.statClimb'),
				heartRate: m('runShare.statHeartRate'),
				bpm: m('runShare.unitBpm'),
			},
			run,
			getUnit(),
			{ kinds: l.stats, locale: currentLocale() },
		);
		const base = { layout: l.layout, ink: l.ink, stats, track: line, wordmark: l.mark ? 'Threkir' : null };
		const canvas =
			s === 'sticker'
				? paintSticker(base)
				: paintPhoto({ ...base, aspect: l.aspect, title, photo: p as ImageBitmap });
		return canvasToPng(canvas);
	}

	let renderSeq = 0;
	$effect(() => {
		if (!open) return;
		const s = style;
		const l = $state.snapshot(look) as RunShareLook;
		const p = photo;
		const r = record;
		if (s === 'versus' || (s === 'photo' && !p)) return;
		const key = JSON.stringify([s, l, s === 'photo' ? photoSeq : 0, s === 'pr' ? r : null]);
		if (preview?.key === key) return;
		const seq = ++renderSeq;
		rendering = true;
		renderPng(s, l, p, r)
			.then((blob) => {
				if (seq !== renderSeq) return;
				if (preview) URL.revokeObjectURL(preview.url);
				preview = { url: URL.createObjectURL(blob), blob, key };
			})
			.catch((e) => {
				if (seq !== renderSeq) return;
				console.warn('share image render failed', e);
				showToast(m('runDetail.imageGenerateFailed', { error: errorCopy(e, m, 'runDetail.imageGenerateFailed') }), 'error');
			})
			.finally(() => {
				if (seq === renderSeq) rendering = false;
			});
	});


	async function onPhotoPicked(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		picking = true;
		try {
			// Decoded with the file's orientation applied; only these pixels are
			// ever drawn, so nothing of the original file, EXIF included,
			// reaches the PNG.
			const decoded = await createImageBitmap(file, { imageOrientation: 'from-image' });
			photo?.close();
			photo = decoded;
			photoSeq++;
		} catch (err) {
			console.warn('share photo could not be decoded', err);
			showToast(m('runShare.photoError'), 'error');
		} finally {
			picking = false;
		}
	}

	function selectStyle(s: Style) {
		style = s;
		if (s === 'photo' && !photo) fileInput?.click();
	}

	let fileName = $derived(`${fileBase}-${style}.png`);
	let hasImage = $derived(style !== 'photo' || photo !== null);
	let ready = $derived(hasImage && preview !== null && !rendering && !busy);

	async function deliver(mode: 'share' | 'download') {
		if (!ready || !preview) return;
		busy = true;
		try {
			const file = new File([preview.blob], fileName, { type: 'image/png' });
			if (mode === 'share' && navigator.canShare?.({ files: [file] })) {
				await navigator.share({ title, files: [file] });
				return;
			}
			const a = document.createElement('a');
			a.href = preview.url;
			a.download = fileName;
			a.click();
			showToast(m('runDetail.imageSaved'), 'success');
		} catch (e) {
			// Cancelling the OS share sheet rejects with AbortError: not a failure.
			if (!(e instanceof DOMException && e.name === 'AbortError')) {
				showToast(m('runDetail.imageGenerateFailed', { error: errorCopy(e, m, 'runDetail.imageGenerateFailed') }), 'error');
			}
		} finally {
			busy = false;
		}
	}
</script>

<Modal {open} {onclose} title={m('runShare.title')} wide data-testid="run-share-image-dialog">
	<div class="share-editor">
		<div class="chip-row" role="radiogroup" aria-label={m('runShare.style')}>
			{#each styles as s (s.value)}
				<button
					type="button"
					role="radio"
					aria-checked={style === s.value}
					class="chip"
					class:active={style === s.value}
					disabled={busy}
					onclick={() => selectStyle(s.value)}
					data-testid="share-style-{s.value}"
				>
					<span class="material-symbols" aria-hidden="true">{s.icon}</span>
					{m(s.label)}
				</button>
			{/each}
		</div>

		{#if style === 'versus' && headToHead}
			<HeadToHeadPanel kind={headToHead.kind} targetId={headToHead.targetId} activityType={run.activity_type ?? 'run'} />
		{:else}
		<div class="preview" class:checker={style === 'sticker'} aria-busy={rendering}>
			{#if !hasImage}
				<button type="button" class="btn btn-secondary" onclick={() => fileInput?.click()} disabled={picking}>
					<span class="material-symbols" aria-hidden="true">add_photo_alternate</span>
					{m('runShare.pickPhoto')}
				</button>
			{:else if preview}
				<img
					src={preview.url}
					alt={m('runShare.preview')}
					class:dim={rendering}
					data-testid="share-image-preview"
				/>
			{:else}
				<span class="preparing" role="status">{m('runShare.preparing')}</span>
			{/if}
		</div>
		<input
			bind:this={fileInput}
			type="file"
			accept="image/jpeg,image/png,image/webp"
			class="visually-hidden"
			tabindex="-1"
			aria-hidden="true"
			onchange={onPhotoPicked}
			data-testid="share-photo-input"
		/>

		{#if style === 'photo'}
			<p class="hint">{m('runShare.photoPrivacy')}</p>
			{#if photo}
				<button type="button" class="btn btn-outline change" onclick={() => fileInput?.click()} disabled={busy || picking}>
					<span class="material-symbols" aria-hidden="true">swap_horiz</span>
					{m('runShare.changePhoto')}
				</button>
			{/if}
		{:else if style === 'sticker'}
			<p class="hint">{m('runShare.stickerHint')}</p>
		{:else if style === 'pr'}
			<p class="hint">{m('runShare.prHint')}</p>
			{#if records.length > 1}
				<fieldset class="control">
					<legend>{m('runShare.prRecord')}</legend>
					<div class="chip-row" role="radiogroup" aria-label={m('runShare.prRecord')}>
						{#each records as r, i (r.distance)}
							<button
								type="button"
								role="radio"
								aria-checked={record === r}
								class="chip"
								class:active={record === r}
								disabled={busy}
								onclick={() => (prIndex = i)}
								data-testid="share-pr-{r.distance}">{m(PR_LABELS[r.distance])}</button
							>
						{/each}
					</div>
				</fieldset>
			{/if}
		{/if}

		{#if style !== 'card'}
			{#if style !== 'pr'}
			<fieldset class="control">
				<legend>{m('runShare.layout')}</legend>
				<div class="chip-row" role="radiogroup" aria-label={m('runShare.layout')}>
					{#each RUN_STICKER_LAYOUTS as v (v)}
						<button
							type="button"
							role="radio"
							aria-checked={look.layout === v}
							class="chip"
							class:active={look.layout === v}
							disabled={busy}
							onclick={() => setLook({ ...look, layout: v })}
							data-testid="share-layout-{v}">{m(LAYOUT_LABELS[v])}</button
						>
					{/each}
				</div>
			</fieldset>
			{/if}
			<fieldset class="control">
				<legend>{m('runShare.ink')}</legend>
				<div class="chip-row" role="radiogroup" aria-label={m('runShare.ink')}>
					{#each RUN_SHARE_INKS as v (v)}
						<button
							type="button"
							role="radio"
							aria-checked={look.ink === v}
							class="chip"
							class:active={look.ink === v}
							disabled={busy}
							onclick={() => setLook({ ...look, ink: v })}
							data-testid="share-ink-{v}">{m(INK_LABELS[v])}</button
						>
					{/each}
				</div>
			</fieldset>
			{#if style === 'photo' || style === 'pr'}
				<fieldset class="control">
					<legend>{m('runShare.aspect')}</legend>
					<div class="chip-row" role="radiogroup" aria-label={m('runShare.aspect')}>
						{#each [...RUN_PHOTO_ASPECTS].reverse() as v (v)}
							<button
								type="button"
								role="radio"
								aria-checked={look.aspect === v}
								class="chip"
								class:active={look.aspect === v}
								disabled={busy}
								onclick={() => setLook({ ...look, aspect: v })}
								data-testid="share-aspect-{v}">{m(ASPECT_LABELS[v])}</button
							>
						{/each}
					</div>
				</fieldset>
			{/if}
			{#if style !== 'pr'}
			<fieldset class="control">
				<legend>{m('runShare.stats')}</legend>
				<div class="chip-row">
					{#each available as kind (kind)}
						{@const on = look.stats.includes(kind)}
						{@const locked = on ? look.stats.length <= 1 : look.stats.length >= MAX_SHARE_STATS}
						<button
							type="button"
							class="chip"
							class:active={on}
							aria-pressed={on}
							disabled={busy || locked}
							onclick={() => setLook(toggleShareStat(look, kind))}
							data-testid="share-stat-{kind}">{statLabel(kind)}</button
						>
					{/each}
				</div>
				<span class="hint">{m('runShare.statsHint', { max: MAX_SHARE_STATS })}</span>
			</fieldset>
			{/if}
		{/if}

		<label class="mark-switch">
			<input
				type="checkbox"
				checked={look.mark}
				disabled={busy}
				onchange={(e) => setLook({ ...look, mark: e.currentTarget.checked })}
				data-testid="share-mark"
			/>
			{m('runShare.mark')}
		</label>

		<div class="actions">
			{#if canShare}
				<button
					type="button"
					class="btn btn-primary"
					onclick={() => deliver('share')}
					disabled={!ready}
					data-testid="share-image-share"
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
				data-testid="share-image-download"
			>
				<span class="material-symbols" aria-hidden="true">download</span>
				{m('runShare.download')}
			</button>
		</div>
		{/if}
	</div>
</Modal>

<style>
	.share-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
		min-width: 0;
	}
	.mark-switch {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		min-height: 44px;
		cursor: pointer;
	}
	.mark-switch input {
		width: 1.25rem;
		height: 1.25rem;
		accent-color: var(--color-primary);
	}
	.chip-row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.4rem 0.9rem;
		min-height: 2.25rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		cursor: pointer;
	}
	.chip .material-symbols {
		font-size: 1.1rem;
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
	/* The sticker is transparent, so its preview sits on a checkerboard drawn
	   by the page, not in the PNG. */
	.preview.checker {
		background-color: var(--color-bg-secondary);
		background-image: conic-gradient(
			var(--color-bg-tertiary) 25%,
			transparent 0 50%,
			var(--color-bg-tertiary) 0 75%,
			transparent 0
		);
		background-size: 24px 24px;
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
	.preparing,
	.hint {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		margin: 0;
	}
	.change {
		align-self: center;
	}
	.control {
		border: 0;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		min-width: 0;
	}
	.control legend {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		padding: 0;
		margin-bottom: 0.4rem;
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
