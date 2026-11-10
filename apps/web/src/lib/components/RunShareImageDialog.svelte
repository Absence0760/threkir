<script lang="ts">
	// The run share-image editor: the map card, the runner's own photo, or a
	// transparent sticker, in the layouts, inks, aspects and stats the phone's
	// share sheet offers (run_share_card.dart), and the occasion stickers the run
	// qualifies for. The preview IS the export: each
	// change re-renders the PNG that Share and Download hand over. On a photo,
	// the title-and-stats block is moved and resized right on the preview.
	import { untrack } from 'svelte';
	import Modal from '#lib/components/Modal.svelte';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { currentLocale } from '#lib/i18n/store.svelte.ts';
	import { formatPaceNoSuffix, getUnit } from '#lib/format/units.svelte.ts';
	import type { Split } from '#lib/runs/run_stats.ts';
	import type { AchievementTier } from '#lib/types.ts';
	import { tierFor } from '#lib/social/badges.ts';
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
		offeredStickerKinds,
		stickerKindFor,
		averageStickerPace,
		type RunStickerKind,
		type SplitsStickerRow,
		saveShareLook,
		shareLookEquals,
		toggleShareStat,
		withSharePlacement,
		type RunShareLook,
	} from '#lib/share/share_look.ts';
	import {
		canvasToPng,
		loadShareFonts,
		paintPhoto,
		paintSticker,
		photoCanvasSize,
		badgeStickerBody,
		prStickerBody,
		raceStickerBody,
		courseStickerBody,
		routeStickerBody,
		streakStickerBody,
		type PhotoLaid,
		type StickerBody,
	} from '#lib/share/run_sticker_canvas.ts';
	import {
		DEFAULT_SHARE_PLACEMENT,
		moveSharePlacement,
		placeShareBlock,
		resizeSharePlacement,
		sharePlacementEquals,
		type SharePlacement,
	} from '#lib/share/share_placement.ts';
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
		/// Shown on a run nobody else can open yet: an image shares no link.
		linkHint?: string | null;
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
		/// The run's splits, computed on the run page from the full track (never
		/// from the clipped line, which would drop the first and last km), and
		/// the tick they were cut at.
		splits?: Split[];
		splitTickMetres?: number;
		/// The streak day this run was, as of its own day.
		streakDays?: number;
		/// The race this run finished, with its official time when stamped.
		race?: { name: string; time: string | null } | null;
		/// The single-run distance badge this run earned.
		badge?: { badgeKey: string; tier: AchievementTier } | null;
		/// The park course time this run set (`pickShareCourse`), with its
		/// place on that season's board when it holds one.
		course?: { name: string; park: string; timeS: number; season: number; rank: number | null } | null;
	}

	let {
		open,
		onclose,
		run,
		linkHint = null,
		title,
		line,
		captureCard,
		fileBase,
		records = [],
		recordDate = '',
		initialStyle = 'card',
		headToHead = null,
		splits = [],
		splitTickMetres = 1000,
		streakDays = 0,
		race = null,
		badge = null,
		course = null,
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
	const KIND_LABELS: Record<RunStickerKind, MessageKey> = {
		stats: 'runShare.kindStats',
		splits: 'runShare.kindSplits',
		pr: 'runShare.kindPr',
		streak: 'runShare.kindStreak',
		race: 'runShare.kindRace',
		course: 'runShare.kindCourse',
		badge: 'runShare.kindBadge',
		route: 'runShare.layoutRoute',
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
	/// The layout the last photo render drew, which the move/resize handle
	/// sits on, so the handle covers what the PNG shows.
	let photoLaid = $state<PhotoLaid | null>(null);
	let areaW = $state(0);
	let areaH = $state(0);
	let gesturing = $state(false);

	let available = $derived(availableShareStats(run));
	let usesSpeed = $derived(run.activity_type === 'cycle');
	let offeredKinds = $derived(
		offeredStickerKinds({
			splits: splits.length,
			records: records.length,
			streakDays,
			race: race !== null,
			course: course !== null,
			badge: badge !== null,
			route: line.length >= 2,
		}),
	);
	/// The kind this run prints: the remembered one when the run has its data.
	let kind = $derived(stickerKindFor(look.kind, offeredKinds));
	let usesKinds = $derived(style === 'sticker' || style === 'photo');

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
			photoLaid = null;
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

	function splitsBody(): StickerBody {
		const unit = getUnit();
		const decimal = new Intl.NumberFormat(currentLocale(), { minimumFractionDigits: 1, maximumFractionDigits: 1 });
		const rows: SplitsStickerRow[] = splits.map((sp) => ({
			paceSecPerKm: sp.pace_s,
			metres: sp.distance_m,
			partial: sp.distance_m < splitTickMetres - 1,
		}));
		const avg = averageStickerPace(rows);
		return {
			kind: 'splits',
			heading: m('runShare.splitsHeading', {
				count: splits.length,
				pace: avg != null ? `${formatPaceNoSuffix(avg, 1000)} /${unit}` : '--:--',
			}),
			entries: splits.map((sp, i) => ({
				label: rows[i].partial ? `${decimal.format(sp.distance_m / splitTickMetres)} ${unit}` : String(sp.km),
				pace: formatPaceNoSuffix(sp.pace_s, 1000),
				row: rows[i],
			})),
		};
	}

	/// The occasion sticker for `k`, or null for `stats`, which the layouts draw.
	function occasionBody(k: RunStickerKind, r: PrCardEntry | null): StickerBody | null {
		const hasRoute = line.length >= 2;
		switch (k) {
			case 'stats':
				return null;
			case 'splits':
				return splitsBody();
			case 'pr': {
				if (!r) throw new Error('no personal record to draw');
				const t = prText(r);
				return prStickerBody({ headline: t.headline, distance: t.distance, time: t.time, improvement: t.improvement }, hasRoute);
			}
			case 'streak':
				return streakStickerBody({
					kicker: m('runShare.kindStreak'),
					days: new Intl.NumberFormat(currentLocale()).format(streakDays),
					caption: m('runShare.streakCaption'),
				});
			case 'race':
				return raceStickerBody({ name: race!.name, finisher: m('runShare.raceFinisher'), time: race!.time }, hasRoute);
			case 'course': {
				const c = course!;
				const nf = new Intl.NumberFormat(currentLocale(), { useGrouping: false });
				return courseStickerBody(
					{
						kicker: m('runShare.courseKicker'),
						name: c.name,
						park: c.park,
						time: formatShareDuration(c.timeS),
						rank: c.rank != null ? m('runShare.courseRank', { rank: nf.format(c.rank), season: nf.format(c.season) }) : null,
					},
					hasRoute,
				);
			}
			case 'badge': {
				const t = tierFor(badge!.badgeKey, badge!.tier);
				return badgeStickerBody({
					kicker: m('runShare.badgeKicker'),
					name: t ? m(t.labelKey) : badge!.badgeKey,
					tier: m(`badges.tier.${badge!.tier}` as MessageKey),
				});
			}
			case 'route':
				return routeStickerBody();
		}
	}

	interface Rendered {
		blob: Blob;
		laid: PhotoLaid | null;
	}

	async function renderPng(
		s: Style,
		l: RunShareLook,
		k: RunStickerKind,
		p: ImageBitmap | null,
		r: PrCardEntry | null,
	): Promise<Rendered> {
		if (s === 'card') {
			if (cardBlob?.mark !== l.mark) cardBlob = { mark: l.mark, blob: await captureCard(l.mark) };
			return { blob: cardBlob.blob, laid: null };
		}
		await loadShareFonts();
		if (s === 'pr') {
			if (!r) throw new Error('no personal record to draw');
			const blob = await canvasToPng(
				paintPrCard({ aspect: l.aspect, ink: l.ink, text: prText(r), track: line, wordmark: l.mark ? 'Threkir' : null }),
			);
			return { blob, laid: null };
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
		const body: StickerBody = occasionBody(k, r) ?? { kind: 'stats', layout: l.layout, stats, hasRoute: line.length >= 2 };
		const base = { body, ink: l.ink, track: line, wordmark: l.mark ? 'Threkir' : null };
		if (s === 'sticker') return { blob: await canvasToPng(paintSticker(base)), laid: null };
		const painted = paintPhoto({
			...base,
			aspect: l.aspect,
			placement: l.placements[l.aspect],
			title,
			photo: p as ImageBitmap,
		});
		return { blob: await canvasToPng(painted.canvas), laid: painted.laid };
	}

	let renderSeq = 0;
	$effect(() => {
		if (!open) return;
		const s = style;
		const l = $state.snapshot(look) as RunShareLook;
		const p = photo;
		const r = record;
		const k = kind;
		if (s === 'versus' || (s === 'photo' && !p)) return;
		const occasion = k === 'stats' ? null : [k, r, streakDays, race, course, badge, splits.length];
		const key = JSON.stringify([s, l, s === 'photo' ? photoSeq : 0, s === 'pr' ? r : null, occasion]);
		if (preview?.key === key) return;
		const seq = ++renderSeq;
		rendering = true;
		renderPng(s, l, k, p, r)
			.then(({ blob, laid }) => {
				if (seq !== renderSeq) return;
				if (preview) URL.revokeObjectURL(preview.url);
				preview = { url: URL.createObjectURL(blob), blob, key };
				if (laid) photoLaid = laid;
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

	// ---- moving and resizing the photo's title-and-stats block ----

	let canvasSize = $derived(photoCanvasSize(look.aspect));
	let placement = $derived(look.placements[look.aspect]);
	/// The preview's size: the canvas fitted inside the preview area.
	let stage = $derived.by(() => {
		const k = Math.min(areaW / canvasSize.w, areaH / canvasSize.h);
		return k > 0 ? { w: canvasSize.w * k, h: canvasSize.h * k, k } : null;
	});
	/// Where the block is, from the layout last drawn at this aspect. The
	/// block's own size does not depend on where it sits, so a drag reads it
	/// while the next render is still on its way.
	let handle = $derived.by(() => {
		const laid = photoLaid;
		const { w, h } = canvasSize;
		if (style !== 'photo' || !photo || !laid || laid.width !== w || laid.height !== h) return null;
		return placeShareBlock(placement, laid.blockWidth, laid.blockHeight, w, h, laid.frame, laid.minScale);
	});
	let isDefaultPlacement = $derived(sharePlacementEquals(placement, DEFAULT_SHARE_PLACEMENT));

	/// `next`, clamped into the frame, as the current aspect's placement. The
	/// store write is left to the end of a gesture.
	function place(next: SharePlacement, save: boolean) {
		const laid = photoLaid;
		if (!laid) return;
		const { w, h } = canvasSize;
		const clamped = placeShareBlock(next, laid.blockWidth, laid.blockHeight, w, h, laid.frame, laid.minScale).placement;
		const updated = withSharePlacement(look, clamped);
		if (!shareLookEquals(updated, look)) look = updated;
		if (save) saveShareLook(look);
	}

	function resetPlacement() {
		setLook(withSharePlacement(look, DEFAULT_SHARE_PLACEMENT));
	}

	type GestureKind = 'moving' | 'sizing' | 'pinching';
	interface Gesture {
		mode: GestureKind;
		from: SharePlacement;
		x: number;
		y: number;
		dist: number;
	}
	const pointers = new Map<number, { x: number; y: number }>();
	let gesture: Gesture | null = null;

	function spread(): number {
		const [a, b] = [...pointers.values()];
		return Math.hypot(a.x - b.x, a.y - b.y);
	}

	/// The block's centre on screen, which the corner grip resizes about.
	function centreOnScreen(el: HTMLElement): { x: number; y: number } {
		const r = el.getBoundingClientRect();
		return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
	}

	function begin(mode: GestureKind, e: PointerEvent, el: HTMLElement) {
		const from = handle?.placement ?? placement;
		if (mode === 'pinching') {
			gesture = { mode, from, x: 0, y: 0, dist: Math.max(1, spread()) };
		} else if (mode === 'sizing') {
			const c = centreOnScreen(el);
			gesture = { mode, from, x: c.x, y: c.y, dist: Math.max(1, Math.hypot(e.clientX - c.x, e.clientY - c.y)) };
		} else {
			gesture = { mode, from, x: e.clientX, y: e.clientY, dist: 0 };
		}
	}

	function onStagePointerDown(e: PointerEvent) {
		if (!handle || busy || e.button !== 0) return;
		const target = e.target as HTMLElement;
		const block = (e.currentTarget as HTMLElement).querySelector<HTMLElement>('[data-share-block]');
		// A gesture starts on the block; elsewhere the preview scrolls the
		// sheet as it always did. A second finger may land anywhere.
		if (pointers.size === 0 && !target.closest('[data-share-block]')) return;
		e.preventDefault();
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
		pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
		gesturing = true;
		if (pointers.size === 2) begin('pinching', e, block!);
		else if (pointers.size === 1) begin(target.closest('[data-share-grip]') ? 'sizing' : 'moving', e, block!);
	}

	function onStagePointerMove(e: PointerEvent) {
		if (!pointers.has(e.pointerId) || !gesture || !stage) return;
		pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
		const g = gesture;
		if (g.mode === 'pinching' && pointers.size >= 2) {
			place(resizeSharePlacement(g.from, spread() / g.dist), false);
		} else if (g.mode === 'sizing') {
			place(resizeSharePlacement(g.from, Math.hypot(e.clientX - g.x, e.clientY - g.y) / g.dist), false);
		} else if (g.mode === 'moving') {
			const { w, h } = canvasSize;
			place(moveSharePlacement(g.from, (e.clientX - g.x) / stage.k, (e.clientY - g.y) / stage.k, w, h), false);
		}
	}

	function onStagePointerUp(e: PointerEvent) {
		if (!pointers.delete(e.pointerId)) return;
		if (pointers.size === 1 && gesture?.mode === 'pinching') {
			// One finger lifted mid-pinch: the other carries on as a move from
			// where the block now is.
			const [rest] = [...pointers.values()];
			gesture = { mode: 'moving', from: handle?.placement ?? placement, x: rest.x, y: rest.y, dist: 0 };
			return;
		}
		if (pointers.size > 0) return;
		gesture = null;
		gesturing = false;
		saveShareLook(look);
	}

	function onBlockWheel(e: WheelEvent) {
		if (!handle || busy) return;
		e.preventDefault();
		place(resizeSharePlacement(handle.placement, Math.exp(-e.deltaY * 0.0015)), true);
	}

	/// Arrow keys move the block by 4 logical px (20 with Shift); + and −
	/// resize it by a tenth.
	function onBlockKey(e: KeyboardEvent) {
		if (!handle || busy) return;
		const step = e.shiftKey ? 20 : 4;
		const { w, h } = canvasSize;
		const from = handle.placement;
		let next: SharePlacement | null = null;
		switch (e.key) {
			case 'ArrowLeft':
				next = moveSharePlacement(from, -step, 0, w, h);
				break;
			case 'ArrowRight':
				next = moveSharePlacement(from, step, 0, w, h);
				break;
			case 'ArrowUp':
				next = moveSharePlacement(from, 0, -step, w, h);
				break;
			case 'ArrowDown':
				next = moveSharePlacement(from, 0, step, w, h);
				break;
			case '+':
			case '=':
				next = resizeSharePlacement(from, 1.1);
				break;
			case '-':
			case '_':
				next = resizeSharePlacement(from, 1 / 1.1);
				break;
		}
		if (!next) return;
		e.preventDefault();
		place(next, true);
	}

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
		{#if linkHint}
			<p class="hint" data-testid="share-image-link-hint">{linkHint}</p>
		{/if}
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
			{:else if preview && style === 'photo'}
				<div class="stage-area" bind:clientWidth={areaW} bind:clientHeight={areaH}>
					{#if stage}
						<!-- svelte-ignore a11y_no_static_element_interactions the stage only carries a gesture begun on the focusable block, so a second finger may land beside it -->
						<div
							class="stage"
							style:width="{stage.w}px"
							style:height="{stage.h}px"
							onpointerdown={onStagePointerDown}
							onpointermove={onStagePointerMove}
							onpointerup={onStagePointerUp}
							onpointercancel={onStagePointerUp}
						>
							<img
								src={preview.url}
								alt={m('runShare.preview')}
								class:dim={rendering && !gesturing}
								draggable="false"
								data-testid="share-image-preview"
							/>
							{#if handle}
								<!-- svelte-ignore a11y_no_noninteractive_element_interactions role=application hands arrow keys and +/- to the block, which moves and resizes with them -->
								<div
									class="block"
									class:active={gesturing}
									style:left="{(handle.left / canvasSize.w) * 100}%"
									style:top="{(handle.top / canvasSize.h) * 100}%"
									style:width="{(handle.width / canvasSize.w) * 100}%"
									style:height="{(handle.height / canvasSize.h) * 100}%"
									role="application"
									tabindex="0"
									aria-label={m('runShare.placementLabel')}
									aria-describedby="share-placement-hint"
									onkeydown={onBlockKey}
									onwheel={onBlockWheel}
									data-share-block
									data-testid="share-placement-block"
								>
									<span class="grip" data-share-grip data-testid="share-placement-grip" aria-hidden="true"></span>
								</div>
							{/if}
						</div>
					{/if}
				</div>
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
				<p class="hint" id="share-placement-hint">{m('runShare.placementHint')}</p>
				<div class="photo-actions">
					<button type="button" class="btn btn-outline" onclick={() => fileInput?.click()} disabled={busy || picking}>
						<span class="material-symbols" aria-hidden="true">swap_horiz</span>
						{m('runShare.changePhoto')}
					</button>
					<button
						type="button"
						class="btn btn-outline"
						onclick={resetPlacement}
						disabled={busy || isDefaultPlacement}
						data-testid="share-placement-reset"
					>
						<span class="material-symbols" aria-hidden="true">undo</span>
						{m('runShare.placementReset')}
					</button>
				</div>
			{/if}
		{:else if style === 'sticker'}
			<p class="hint">{m('runShare.stickerHint')}</p>
		{:else if style === 'pr'}
			<p class="hint">{m('runShare.prHint')}</p>
		{/if}

		{#if usesKinds && offeredKinds.length > 1}
			<fieldset class="control">
				<legend>{m('runShare.kind')}</legend>
				<div class="chip-row" role="radiogroup" aria-label={m('runShare.kind')}>
					{#each offeredKinds as v (v)}
						<button
							type="button"
							role="radio"
							aria-checked={kind === v}
							class="chip"
							class:active={kind === v}
							disabled={busy}
							onclick={() => setLook({ ...look, kind: v })}
							data-testid="share-kind-{v}">{m(KIND_LABELS[v])}</button
						>
					{/each}
				</div>
			</fieldset>
		{/if}

		{#if style === 'pr' || (usesKinds && kind === 'pr')}
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
			{#if style !== 'pr' && kind === 'stats'}
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
			{#if style !== 'pr' && kind === 'stats'}
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
	.photo-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-sm);
		justify-content: center;
	}
	.stage-area {
		width: 100%;
		height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		min-width: 0;
	}
	.stage {
		position: relative;
		flex: none;
	}
	.stage img {
		display: block;
		width: 100%;
		height: 100%;
		max-width: none;
		max-height: none;
		user-select: none;
	}
	/* The block's handle: invisible over the drawn stats until it is hovered,
	   focused or held, so the preview still reads as the export. */
	.block {
		position: absolute;
		box-sizing: border-box;
		border: 2px dashed transparent;
		border-radius: var(--radius-sm);
		cursor: move;
		/* The browser must not pan or zoom the page under a drag that starts
		   on the block; anywhere else on the preview, it still scrolls. */
		touch-action: none;
	}
	.block:hover,
	.block:focus-visible,
	.block.active {
		border-color: var(--color-on-primary);
		box-shadow: 0 0 0 1px var(--color-primary);
		outline: none;
	}
	.grip {
		position: absolute;
		inset-inline-end: -10px;
		bottom: -10px;
		width: 20px;
		height: 20px;
		border-radius: 50%;
		background: var(--color-primary);
		border: 2px solid var(--color-on-primary);
		cursor: nwse-resize;
		opacity: 0;
	}
	.block:hover .grip,
	.block:focus-visible .grip,
	.block.active .grip {
		opacity: 1;
	}
	@media (hover: none) {
		.grip {
			opacity: 1;
		}
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
