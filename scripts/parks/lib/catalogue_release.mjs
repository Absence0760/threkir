// Whether a park may load into production (decisions § 2460, § 2600). The
// build derives every park's `release` from the go-live gate
// (`golive_gate.mjs`) and writes it into its `manifest.json`; `park.json`
// carries none:
//
//   { "status": "live" }                         the release sync loads it
//   { "status": "live", "held": [{ "course": "...", "reason": "..." }] }
//                                                it loads every course but the
//                                                held ones (decisions § 2602)
//   { "status": "staged", "reason": "..." }      built, validated, never loaded
//
// A held course is never created, and one already loaded is never closed by
// being held: the sync leaves it as it is and reports it `held_live`.
//
// There is no default. A manifest without a release, or with one this module
// does not recognise, fails the sync rather than loading, so a hand edit can
// never publish a park the gate did not pass.

export const RELEASE_STATUSES = ['live', 'staged'];
export const MAX_STAGED_REASON_LENGTH = 500;

/**
 * @typedef {{ course: string, reason: string }} HeldCourse
 * @typedef {{ status: 'live', held?: HeldCourse[] } | { status: 'staged', reason: string }} Release
 */

const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

/**
 * @param {unknown} reason
 * @param {string} where
 */
function checkedReason(reason, where) {
	const text = typeof reason === 'string' ? reason.trim() : '';
	if (text.length === 0 || text.length > MAX_STAGED_REASON_LENGTH) {
		throw new Error(`${where} release reason must be 1-${MAX_STAGED_REASON_LENGTH} characters`);
	}
	return text;
}

/**
 * @param {unknown} json
 * @param {string} where names the park in the error
 * @returns {Release}
 */
export function parseRelease(json, where) {
	if (json === undefined || json === null) {
		throw new Error(
			`${where} has no release: add "release": { "status": "staged", "reason": "..." } until it may load, or { "status": "live" }`,
		);
	}
	if (typeof json !== 'object' || Array.isArray(json)) throw new Error(`${where} release must be an object`);
	const release = /** @type {Record<string, unknown>} */ (json);
	const keys = Object.keys(release).sort().join(',');
	if (release.status === 'live') {
		if (keys === 'status') return { status: 'live' };
		if (keys !== 'held,status') throw new Error(`${where} release "live" takes status and an optional held, got ${keys}`);
		if (!Array.isArray(release.held) || release.held.length === 0) throw new Error(`${where} release held must be a non-empty list`);
		/** @type {HeldCourse[]} */
		const held = release.held.map((h, i) => {
			const entry = /** @type {Record<string, unknown>} */ (h ?? {});
			if (typeof h !== 'object' || Array.isArray(h) || Object.keys(entry).sort().join(',') !== 'course,reason') {
				throw new Error(`${where} release held ${i + 1} takes exactly course and reason`);
			}
			if (typeof entry.course !== 'string' || !SLUG.test(entry.course)) throw new Error(`${where} release held ${i + 1} course is not a slug`);
			return { course: entry.course, reason: checkedReason(entry.reason, `${where} held ${entry.course}`) };
		});
		if (new Set(held.map((h) => h.course)).size !== held.length) throw new Error(`${where} release holds a course twice`);
		return { status: 'live', held };
	}
	if (release.status === 'staged') {
		if (keys !== 'reason,status') throw new Error(`${where} release "staged" takes exactly status and reason, got ${keys}`);
		return { status: 'staged', reason: checkedReason(release.reason, where) };
	}
	throw new Error(`${where} release status ${JSON.stringify(release.status)} is not one of ${RELEASE_STATUSES.join(', ')}`);
}
