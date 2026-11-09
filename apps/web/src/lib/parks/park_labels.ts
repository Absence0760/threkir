import type { MessageKey } from '../i18n/messages.ts';
import type {
	CourseDifficulty,
	CourseShape,
	CourseStatus,
	GeometrySource,
	ParkAgency,
} from './park_courses.ts';

// Each value names its catalogue key literally, so the area-catalogue split
// (decisions § 1802) can see which route renders it.

export const AGENCY_LABEL: Record<ParkAgency, MessageKey> = {
	nps: 'parks.agencyNps',
	state: 'parks.agencyState',
	county: 'parks.agencyCounty',
	other: 'parks.agencyOther',
};

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
