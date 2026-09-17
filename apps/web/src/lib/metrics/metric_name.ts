import { m } from '$lib/i18n/store.svelte';
import { METRICS, type MetricEntry, type MetricId } from './metric_registry';

/**
 * A registered metric's name as plain text, for the places a disclosure cannot
 * go: an input's `aria-label`, whose visible caption is `<MetricLabel>`.
 */
export function metricName(
	metric: MetricId,
	variant?: string,
	params?: Record<string, string | number>,
): string {
	const entry: MetricEntry = METRICS[metric];
	return m((variant ? entry.variants?.[variant] : undefined) ?? entry.label, params);
}
