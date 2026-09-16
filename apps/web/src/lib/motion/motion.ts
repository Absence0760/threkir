// Pure pieces of the public pages' motion, kept out of the rune store and the
// DOM actions so they run under plain `tsx --test`.

export function easeOutCubic(t: number): number {
	const c = Math.min(1, Math.max(0, t));
	return 1 - Math.pow(1 - c, 3);
}

/// Stagger for the i-th item of a group, capped so a long list does not keep
/// its last items hidden for seconds after the group scrolls into view.
export function staggerDelay(index: number, step = 70, cap = 420): number {
	return Math.min(Math.max(0, index) * step, cap);
}

type Reading =
	| { kind: 'clock'; parts: number[]; widths: number[] }
	| { kind: 'decimal'; value: number; decimals: number };

/// Reads a figure as the product prints it: a clock (`39:54`, `1:02:07`) or a
/// plain decimal (`8.04`). Anything else is not a count and returns null, so
/// the caller leaves the text alone instead of animating it into garbage.
export function parseReading(text: string): Reading | null {
	const trimmed = text.trim();
	if (/^\d+(:\d{2}){1,2}$/.test(trimmed)) {
		const raw = trimmed.split(':');
		return { kind: 'clock', parts: raw.map(Number), widths: raw.map((p) => p.length) };
	}
	if (/^\d+(\.\d+)?$/.test(trimmed)) {
		const decimals = trimmed.includes('.') ? trimmed.split('.')[1].length : 0;
		return { kind: 'decimal', value: Number(trimmed), decimals };
	}
	return null;
}

/// The reading `progress` of the way from zero to `final`, in the same shape:
/// the same number of decimals, the same clock fields and padding. At 1 it
/// returns `final` exactly, so an animation that ends lands on the markup's
/// own text rather than on a recomputed approximation of it.
export function readingAt(final: string, progress: number): string {
	const reading = parseReading(final);
	if (!reading || progress >= 1) return final;
	const p = Math.max(0, progress);

	if (reading.kind === 'decimal') {
		return (reading.value * p).toFixed(reading.decimals);
	}

	const units = reading.parts.length === 3 ? [3600, 60, 1] : [60, 1];
	const total = reading.parts.reduce((sum, part, i) => sum + part * units[i], 0);
	let left = Math.floor(total * p);
	return units
		.map((unit, i) => {
			const value = Math.floor(left / unit);
			left -= value * unit;
			return i === 0 ? String(value) : String(value).padStart(reading.widths[i], '0');
		})
		.join(':');
}

/// Advances a clock reading by whole seconds, for the phone's live timer.
export function tickClock(text: string, seconds = 1): string {
	const reading = parseReading(text);
	if (!reading || reading.kind !== 'clock') return text;
	const units = reading.parts.length === 3 ? [3600, 60, 1] : [60, 1];
	let total = reading.parts.reduce((sum, part, i) => sum + part * units[i], 0) + seconds;
	const hours = Math.floor(total / 3600);
	if (reading.parts.length === 2 && hours === 0) {
		return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
	}
	total -= hours * 3600;
	return `${hours}:${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}
