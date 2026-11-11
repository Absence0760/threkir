// Third-party event marks a park course must never carry (decisions § 2455,
// reviews/legal-parkrun-park-courses.md § Recommendation 2). A course on paths
// a weekly event also uses is named after the park and its distance only:
// the event's name, in any spelling, and a link to its site would read as the
// event's own course or results. Checked over every string in a park's spec
// and its built manifest, so a name, a note, a route guide or a source URL
// cannot slip one in.

/** "parkrun" in any case or spacing (park run, park-run, (not)parkrun, junior parkrun), its domains, and "parkwalk". */
export const THIRD_PARTY_MARK = /park[\s_-]*(run|walk)/i;

/**
 * Every string under `value` that carries a refused mark, with its JSON path.
 *
 * @param {unknown} value
 * @param {string} [at]
 * @returns {{ path: string, text: string }[]}
 */
export function thirdPartyMarks(value, at = '') {
	if (typeof value === 'string') return THIRD_PARTY_MARK.test(value) ? [{ path: at || '(value)', text: value }] : [];
	if (Array.isArray(value)) return value.flatMap((v, i) => thirdPartyMarks(v, `${at}[${i}]`));
	if (value && typeof value === 'object') {
		return Object.entries(value).flatMap(([k, v]) => [
			...(THIRD_PARTY_MARK.test(k) ? [{ path: `${at}.${k}`, text: k }] : []),
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
