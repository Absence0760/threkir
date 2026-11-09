// The one boundary where network data enters a park's committed snapshot.
//
// `fetch_snapshot.mjs` writes what the OSM API returns into `snapshot.json`,
// which `build.mjs` then trusts offline. A response that is not the shape the
// API documents — a proxy error page that parsed as JSON, a truncated body, a
// coordinate out of range — must stop the run here, not land in a reviewed
// file where it reads as geometry. So every field is rebuilt from a checked
// primitive rather than copied: ids and versions are positive integers,
// coordinates are finite and in range, and tags are short strings, which is
// what OSM itself enforces (a tag key or value is at most 255 characters).

const MAX_TAG_LENGTH = 255;

/**
 * @param {unknown} value
 * @returns {value is number}
 */
function isPositiveInteger(value) {
	return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}

/**
 * @param {unknown} value
 * @param {number} limit
 * @returns {value is number}
 */
function isCoordinate(value, limit) {
	return typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= limit;
}

/**
 * @param {unknown} value
 * @returns {value is string}
 */
function isTagString(value) {
	return typeof value === 'string' && value.length > 0 && value.length <= MAX_TAG_LENGTH;
}

/**
 * The way and its nodes from one OSM API 0.6 `way/{id}/full.json` response,
 * or a thrown Error naming what did not check.
 *
 * @param {unknown} body
 * @param {number} wayId
 * @returns {{
 *   way: { id: number, version: number, tags: Record<string, string>, nodes: number[] },
 *   nodes: Record<string, { lat: number, lon: number }>,
 * }}
 */
export function parseWayFull(body, wayId) {
	const elements = /** @type {{ elements?: unknown }} */ (body ?? {}).elements;
	if (!Array.isArray(elements)) throw new Error(`way ${wayId}: response has no elements array`);

	/** @type {Record<string, { lat: number, lon: number }>} */
	const nodes = {};
	/** @type {{ id: number, version: number, tags: Record<string, string>, nodes: number[] } | null} */
	let way = null;

	for (const raw of elements) {
		if (typeof raw !== 'object' || raw === null) throw new Error(`way ${wayId}: an element is not an object`);
		const el = /** @type {Record<string, unknown>} */ (raw);
		if (el.type === 'node') {
			if (!isPositiveInteger(el.id)) throw new Error(`way ${wayId}: node id ${JSON.stringify(el.id)} is not a positive integer`);
			if (!isCoordinate(el.lat, 90) || !isCoordinate(el.lon, 180)) {
				throw new Error(`way ${wayId}: node ${el.id} has no valid coordinate`);
			}
			nodes[String(el.id)] = { lat: el.lat, lon: el.lon };
		} else if (el.type === 'way' && el.id === wayId) {
			if (!isPositiveInteger(el.version)) throw new Error(`way ${wayId}: version ${JSON.stringify(el.version)} is not a positive integer`);
			if (!Array.isArray(el.nodes) || el.nodes.length < 2 || !el.nodes.every(isPositiveInteger)) {
				throw new Error(`way ${wayId}: its node list is not two or more positive integers`);
			}
			/** @type {Array<[string, string]>} */
			const tagEntries = [];
			if (el.tags !== undefined) {
				if (typeof el.tags !== 'object' || el.tags === null || Array.isArray(el.tags)) {
					throw new Error(`way ${wayId}: tags is not an object`);
				}
				for (const [key, value] of Object.entries(el.tags)) {
					if (!isTagString(key) || !isTagString(value)) {
						throw new Error(`way ${wayId}: tag ${JSON.stringify(key).slice(0, 40)} is not a 1-${MAX_TAG_LENGTH} character string pair`);
					}
					tagEntries.push([key, value]);
				}
			}
			// fromEntries defines own properties, so a `__proto__` tag key stays
			// a key rather than replacing the object's prototype.
			way = { id: wayId, version: el.version, tags: Object.fromEntries(tagEntries), nodes: [...el.nodes] };
		}
	}

	if (!way) throw new Error(`OSM returned no way ${wayId}`);
	const missing = way.nodes.filter((id) => !nodes[String(id)]);
	if (missing.length) throw new Error(`way ${wayId}: response omits node(s) ${missing.slice(0, 5).join(', ')}`);
	return { way, nodes };
}
