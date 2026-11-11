// Whether a park may load into production (decisions § 2460). Every park's
// `park.json` declares a `release`, which the build copies into its
// `manifest.json`:
//
//   { "status": "live" }                         the release sync loads it
//   { "status": "staged", "reason": "..." }      built, validated, never loaded
//
// There is no default. A park without a release, or with one this module does
// not recognise, fails the build and the sync rather than loading, so a typo
// can never publish a park that was meant to wait.

export const RELEASE_STATUSES = ['live', 'staged'];
export const MAX_STAGED_REASON_LENGTH = 500;

/**
 * @typedef {{ status: 'live' } | { status: 'staged', reason: string }} Release
 */

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
		if (keys !== 'status') throw new Error(`${where} release "live" takes only status, got ${keys}`);
		return { status: 'live' };
	}
	if (release.status === 'staged') {
		if (keys !== 'reason,status') throw new Error(`${where} release "staged" takes exactly status and reason, got ${keys}`);
		const reason = typeof release.reason === 'string' ? release.reason.trim() : '';
		if (reason.length === 0 || reason.length > MAX_STAGED_REASON_LENGTH) {
			throw new Error(`${where} release reason must be 1-${MAX_STAGED_REASON_LENGTH} characters`);
		}
		return { status: 'staged', reason };
	}
	throw new Error(`${where} release status ${JSON.stringify(release.status)} is not one of ${RELEASE_STATUSES.join(', ')}`);
}
