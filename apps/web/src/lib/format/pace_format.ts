/// Pure pace-string formatting, split out from `units.svelte.ts` so it can
/// be unit-tested without the Svelte compiler (the unit-preference signal
/// lives in the `.svelte.ts` shell; this layer is rune-free).

/// Split a pace value (seconds per the display unit) into whole minutes +
/// seconds, rounding to the nearest second FIRST so the seconds field is
/// always 0–59.
///
/// Splitting before rounding — `Math.floor(x / 60)` for minutes but
/// `Math.round(x % 60)` for seconds — lets a fractional input produce a
/// seconds field of 60 (e.g. 299.6 → 4 min + 60 s), which renders as the
/// malformed "4:60" and, in a two-field editor, exceeds the `max="59"`
/// input bound. Rounding the total first keeps the rollover correct.
export function paceParts(secPerUnit: number): { minutes: number; seconds: number } {
	const total = Math.round(secPerUnit);
	return { minutes: Math.floor(total / 60), seconds: total % 60 };
}

/// Format a pace value (seconds per the display unit, already converted to
/// km or mi by the caller) as "m:ss". Mirrors `fmtPaceCell` in
/// training/plan_serialize.ts and the Dart `UnitFormat.pace` twin in
/// preferences.dart.
///
/// A non-finite or negative input is not a pace — `Infinity` is what a 0 m
/// distance divides to, and `paceParts` would otherwise render it as
/// "Infinity:NaN" — so it gets the `--:--` placeholder `formatPace` and
/// `UnitFormat.pace` use. Zero stays "0:00", which the pace editors pre-fill.
export function paceMinutesSeconds(secPerUnit: number): string {
	if (!Number.isFinite(secPerUnit) || secPerUnit < 0) return '--:--';
	const { minutes, seconds } = paceParts(secPerUnit);
	return `${minutes}:${String(seconds).padStart(2, '0')}`;
}

/// A pace/speed value is only meaningful when both inputs are finite and
/// strictly positive. A zero or negative duration/distance (a corrupt or
/// manually-edited row) otherwise renders a malformed `0:00`, `-5:00`, or
/// `-12.0 km/h` instead of a sentinel. Mirrors the `<= 0` guard the Dart
/// twin `UnitFormat.pace` / `UnitFormat.speed` already apply, so the same
/// non-physical input shows the em-dash sentinel on both platforms.
export function isMeaningfulPace(seconds: number, metres: number): boolean {
	return Number.isFinite(seconds) && Number.isFinite(metres) && seconds > 0 && metres > 0;
}

/// A pace tolerance is stored as seconds per km (`target_pace_tolerance_sec`).
/// Next to a /mi pace it has to be per mile too, and say so: "±10s" beside
/// "8:03/mi" read as ten seconds a mile when it meant sixteen.
export function paceToleranceLabel(secPerKm: number, unit: 'km' | 'mi'): string {
	return `±${paceToleranceToUnit(secPerKm, unit)}s/${unit}`;
}

/// A stored pace (seconds per km) as an "m:ss" field in the runner's unit,
/// or '' when there is none.
export function paceFieldFromSecPerKm(secPerKm: number | null, unit: 'km' | 'mi'): string {
	if (secPerKm == null || secPerKm <= 0) return '';
	return paceMinutesSeconds(unit === 'mi' ? secPerKm * (1609.344 / 1000) : secPerKm);
}

/// An "m:ss" field typed in the runner's unit, as whole seconds per km for
/// the integer pace column; null when it is empty or not "m:ss". The plan
/// wizard used to store the typed value as-is, so 8:51 meant for a mile
/// became 8:51/km.
export function secPerKmFromPaceField(raw: string, unit: 'km' | 'mi'): number | null {
	const m = raw.trim().match(/^(\d{1,2}):([0-5]\d)$/);
	if (!m) return null;
	const perUnit = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
	if (perUnit <= 0) return null;
	return Math.round(unit === 'mi' ? perUnit / (1609.344 / 1000) : perUnit);
}

/// The tolerance an editor shows, in whole seconds per the display unit.
export function paceToleranceToUnit(secPerKm: number, unit: 'km' | 'mi'): number {
	return Math.round(unit === 'mi' ? secPerKm * (1609.344 / 1000) : secPerKm);
}

/// What an editor stores for a tolerance typed per the display unit: whole
/// seconds per km, the column's unit. Typed as-is, ±10 s/mi was saved as
/// ±10 s/km and read back beside the pace as "±16s/mi".
export function paceToleranceFromUnit(secPerUnit: number, unit: 'km' | 'mi'): number {
	return Math.round(unit === 'mi' ? secPerUnit / (1609.344 / 1000) : secPerUnit);
}
