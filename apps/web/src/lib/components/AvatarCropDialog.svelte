<script lang="ts">
	import Modal from './Modal.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import {
		AVATAR_MAX_ZOOM,
		AVATAR_MIN_ZOOM,
		initialCropState,
		panBy,
		rezoom,
		rotate,
		type CropState,
	} from '$lib/util/avatar_crop';
	import {
		drawAvatarCrop,
		encodeAvatarCrop,
		loadOrientedImage,
		sourceSize,
		type AvatarSource,
	} from '$lib/util/avatar_render';

	interface Props {
		/// The picked file. The dialog is open while this is non-null.
		file: File | null;
		onconfirm: (cropped: File) => void;
		oncancel: () => void;
	}

	let { file, onconfirm, oncancel }: Props = $props();

	// Crop geometry runs in a fixed coordinate square; the stage scales it to
	// whatever size CSS gives it, and pointer deltas are mapped back through
	// the stage's measured width.
	const VIEW = 300;
	const PREVIEW_PX = VIEW * 2;
	const KEY_STEP = 10;
	const ZOOM_STEP = 0.25;

	let source = $state<AvatarSource | null>(null);
	let crop = $state<CropState | null>(null);
	let status = $state<'loading' | 'ready' | 'failed'>('loading');
	let encoding = $state(false);
	let canvas = $state<HTMLCanvasElement | null>(null);
	let stageWidth = $state(VIEW);

	$effect(() => {
		const f = file;
		source = null;
		crop = null;
		encoding = false;
		if (!f) return;
		status = 'loading';
		let cancelled = false;
		loadOrientedImage(f).then(
			(img) => {
				if (cancelled) return;
				const { width, height } = sourceSize(img);
				if (width < 1 || height < 1) {
					status = 'failed';
					return;
				}
				source = img;
				crop = initialCropState(width, height, VIEW);
				status = 'ready';
			},
			(err) => {
				if (cancelled) return;
				console.warn('avatar crop: decode failed', err);
				status = 'failed';
			},
		);
		return () => {
			cancelled = true;
		};
	});

	$effect(() => {
		if (!canvas || !source || !crop) return;
		const ctx = canvas.getContext('2d');
		if (ctx) drawAvatarCrop(ctx, source, crop, PREVIEW_PX);
	});

	const toView = (px: number) => (px * VIEW) / Math.max(1, stageWidth);

	const pointers = new Map<number, { x: number; y: number }>();
	let pinchDistance = 0;

	function spread(): number {
		const [a, b] = [...pointers.values()];
		return Math.hypot(a.x - b.x, a.y - b.y);
	}

	function onPointerDown(e: PointerEvent) {
		if (!crop) return;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
		pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
		if (pointers.size === 2) pinchDistance = spread();
	}

	function onPointerMove(e: PointerEvent) {
		const prev = pointers.get(e.pointerId);
		if (!crop || !prev) return;
		pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
		if (pointers.size === 2) {
			const d = spread();
			if (pinchDistance > 0 && d > 0) crop = rezoom(crop, (crop.zoom * d) / pinchDistance);
			pinchDistance = d;
			return;
		}
		crop = panBy(crop, toView(e.clientX - prev.x), toView(e.clientY - prev.y));
	}

	function onPointerUp(e: PointerEvent) {
		pointers.delete(e.pointerId);
		pinchDistance = pointers.size === 2 ? spread() : 0;
	}

	function onWheel(e: WheelEvent) {
		if (!crop) return;
		e.preventDefault();
		crop = rezoom(crop, crop.zoom * Math.exp(-e.deltaY / 500));
	}

	function onStageKey(e: KeyboardEvent) {
		if (!crop) return;
		const moves: Record<string, [number, number]> = {
			ArrowLeft: [KEY_STEP, 0],
			ArrowRight: [-KEY_STEP, 0],
			ArrowUp: [0, KEY_STEP],
			ArrowDown: [0, -KEY_STEP],
		};
		const move = moves[e.key];
		if (move) {
			crop = panBy(crop, move[0], move[1]);
		} else if (e.key === '+' || e.key === '=') {
			crop = rezoom(crop, crop.zoom + ZOOM_STEP);
		} else if (e.key === '-' || e.key === '_') {
			crop = rezoom(crop, crop.zoom - ZOOM_STEP);
		} else {
			return;
		}
		e.preventDefault();
	}

	function turn(direction: 1 | -1) {
		if (crop) crop = rotate(crop, direction);
	}

	async function confirm() {
		if (!source || !crop || encoding) return;
		encoding = true;
		try {
			onconfirm(await encodeAvatarCrop(source, crop));
		} catch (err) {
			console.warn('avatar crop: encode failed', err);
			status = 'failed';
		} finally {
			encoding = false;
		}
	}
</script>

<Modal
	open={file !== null}
	title={m('avatarCrop.title')}
	narrow
	onclose={() => {
		if (!encoding) oncancel();
	}}
	data-testid="avatar-crop-dialog"
>
	<div class="crop-body">
		{#if status === 'failed'}
			<p class="crop-error" role="alert" data-testid="avatar-crop-error">{m('avatarCrop.loadFailed')}</p>
		{:else}
			<!-- svelte-ignore a11y_no_noninteractive_element_interactions role=application hands arrow keys to the stage, which pans with them -->
			<div
				class="crop-stage"
				role="application"
				tabindex="0"
				aria-label={m('avatarCrop.stageLabel')}
				aria-describedby="avatar-crop-hint"
				aria-busy={status === 'loading'}
				bind:clientWidth={stageWidth}
				onpointerdown={onPointerDown}
				onpointermove={onPointerMove}
				onpointerup={onPointerUp}
				onpointercancel={onPointerUp}
				onwheel={onWheel}
				onkeydown={onStageKey}
				data-testid="avatar-crop-stage"
			>
				<canvas bind:this={canvas} width={PREVIEW_PX} height={PREVIEW_PX} data-testid="avatar-crop-canvas"></canvas>
				<div class="crop-mask" aria-hidden="true"></div>
				{#if status === 'loading'}
					<span class="crop-loading">{m('avatarCrop.loading')}</span>
				{/if}
			</div>
			<p id="avatar-crop-hint" class="crop-hint">{m('avatarCrop.hint')}</p>
			<div class="crop-controls">
				<button
					type="button"
					class="btn btn-outline btn-sm icon-btn"
					onclick={() => turn(-1)}
					disabled={!crop}
					aria-label={m('avatarCrop.rotateLeft')}
					title={m('avatarCrop.rotateLeft')}
					data-testid="avatar-crop-rotate-left"
				>
					<span class="material-symbols" aria-hidden="true">rotate_left</span>
				</button>
				<label class="zoom">
					<span class="zoom-label">{m('avatarCrop.zoom')}</span>
					<input
						type="range"
						min={AVATAR_MIN_ZOOM}
						max={AVATAR_MAX_ZOOM}
						step="0.01"
						value={crop?.zoom ?? 1}
						disabled={!crop}
						oninput={(e) => {
							if (crop) crop = rezoom(crop, Number((e.currentTarget as HTMLInputElement).value));
						}}
						data-testid="avatar-crop-zoom"
					/>
				</label>
				<button
					type="button"
					class="btn btn-outline btn-sm icon-btn"
					onclick={() => turn(1)}
					disabled={!crop}
					aria-label={m('avatarCrop.rotateRight')}
					title={m('avatarCrop.rotateRight')}
					data-testid="avatar-crop-rotate-right"
				>
					<span class="material-symbols" aria-hidden="true">rotate_right</span>
				</button>
			</div>
		{/if}
		<div class="actions">
			<button
				type="button"
				class="btn btn-secondary"
				onclick={oncancel}
				disabled={encoding}
				data-testid="avatar-crop-cancel"
			>
				{m('common.cancel')}
			</button>
			<button
				type="button"
				class="btn btn-primary"
				onclick={confirm}
				disabled={status !== 'ready' || encoding}
				aria-busy={encoding}
				data-testid="avatar-crop-confirm"
			>
				{m('avatarCrop.confirm')}
			</button>
		</div>
	</div>
</Modal>

<style>
	.crop-body {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.crop-stage {
		position: relative;
		width: min(18rem, 100%);
		aspect-ratio: 1;
		margin: 0 auto;
		overflow: hidden;
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
		touch-action: none;
		cursor: grab;
		user-select: none;
	}
	.crop-stage:active {
		cursor: grabbing;
	}
	.crop-stage:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 3px;
	}
	.crop-stage canvas {
		display: block;
		width: 100%;
		height: 100%;
	}
	/* Avatars render as circles everywhere, so the kept region is shown as one;
	   the square corners outside it are dimmed but still uploaded. */
	.crop-mask {
		position: absolute;
		inset: 0;
		border-radius: 50%;
		box-shadow: 0 0 0 100vmax rgb(0 0 0 / 0.5);
		pointer-events: none;
	}
	.crop-loading {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
		color: var(--color-text);
		font-size: 0.88rem;
	}
	.crop-hint {
		margin: 0;
		font-size: 0.82rem;
		color: var(--color-text-secondary);
		text-align: center;
	}
	.crop-controls {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.icon-btn {
		display: inline-grid;
		place-items: center;
		min-width: 2.75rem;
		min-height: 2.75rem;
	}
	.zoom {
		flex: 1;
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		font-size: 0.82rem;
		color: var(--color-text-secondary);
	}
	.zoom input {
		flex: 1;
		min-width: 0;
	}
	.crop-error {
		margin: 0;
		color: var(--color-danger-text);
		font-size: 0.88rem;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
