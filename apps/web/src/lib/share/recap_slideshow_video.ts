/// Browser glue for the recap slideshow video (decisions § 2269): draws each
/// frame of the plan `recap_slideshow.ts` made on a 1080x1920 canvas and hands
/// it to the shared encoder sink. No map and no tiles: the slides are type and
/// bars only, so nothing here waits on the network or needs cookie consent.
import { OG_CARD_DARK } from './og_card_palette';
import {
	recapSlides,
	slideshowFrame,
	slideshowTimeline,
	type RecapSlide,
	type RecapSlideFormat,
} from './recap_slideshow';
import type { YearInRunningRecap } from '../runs/recap';
import { VIDEO_HEIGHT, VIDEO_WIDTH } from '../video/frame_clock';
import { createFrameSink, videoAbortError, type FrameSink } from '../video/encode_video';
import type { VideoEncoderPlan } from '../video/video_encoder';

const W = VIDEO_WIDTH;
const H = VIDEO_HEIGHT;
const PAD = 88;
const INNER = W - PAD * 2;
const CX = W / 2;
// A story viewer's progress bar and avatar sit in the top band and its reply
// box in the bottom one, so nothing that has to be read goes there.
const SAFE_TOP = 250;
const FONT = 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';
const C = OG_CARD_DARK;

export interface RecapSlideshowInput {
	recap: YearInRunningRecap;
	/// The recap page's own formatters and strings (`recapSlides`).
	format: RecapSlideFormat;
	plan: VideoEncoderPlan;
	signal: AbortSignal;
	onprogress: (fraction: number) => void;
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
	return new Promise((resolve) => {
		const img = new Image();
		img.onload = () => resolve(img);
		img.onerror = () => resolve(null);
		img.src = src;
	});
}

const ease = (x: number) => 1 - (1 - x) ** 3;

/// Shrinks the type until the line fits rather than cutting it: a recap's
/// headline number is the one thing that must survive whole.
function text(
	ctx: CanvasRenderingContext2D,
	s: string,
	y: number,
	size: number,
	opts: { weight?: number; color?: string; spacing?: number } = {},
) {
	let px = size;
	const font = () => `${opts.weight ?? 800} ${px}px ${FONT}`;
	ctx.font = font();
	ctx.letterSpacing = `${opts.spacing ?? 0}px`;
	while (px > 12 && ctx.measureText(s).width > INNER) {
		px = Math.floor(px * 0.92);
		ctx.font = font();
	}
	ctx.textAlign = 'center';
	ctx.textBaseline = 'alphabetic';
	ctx.fillStyle = opts.color ?? C.hero;
	ctx.fillText(s, CX, y);
	ctx.letterSpacing = '0px';
}

/// `dy` lowers the slide's content, not its background or header, so a slide
/// rises into place as it fades in while the brand stays put.
function drawSlide(
	ctx: CanvasRenderingContext2D,
	slide: RecapSlide,
	progress: number,
	mark: HTMLImageElement | null,
	dy = 0,
) {
	ctx.fillStyle = C.bg;
	ctx.fillRect(0, 0, W, H);
	if (slide.kind !== 'end') {
		ctx.font = `800 44px ${FONT}`;
		ctx.textAlign = 'left';
		ctx.fillStyle = C.brand;
		ctx.fillText('Threkir', PAD, SAFE_TOP + 60);
		if (mark) ctx.drawImage(mark, W - PAD - 72, SAFE_TOP + 4, 72, 72);
	}
	ctx.save();
	ctx.translate(0, dy);
	switch (slide.kind) {
		case 'title':
			text(ctx, slide.kicker.toLocaleUpperCase(), 800, 44, { weight: 700, color: C.label, spacing: 4 });
			text(ctx, slide.hero, 1010, 200, { weight: 900 });
			text(ctx, slide.subhead, 1110, 60, { weight: 600, color: C.stat });
			break;
		case 'stat':
			text(ctx, slide.label.toLocaleUpperCase(), 820, 48, { weight: 700, color: C.label, spacing: 4 });
			text(ctx, slide.value, 1020, 180, { weight: 900 });
			if (slide.sub) text(ctx, slide.sub, 1120, 56, { weight: 600, color: C.stat });
			break;
		case 'months': {
			text(ctx, slide.label.toLocaleUpperCase(), 560, 48, { weight: 700, color: C.label, spacing: 4 });
			text(ctx, slide.value, 720, 150, { weight: 900 });
			text(ctx, slide.sub, 810, 56, { weight: 600, color: C.stat });
			const top = 900;
			const bottom = 1440;
			const gap = 14;
			const bw = (INNER - gap * 11) / 12;
			const grow = ease(Math.min(1, progress * 2.5));
			slide.bars.forEach((b, i) => {
				const x = PAD + i * (bw + gap);
				const h = Math.max(8, (bottom - top) * b.frac * grow);
				ctx.fillStyle = b.peak ? C.brand : 'rgba(228, 225, 234, 0.35)';
				ctx.beginPath();
				ctx.roundRect(x, bottom - h, bw, h, 10);
				ctx.fill();
				ctx.font = `700 36px ${FONT}`;
				ctx.textAlign = 'center';
				ctx.fillStyle = b.peak ? C.hero : C.label;
				ctx.fillText(b.letter, x + bw / 2, bottom + 60);
			});
			break;
		}
		case 'badges':
			text(ctx, slide.label.toLocaleUpperCase(), 620, 48, { weight: 700, color: C.label, spacing: 4 });
			text(ctx, slide.sub, 710, 56, { weight: 600, color: C.stat });
			slide.items.forEach((item, i) => {
				text(ctx, item, 900 + i * 140, 76, { weight: 800 });
			});
			break;
		case 'end':
			if (mark) ctx.drawImage(mark, CX - 120, 600, 240, 240);
			text(ctx, 'Threkir', 1010, 130, { weight: 900 });
			text(ctx, slide.line, 1110, 56, { weight: 700, color: C.stat });
			text(ctx, slide.url, 1210, 52, { weight: 700, color: C.brand });
			break;
	}
	ctx.restore();
}

export async function renderRecapSlideshow(input: RecapSlideshowInput): Promise<Blob> {
	const { signal } = input;
	if (signal.aborted) throw videoAbortError();
	const slides = recapSlides(input.recap, input.format);
	const tl = slideshowTimeline(slides);
	const out = document.createElement('canvas');
	out.width = W;
	out.height = H;
	const ctx = out.getContext('2d');
	// The previous slide is drawn once per crossfade onto its own canvas, so
	// a fade costs one image copy a frame rather than two full redraws.
	const under = document.createElement('canvas');
	under.width = W;
	under.height = H;
	const underCtx = under.getContext('2d');
	if (!ctx || !underCtx) throw new Error('no 2D canvas');
	const mark = await loadImage('/logo-mark.svg');
	let sink: FrameSink | null = createFrameSink(input.plan, out, tl.fps);
	let underSlide = -1;
	try {
		for (let i = 0; i < tl.totalFrames; i++) {
			if (signal.aborted) throw videoAbortError();
			const f = slideshowFrame(tl, i);
			const slide = slides[f.slide];
			if (f.enter < 1) {
				if (underSlide !== f.slide - 1) {
					drawSlide(underCtx, slides[f.slide - 1], 1, mark);
					underSlide = f.slide - 1;
				}
				ctx.globalAlpha = 1;
				ctx.drawImage(under, 0, 0);
				ctx.globalAlpha = ease(f.enter);
				drawSlide(ctx, slide, f.progress, mark, (1 - ease(f.enter)) * 48);
				ctx.globalAlpha = 1;
			} else {
				drawSlide(ctx, slide, f.progress, mark);
			}
			await sink.push(out, i);
			input.onprogress((i + 1) / tl.totalFrames);
		}
		const blob = await sink.finish();
		sink = null;
		return blob;
	} finally {
		sink?.abort();
	}
}
