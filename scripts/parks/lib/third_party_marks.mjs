// Third-party event marks a park course must never carry (decisions § 2455,
// reviews/legal-parkrun-park-courses.md § Recommendation 2). A course on paths
// a weekly event also uses is named after the park and its distance only:
// the event's name, in any spelling, and a link to its site would read as the
// event's own course or results. Checked over every string in a park's spec
// and its built manifest, so a name, a note, a route guide or a source URL
// cannot slip one in.

/**
 * "parkrun" / "parkwalk" anywhere (so parkrunner, (not)parkrun, its domains),
 * and the spaced or hyphenated forms as whole words, so "the park runs along
 * the creek" and "park walkway" stay sayable.
 */
export const THIRD_PARTY_MARK = /park(run|walk)|\bpark[\s_-]+(run|walk)\b/i;

/** @param {string} text */
const folded = (text) => text.normalize('NFKC').replace(/[\u00ad\u200b-\u200f\u2060\ufeff]/g, '');

/**
 * Every string under `value` that carries a refused mark, with its JSON path.
 *
 * @param {unknown} value
 * @param {string} [at]
 * @returns {{ path: string, text: string }[]}
 */
export function thirdPartyMarks(value, at = '') {
	if (typeof value === 'string') return THIRD_PARTY_MARK.test(folded(value)) ? [{ path: at || '(value)', text: value }] : [];
	if (Array.isArray(value)) return value.flatMap((v, i) => thirdPartyMarks(v, `${at}[${i}]`));
	if (value && typeof value === 'object') {
		return Object.entries(value).flatMap(([k, v]) => [
			...(THIRD_PARTY_MARK.test(folded(k)) ? [{ path: `${at}.${k}`, text: k }] : []),
			...thirdPartyMarks(v, at ? `${at}.${k}` : k),
		]);
	}
	return [];
}

/**
 * @param {unknown} value a park.json spec or a built manifest
 * @param {string} where names the file in the error
 */
export function assertNoThirdPartyMarks(value, where) {
	const found = thirdPartyMarks(value);
	if (found.length > 0) {
		throw new Error(
			`${where} names a third-party event (parkrun / parkwalk) or links to its site, which no park course may: ` +
				found.map((f) => `${f.path} = ${JSON.stringify(f.text.slice(0, 120))}`).join('; '),
		);
	}
}
