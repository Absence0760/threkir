import type { MessageKey } from '../i18n/messages.ts';
import type {
	CourseDifficulty,
	CourseShape,
	CourseStatus,
	GeometrySource,
	ParkAgency,
	ParkKind,
} from './park_courses.ts';

// Each value names its catalogue key literally, so the area-catalogue split
// (decisions § 1802) can see which route renders it.

export const AGENCY_LABEL: Record<ParkAgency, MessageKey> = {
	nps: 'parks.agencyNps',
	state: 'parks.agencyState',
	county: 'parks.agencyCounty',
	other: 'parks.agencyOther',
};

/**
 * A catalogue entry's kind, where it names the place: a trail reads "Trail"
 * whoever runs it, and a park reads as its agency (`null` here).
 */
export const KIND_LABEL: Record<ParkKind, MessageKey | null> = {
	park: null,
	trail: 'parks.kindTrail',
};

/**
 * What a park card and page call the place: "Trail" for a trail, else the
 * agency's label ("State park"). Null for values outside both vocabularies.
 */
export function parkTypeKey(kind: string | null | undefined, agency: string | null | undefined): MessageKey | null {
	const kindKey =
		kind != null && Object.prototype.hasOwnProperty.call(KIND_LABEL, kind) ? KIND_LABEL[kind as ParkKind] : null;
	return kindKey ?? labelKey(AGENCY_LABEL, agency);
}

export const SHAPE_LABEL: Record<CourseShape, MessageKey> = {
	loop: 'parks.shapeLoop',
	out_and_back: 'parks.shapeOutAndBack',
	point_to_point: 'parks.shapePointToPoint',
};

export const STATUS_LABEL: Record<CourseStatus, MessageKey> = {
	open: 'parks.statusOpen',
	closed: 'parks.statusClosed',
	seasonal: 'parks.statusSeasonal',
};

export const DIFFICULTY_LABEL: Record<CourseDifficulty, MessageKey> = {
	easy: 'parks.difficultyEasy',
	moderate: 'parks.difficultyModerate',
	hard: 'parks.difficultyHard',
};

export const ATTRIBUTION_LABEL: Record<GeometrySource, MessageKey> = {
	osm: 'parks.attributionOsm',
	nps: 'parks.attributionNps',
	agency: 'parks.attributionAgency',
	traced: 'parks.attributionTraced',
};

/** A label key for a stored value, or null for a value outside the vocabulary. */
export function labelKey<T extends string>(
	table: Record<T, MessageKey>,
	value: string | null | undefined,
): MessageKey | null {
	if (value == null) return null;
	return Object.prototype.hasOwnProperty.call(table, value) ? table[value as T] : null;
}

/**
 * The one credit line a course shows (issue #1352): the course's own
 * `attribution` text when it has one, else the label for its geometry
 * source; null when there is neither.
 */
export function courseCredit(
	attribution: string | null | undefined,
	geometrySource: string | null | undefined,
): { text: string } | { key: MessageKey } | null {
	const text = attribution?.trim();
	if (text) return { text };
	const key = labelKey(ATTRIBUTION_LABEL, geometrySource);
	return key ? { key } : null;
}
