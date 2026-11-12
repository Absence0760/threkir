/// Gridline ticks for the training-load chart. The plot is min/max-normalised,
/// so without labelled ticks CTL 45 and CTL 450 draw pixel-identically: shape
/// without magnitude. Pairs with mobile's `trainingLoadTickStep` /
/// `trainingLoadTickValues` in `training_load_chart.dart`.

/// Round step on the 1 / 2 / 5 x 10^n ladder, never below 1.
export function trainingLoadTickStep(span: number, maxTicks = 4): number {
	if (!Number.isFinite(span) || span <= 0) return 1;
	const raw = span / maxTicks;
	const mag = 10 ** Math.floor(Math.log10(raw));
	const norm = raw / mag;
	const mult = norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10;
	// Labels are whole numbers and double as the keyed-each key, so a sub-1
	// step (a near-zero load, e.g. one 10 s run) rounds two ticks to the same
	// value: -0.5 and 0 both key as 0 and Svelte throws, taking the whole
	// dashboard down with it (#1155).
	return Math.max(1, mult * mag);
}

/// Whole-number tick values from `min` to `max`, ascending and distinct.
/// `-0` is folded to `0` so it can never collide with a real zero tick.
export function trainingLoadTickValues(min: number, max: number): number[] {
	if (!Number.isFinite(min) || !Number.isFinite(max) || max < min) return [];
	const step = trainingLoadTickStep(max - min);
	const out: number[] = [];
	for (let v = Math.ceil(min / step) * step; v <= max + step * 0.001; v += step) {
		out.push(Math.round(v) || 0);
	}
	return out;
}
