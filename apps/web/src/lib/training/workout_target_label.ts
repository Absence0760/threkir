// The read-only line for a planned workout's effort and heart-rate targets:
// "RPE 3–4", "Cap 125 bpm". The shape comes from `rangeShape`
// (workout_prescription.ts); the words are the catalogue's, so every surface
// that shows a target (workout detail, the plan week, the coach's view) reads
// the same.

import { m } from '#lib/i18n/store.svelte.ts';
import { rangeShape } from './workout_prescription';

export function rpeTargetLabel(min: number | null | undefined, max: number | null | undefined): string | null {
	switch (rangeShape(min, max)) {
		case 'between':
			return m('workoutTarget.rpeBetween', { min: min!, max: max! });
		case 'exact':
			return m('workoutTarget.rpeExact', { value: min! });
		case 'atMost':
			return m('workoutTarget.rpeAtMost', { max: max! });
		case 'atLeast':
			return m('workoutTarget.rpeAtLeast', { min: min! });
		default:
			return null;
	}
}

export function hrTargetLabel(min: number | null | undefined, max: number | null | undefined): string | null {
	switch (rangeShape(min, max)) {
		case 'between':
			return m('workoutTarget.hrBetween', { min: min!, max: max! });
		case 'exact':
			return m('workoutTarget.hrExact', { value: min! });
		case 'atMost':
			return m('workoutTarget.hrAtMost', { max: max! });
		case 'atLeast':
			return m('workoutTarget.hrAtLeast', { min: min! });
		default:
			return null;
	}
}
