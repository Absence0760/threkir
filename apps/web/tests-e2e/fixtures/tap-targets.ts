import { expect, type Locator } from '@playwright/test';

/**
 * The one place the web tap-target bar is written down, and the sweep that
 * measures a whole surface against it.
 *
 * Two numbers, and the gap between them is the point. `MIN_TAP_TARGET_PX` is
 * the product bar — the size a control must clear, well above WCAG 2.2 AA's
 * 24 px target-size minimum (2.5.8) and the number every tap-target assertion
 * in the suite tests. `TAP_TARGET_HEADROOM_PX` is what a control must clear it
 * BY: `.pr-hide` used to be sized at the bar exactly and reported 44.0 x 44.0
 * on all 480 samples of a 12-load run, so a fractional device pixel ratio, an
 * ancestor transform mid-animation or a compositor quad rounding down turned a
 * correct control into a failed assertion. Source sizing goes through
 * `--tap-target-min` in app.css, which sits above the bar; a control measured
 * AT the bar is one written against the assertion instead of the token, and
 * fails here saying so.
 *
 * Scope is icon buttons — a control whose glyph is the whole target. A labelled
 * control carries a wide text surface and takes WCAG 2.5.8's own inline and
 * spacing exceptions, which is the same line `conventions.md` draws for the
 * Flutter twin's IconButtons. `INLINE_DISCLOSURE` names the one icon button
 * that is deliberately smaller: a disclosure sitting inside running text, whose
 * size is constrained by the line-height of the text around it (2.5.8's Inline
 * exception), sized from `--tap-target-inline-min`.
 */

export const MIN_TAP_TARGET_PX = 44;
export const TAP_TARGET_HEADROOM_PX = 2;

/** WCAG 2.2 AA SC 2.5.8, for the controls the 44 px bar exempts. */
export const WCAG_MIN_TARGET_PX = 24;

/**
 * Icon buttons held to the WCAG floor rather than the product bar, by class,
 * with the reason. Anything not listed here answers to `MIN_TAP_TARGET_PX`.
 */
export const INLINE_DISCLOSURE: Record<string, string> = {
	'metric-info':
		"a metric name's definition toggletip, inline inside the label text — " +
		'a 48 px box would push the tile value off its line (WCAG 2.5.8 Inline)'
};

export type MeasuredTarget = {
	label: string;
	classes: string;
	width: number;
	height: number;
	/** The floor this one answers to, already resolved through the exemptions. */
	floor: number;
};

/**
 * Every visible icon button inside `scope`, measured.
 *
 * An icon button is a control that carries an `aria-label` or `title` and
 * renders no word characters of its own — the Material Symbols ligature spans
 * are `aria-hidden`, so they are stripped before the test. That is the same
 * definition the Flutter guard uses ("the glyph is the whole target"), applied
 * to the DOM rather than to Dart source.
 */
export async function measureIconButtons(scope: Locator): Promise<MeasuredTarget[]> {
	return scope.evaluate(
		(root, args) => {
			const [bar, wcagFloor, exempt] = args;
			const out: MeasuredTarget[] = [];
			const els = root.querySelectorAll<HTMLElement>(
				'button, a[href], [role="button"], [role="link"], summary'
			);
			for (const el of els) {
				const label = el.getAttribute('aria-label') ?? el.getAttribute('title') ?? '';
				if (!label) continue;
				const clone = el.cloneNode(true) as HTMLElement;
				for (const hidden of clone.querySelectorAll('[aria-hidden="true"]')) {
					hidden.remove();
				}
				if (/\w/.test(clone.textContent ?? '')) continue;
				const cs = getComputedStyle(el);
				if (cs.visibility === 'hidden' || cs.display === 'none') continue;
				const r = el.getBoundingClientRect();
				if (r.width === 0 && r.height === 0) continue;
				const classes = el.className?.toString?.() ?? '';
				const exemption = Object.keys(exempt).find((c) =>
					classes.split(/\s+/).includes(c)
				);
				out.push({
					label,
					classes,
					width: r.width,
					height: r.height,
					floor: exemption ? wcagFloor : bar
				});
			}
			return out;
		},
		[MIN_TAP_TARGET_PX, WCAG_MIN_TARGET_PX, INLINE_DISCLOSURE] as const
	);
}

/**
 * Sweep `scope` and fail on any icon button that misses its floor, or that
 * meets it exactly. Polled, because a dashboard still settling reports a row
 * mid-swap; the threshold is never relaxed, only re-read.
 */
export async function expectIconButtonsClearTheBar(
	scope: Locator,
	{ minCount }: { minCount: number }
): Promise<MeasuredTarget[]> {
	await expect
		.poll(async () => (await measureIconButtons(scope)).length, {
			message: `expected at least ${minCount} icon buttons in the sweep scope`
		})
		.toBeGreaterThanOrEqual(minCount);

	await expect
		.poll(async () => describeOffenders(await measureIconButtons(scope)), {
			message:
				'every icon button must clear its tap-target floor by at least ' +
				`${TAP_TARGET_HEADROOM_PX}px — size it from --tap-target-min, not from the bar`
		})
		.toEqual([]);

	return measureIconButtons(scope);
}

export function describeOffenders(measured: MeasuredTarget[]): string[] {
	return measured
		.filter(
			(t) =>
				t.width < t.floor + TAP_TARGET_HEADROOM_PX ||
				t.height < t.floor + TAP_TARGET_HEADROOM_PX
		)
		.map(
			(t) =>
				`${t.label} (.${t.classes.split(/\s+/)[0]}): ${t.width}x${t.height}, ` +
				`floor ${t.floor}`
		)
		.sort();
}
