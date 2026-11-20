// Whether a park may load into production (decisions § 2460, § 2600). The
// build derives every park's `release` from the go-live gate
// (`golive_gate.mjs`) and writes it into its `manifest.json`; `park.json`
// carries none:
//
//   { "status": "live" }                         the release sync loads it
//   { "status": "staged", "reason": "..." }      built, validated, never loaded
//
// There is no default. A manifest without a release, or with one this module
// does not recognise, fails the sync rather than loading, so a hand edit can
// never publish a park the gate did not pass.

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
