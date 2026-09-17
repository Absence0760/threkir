/**
 * The one registry of derived-metric names and their plain-English
 * definitions (#902 §1 + §2, #905 workstream 6).
 *
 * Every entry is rendered through `<MetricLabel>`, which puts the name on
 * screen with a disclosure a runner can open by touch or keyboard. A `title=`
 * tooltip is not that: it never appears on touch, a keyboard cannot reach it,
 * and screen readers announce it inconsistently (decisions § 1622).
 *
 * `metric_label_guard.test.ts` reads this same object, so the registry and the
 * rule it enforces cannot drift: a label or definition key rendered anywhere
 * but through `<MetricLabel>`, a registered term typed straight into markup,
 * or English copy that carries a term with no expansion fails the unit job.
 */
import type { MessageKey } from '$lib/i18n/messages';

export interface MetricEntry {
	/** The short on-screen name. Resolved only by `<MetricLabel>`. */
	readonly label: MessageKey;
	/** One plain line saying what the number means. */
	readonly definition: MessageKey;
	/** Other spellings of the name a surface needs, e.g. "This week's vert". */
	readonly variants?: Readonly<Record<string, MessageKey>>;
	/**
	 * Catalogue sentences that name the metric mid-prose. Each carries a
	 * `{term}` placeholder, and `<MetricLabel sentence=…>` renders the name,
	 * with its disclosure, where the placeholder sits.
	 */
	readonly sentences?: readonly MessageKey[];
	/**
	 * How the jargon is spelled in English. The guard hunts for it in markup
	 * and in the English catalogue. Case-sensitive on purpose: `rpe` is a class
	 * name, `RPE` is a word a runner reads.
	 */
	readonly term?: RegExp;
	/**
	 * English copy that may carry the term because the same string spells out
	 * what it means — an `<option>` or a form label cannot hold a disclosure.
	 * The value is the reason, and the guard fails once a key stops carrying
	 * the term, so an exemption cannot outlive its cause.
	 */
	readonly expandedIn?: Readonly<Partial<Record<MessageKey, string>>>;
}

export const METRICS = {
	vo2max: {
		label: 'metric.vo2max.label',
		definition: 'dash.vo2maxTooltip',
		term: /VO₂\s?max|VO2\s?max/,
	},
	ctl: {
		label: 'dash.ctlLabel',
		definition: 'dash.ctlTooltip',
		term: /\bCTL\b/,
		expandedIn: {
			'trainingLoad.chartAriaLabel':
				'an accessible name for the chart, which spells out each acronym beside it',
		},
	},
	atl: {
		label: 'dash.atlLabel',
		definition: 'dash.atlTooltip',
		term: /\bATL\b/,
		expandedIn: {
			'trainingLoad.chartAriaLabel':
				'an accessible name for the chart, which spells out each acronym beside it',
		},
	},
	tsb: {
		label: 'dash.tsbLabel',
		definition: 'dash.tsbTooltip',
		term: /\bTSB\b/,
		expandedIn: {
			'trainingLoad.chartAriaLabel':
				'an accessible name for the chart, which spells out each acronym beside it',
		},
	},
	ageGrade: {
		label: 'metric.ageGrade.label',
		definition: 'metric.ageGrade.definition',
		term: /\b[Aa]ge grade\b/,
	},
	vert: {
		label: 'metric.vert.label',
		definition: 'metric.vert.definition',
		variants: { thisWeek: 'dash.statThisWeekVert' },
		// Not the `{vert}` placeholder, and not the `'vert'` challenge metric id.
		term: /\bVert\b|(?<![{'"\w])vert(?![}'"\w])/,
	},
	trimp: {
		label: 'metric.trimp.label',
		definition: 'metric.trimp.definition',
		sentences: ['trainingLoad.hintTrimp'],
		term: /\bTRIMP\b/,
	},
	riegel: {
		label: 'metric.riegel.label',
		definition: 'metric.riegel.definition',
		sentences: ['racePredictor.footnote', 'planEditor.recent5kHint'],
		term: /\bRiegel\b/,
	},
	vdot: {
		label: 'metric.vdot.label',
		definition: 'metric.vdot.definition',
		term: /\bVDOT\b/,
	},
	distanceBanked: {
		label: 'planDetail.distanceBanked',
		definition: 'metric.distanceBanked.definition',
		term: /\b[Dd]istance banked\b/,
	},
	// No term: Base, Build and Peak are ordinary words elsewhere in the copy,
	// so the phase names cannot be hunted for. The label is the guarded part.
	planPhases: {
		label: 'metric.planPhases.label',
		definition: 'metric.planPhases.definition',
	},
} as const satisfies Record<string, MetricEntry>;

export type MetricId = keyof typeof METRICS;

export function isMetricId(value: string): value is MetricId {
	return Object.hasOwn(METRICS, value);
}

/** Every catalogue key the registry owns for one metric's name. */
export function nameKeys(entry: MetricEntry): MessageKey[] {
	return [entry.label, ...Object.values(entry.variants ?? {})];
}

export const TERM_PLACEHOLDER = '{term}';

/**
 * A resolved sentence cut at its `{term}` placeholder. Null when the
 * placeholder is missing or doubled, which the caller renders as the name
 * alone rather than guessing where it belonged.
 */
export function splitAtTerm(sentence: string): { before: string; after: string } | null {
	const at = sentence.indexOf(TERM_PLACEHOLDER);
	if (at < 0 || sentence.indexOf(TERM_PLACEHOLDER, at + 1) >= 0) return null;
	return { before: sentence.slice(0, at), after: sentence.slice(at + TERM_PLACEHOLDER.length) };
}
