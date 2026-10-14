// A runner's parkrun athlete number and the Code 128 barcode a finish-funnel
// scanner reads it from. parkrun's printed barcodes are Code 128 carrying the
// number itself, leading `A` included (`A123456`) — see
// docs/features/integrations.md § parkrun barcode for the sources. Everything
// is encoded in code set B: one symbol per character, so the module count is
// fixed by the length and no set-switching logic can mis-pick a symbol.
// Dart twin: apps/mobile_android/lib/parkrun_barcode.dart (keep in lockstep).

/** Same bound `parkrun-import` enforces (`/^A\d{1,12}$/`). */
export const PARKRUN_ATHLETE_NUMBER_MAX_DIGITS = 12;

const ATHLETE_NUMBER = new RegExp(`^A\\d{1,${PARKRUN_ATHLETE_NUMBER_MAX_DIGITS}}$`);

/**
 * The canonical form of what a runner typed, or null when it is not an
 * athlete number. Whitespace anywhere is dropped and a lowercase `a` is
 * accepted, because both are how the number gets copied off a printed
 * barcode or a results email; anything else is refused rather than guessed.
 */
export function normalizeParkrunAthleteNumber(raw: string | null | undefined): string | null {
	if (raw == null) return null;
	const compact = raw.replace(/\s+/g, '');
	if (compact.length === 0) return null;
	const canonical = compact[0] === 'a' ? `A${compact.slice(1)}` : compact;
	return ATHLETE_NUMBER.test(canonical) ? canonical : null;
}

/**
 * Bar/space widths, in modules, for Code 128 symbol values 0–106. Each data
 * symbol is 6 elements summing to 11 modules; STOP (106) is 7 elements, 13
 * modules, including its terminating bar. Cross-checked against JsBarcode's
 * `BARS` table.
 */
export const CODE128_PATTERNS: readonly string[] = [
	'212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213',
	'221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
	'221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
	'212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
	'231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
	'231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
	'314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
	'112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
	'111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
	'214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
	'114131', '311141', '411131', '211412', '211214', '211232', '2331112',
];

export const CODE128_START_B = 104;
export const CODE128_STOP = 106;

/** ISO/IEC 15417 asks for at least 10 modules of quiet zone each side. */
export const CODE128_QUIET_ZONE_MODULES = 10;

/**
 * The symbol values for [text] in code set B: START B, one value per
 * character (`code − 32`), the mod-103 check symbol, STOP. Throws on a
 * character set B cannot carry (outside printable ASCII 32–126).
 */
export function code128BSymbols(text: string): number[] {
	if (text.length === 0) throw new RangeError('Code 128 needs at least one character');
	const values = [CODE128_START_B];
	for (let i = 0; i < text.length; i++) {
		const code = text.charCodeAt(i);
		if (code < 32 || code > 126) {
			throw new RangeError(`Code 128 set B cannot encode character ${code} at ${i}`);
		}
		values.push(code - 32);
	}
	let sum = CODE128_START_B;
	for (let i = 1; i < values.length; i++) sum += i * values[i];
	values.push(sum % 103, CODE128_STOP);
	return values;
}

/** The barcode as a module string, `1` a bar module and `0` a space, no quiet zone. */
export function code128BModules(text: string): string {
	let out = '';
	for (const value of code128BSymbols(text)) {
		const widths = CODE128_PATTERNS[value];
		for (let e = 0; e < widths.length; e++) {
			out += (e % 2 === 0 ? '1' : '0').repeat(Number(widths[e]));
		}
	}
	return out;
}

export interface BarcodeBar {
	/** Offset from the first module, in modules. */
	start: number;
	width: number;
}

/** Each contiguous run of bar modules, for drawing one rectangle per bar. */
export function barcodeBars(modules: string): BarcodeBar[] {
	const bars: BarcodeBar[] = [];
	let i = 0;
	while (i < modules.length) {
		if (modules[i] !== '1') {
			i++;
			continue;
		}
		const start = i;
		while (i < modules.length && modules[i] === '1') i++;
		bars.push({ start, width: i - start });
	}
	return bars;
}
