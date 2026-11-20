import type { MessageKey } from '../i18n/messages.ts';
import type { ParkCourseAttempt, ParkCourseAttemptOutcome } from '../types.ts';
import { formatShortDistance } from '../format/short_distance.ts';
import { regionSlug } from './park_courses.ts';

// The card a run's owner sees for a park course the run started and got no
// time on. Pure (unit, locale and the translator passed in) so it tests
// without the runes modules `tsx --test` cannot compile.

type Translate = (key: MessageKey, params?: Record<string, string | number>) => string;

const REASON_KEY = {
	stopped_short: 'runDetail.parkCourseAttemptStoppedShort',
	skipped_checkpoint: 'runDetail.parkCourseAttemptSkippedCheckpoint',
	off_course: 'runDetail.parkCourseAttemptOffCourse',
	gps_gap: 'runDetail.parkCourseAttemptGpsGap',
	wrong_direction: 'runDetail.parkCourseAttemptWrongDirection',
} as const satisfies Record<ParkCourseAttemptOutcome, MessageKey>;

export interface AttemptCard {
	href: string;
	reason: string;
	/** "1.20 km of 5.00 km": the bar's visible text and its spoken value. */
	progress: string;
	/** 0..1, how full the bar is. */
	fraction: number;
	/** The bar's accessible name. */
	barLabel: string;
}

export function attemptHref(a: ParkCourseAttempt): string {
	return `/parks/${regionSlug(a.region)}/${a.parkSlug}/${a.courseSlug}`;
}

export function attemptFraction(a: ParkCourseAttempt): number {
	if (!(a.courseM > 0) || !Number.isFinite(a.progressM)) return 0;
	return Math.min(1, Math.max(0, a.progressM / a.courseM));
}

export function attemptCard(a: ParkCourseAttempt, unit: 'km' | 'mi', locale: string, t: Translate): AttemptCard {
	const nf = new Intl.NumberFormat(locale, { useGrouping: false });
	const clamped = Math.min(Math.max(a.progressM, 0), a.courseM);
	const progress = formatShortDistance(clamped, unit, locale);
	const total = formatShortDistance(a.courseM, unit, locale);
	const reason = t(REASON_KEY[a.outcome], {
		course: a.courseName,
		progress,
		total,
		n: nf.format(a.missedCheckpoint ?? 0),
		count: nf.format(a.checkpointCount),
	});
	return {
		href: attemptHref(a),
		reason,
		progress: t('runDetail.parkCourseAttemptProgress', { progress, total }),
		fraction: attemptFraction(a),
		barLabel: t('runDetail.parkCourseAttemptBarLabel', { course: a.courseName }),
	};
}
