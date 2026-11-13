/// The recap slideshow video's frame plan (decisions § 2269): which slides a
/// recap earns, what each says, and which slide frame `i` shows. The text is
/// formatted by the caller with the recap page's own formatters and catalogue
/// keys, so the video never disagrees with the page; this module only picks
/// and orders. Pure, so the plan is pinned by unit tests rather than by
/// watching a file.

import type { YearInRunningRecap } from '../runs/recap';
import { VIDEO_FPS } from '../video/frame_clock';
import { recapActiveMonths, recapBadgeText, type RecapTranslate } from './recap_card_text';

export interface RecapMonthBar {
	month: number;
	letter: string;
	/// Height as a share of the biggest month, 0..1.
	frac: number;
	peak: boolean;
}

export type RecapSlide =
	| { kind: 'title'; kicker: string; hero: string; subhead: string }
	| { kind: 'stat'; label: string; value: string; sub: string | null }
	| { kind: 'months'; label: string; value: string; sub: string; bars: RecapMonthBar[] }
	| { kind: 'badges'; label: string; sub: string; items: string[] }
	| { kind: 'end'; line: string; url: string };

export interface RecapSlideFormat {
	t: RecapTranslate;
	/// The page's eyebrow, e.g. "My 2026 in running".
	kicker: string;
	distance: (meters: number) => string;
	pace: (secPerKm: number) => string;
	weekOf: (isoDate: string) => string;
	monthName: (month: number) => string;
	monthLetter: (month: number) => string;
	/// Grouped whole number in the reader's locale.
	count: (n: number) => string;
	/// The reader's distance unit and number locale, for badge words that name
	/// a distance ("26.2 mi in one run").
	unit: 'km' | 'mi';
	locale?: string;
	url: string;
}

/// Middle slides beyond this are dropped, lowest priority first, so the file
/// stays a story-length reel (about 20 s) however rich the year.
export const MAX_MIDDLE_SLIDES = 6;
export const MAX_BADGES = 4;

export function recapSlides(recap: YearInRunningRecap, f: RecapSlideFormat): RecapSlide[] {
	const { t } = f;
	const middle: RecapSlide[] = [];
	if (recap.longestRunM > 0) {
		middle.push({
			kind: 'stat',
			label: t('recap.longestRun'),
			value: f.distance(recap.longestRunM),
			sub: t('recap.singleOuting'),
		});
	}
	if (recap.month == null && recapActiveMonths(recap) >= 2) {
		const max = Math.max(...recap.monthly.map((m) => m.distanceM));
		const peak = recap.monthly.find((m) => m.distanceM === max)!;
		middle.push({
			kind: 'months',
			label: t('recap.videoBiggestMonth'),
			value: f.monthName(peak.month),
			sub: f.distance(peak.distanceM),
			bars: recap.monthly.map((m) => ({
				month: m.month,
				letter: f.monthLetter(m.month),
				frac: max > 0 ? m.distanceM / max : 0,
				peak: m.month === peak.month,
			})),
		});
	}
	if (recap.topWeek && recap.topWeek.distanceM > 0) {
		middle.push({
			kind: 'stat',
			label: t('recap.topWeek'),
			value: f.distance(recap.topWeek.distanceM),
			sub: t('recap.weekOf', { date: f.weekOf(recap.topWeek.weekStart) }),
		});
	}
	if (recap.fastestPaceSecPerKm != null && recap.fastestPaceSecPerKm > 0) {
		middle.push({
			kind: 'stat',
			label: t('recap.fastestPace'),
			value: f.pace(recap.fastestPaceSecPerKm),
			sub: t('recap.fastestPaceSub'),
		});
	}
	if (recap.bestStreakDays >= 2) {
		middle.push({
			kind: 'stat',
			label: t('recap.bestStreak'),
			value: t('recap.cardStreakDays', { n: recap.bestStreakDays }),
			sub: t('recap.consecutiveRunDays'),
		});
	}
	if (Math.round(recap.totalElevationM) > 0) {
		middle.push({
			kind: 'stat',
			label: t('recap.cardClimbed'),
			value: `${f.count(Math.round(recap.totalElevationM))} m`,
			sub: null,
		});
	}
	if (recap.personalRecordCount > 0) {
		middle.push({
			kind: 'stat',
			label: t('recap.personalRecords'),
			value: f.count(recap.personalRecordCount),
			sub: t('recap.setThisYear'),
		});
	}
	if (recap.badges.length > 0) {
		middle.push({
			kind: 'badges',
			label: t('recap.trophies'),
			sub: t('recap.earnedInYear', { n: recap.badges.length, year: recap.year }),
			items: recap.badges.slice(0, MAX_BADGES).map((b) => recapBadgeText(b, t, f.unit, f.locale).label),
		});
	}
	return [
		{
			kind: 'title',
			kicker: f.kicker,
			hero: f.distance(recap.totalDistanceM),
			subhead: t('recap.acrossRuns', { n: recap.runCount }),
		},
		...middle.slice(0, MAX_MIDDLE_SLIDES),
		{ kind: 'end', line: f.kicker, url: f.url },
	];
}

export const SLIDE_SECONDS: Record<RecapSlide['kind'], number> = {
	title: 3,
	stat: 2.5,
	months: 3.5,
	badges: 3,
	end: 3,
};
/// Each slide crossfades in over the one before it for this long.
export const FADE_SECONDS = 0.4;

export interface SlideshowTimeline {
	fps: number;
	/// First frame of each slide.
	starts: number[];
	frames: number[];
	totalFrames: number;
}

export function slideshowTimeline(slides: readonly RecapSlide[], fps = VIDEO_FPS): SlideshowTimeline {
	const frames = slides.map((s) => Math.round(SLIDE_SECONDS[s.kind] * fps));
	const starts: number[] = [];
	let at = 0;
	for (const n of frames) {
		starts.push(at);
		at += n;
	}
	return { fps, starts, frames, totalFrames: at };
}

export interface SlideshowFrame {
	slide: number;
	/// 0 on the slide's first frame, 1 on its last.
	progress: number;
	/// 0..1, how far the slide has faded in over the previous one; always 1 on
	/// the first slide, which has nothing to fade from.
	enter: number;
}

export function slideshowFrame(tl: SlideshowTimeline, index: number): SlideshowFrame {
	const i = Math.min(Math.max(0, Math.floor(index)), tl.totalFrames - 1);
	let slide = tl.starts.length - 1;
	while (slide > 0 && tl.starts[slide] > i) slide--;
	const local = i - tl.starts[slide];
	const n = tl.frames[slide];
	const fade = Math.max(1, Math.round(FADE_SECONDS * tl.fps));
	return {
		slide,
		progress: n > 1 ? local / (n - 1) : 1,
		enter: slide === 0 ? 1 : Math.min(1, local / fade),
	};
}
