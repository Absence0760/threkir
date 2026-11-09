/// The goal and window wording every challenge surface shows: the detail page,
/// the invite join page and the public share page. One home so the three
/// cannot describe the same challenge differently.

import { formatDistance, formatElevation } from './units.svelte';
import { formatDuration } from './time';
import { m } from '../i18n/store.svelte';
import type { ChallengeMetric } from '../types';

export function formatChallengeGoal(metric: ChallengeMetric, v: number): string {
	switch (metric) {
		case 'distance':
			return formatDistance(v);
		case 'duration':
			return formatDuration(Math.round(v));
		case 'vert':
			return formatElevation(v);
		case 'streak_days':
			return m('challenges.unitDays', { n: Math.round(v) });
		case 'activity_count':
			return m('challenges.unitActivities', { n: Math.round(v) });
		case 'park_courses':
			return m('challenges.unitParkCourses', { n: Math.round(v) });
	}
}

export function challengeWindowLabel(
	c: { starts_at: string; ends_at: string },
	now: number = Date.now(),
): string {
	const starts = new Date(c.starts_at).getTime();
	const ends = new Date(c.ends_at).getTime();
	if (now < starts) return m('challenges.startsIn', { n: Math.ceil((starts - now) / 86400000) });
	if (now >= ends) return m('challenges.ended');
	const d = Math.ceil((ends - now) / 86400000);
	return d <= 1 ? m('challenges.endsToday') : m('challenges.endsIn', { n: d });
}
