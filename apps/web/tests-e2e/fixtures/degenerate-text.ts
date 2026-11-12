/**
 * A number that should never reach a label: `NaN`, an infinity (`Infinity`
 * or the `∞` Intl prints), or a negative zero (`-0`, `-0.00`, `-0:00`, also
 * with the U+2212 minus Intl emits in some locales).
 *
 * The negative-zero arm refuses a minus preceded by a letter or digit, so a
 * date (`2026-04-05`) or a zone (`UTC-0`) is not one, and refuses a zero with
 * any non-zero digit after it, so `-0.05` and a `-0:30` pace delta are not.
 *
 * The same pattern as the mobile sweep's `degenerateNumber`
 * (`apps/mobile_android/test/rendered_text_sweep.dart`), so "the page printed
 * a broken number" means the same thing on both platforms;
 * `degenerate-text.test.ts` fails when the two sources disagree.
 */
export const DEGENERATE_NUMBER =
	/\bNaN\b|\bInfinity\b|∞|(?<![\p{L}\p{N}])[-−]0(?:[.,:]0+)*(?![.,:]?\p{N})/u;

/** Every string in `strings` that carries a degenerate number. */
export function degenerateStrings(strings: readonly string[]): string[] {
	return strings.filter((s) => DEGENERATE_NUMBER.test(s));
}
