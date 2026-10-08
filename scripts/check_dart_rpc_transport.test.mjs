// Unit tests for scripts/check_dart_rpc_transport.mjs.
//
// The real tree is the positive control, and each case mutates an in-memory
// copy of it into one shape the guard exists to refuse. Every mutation must
// actually match, so a reworded source fails here instead of quietly testing
// an unmutated tree.
//
// Run: node --test scripts/check_dart_rpc_transport.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { checkDartRpcTransport, collectFiles, mapEntries, readSites } from './check_dart_rpc_transport.mjs';
import { loadFunctions } from './rpc_transport.mjs';

const TREE = collectFiles();
const FUNCTIONS = loadFunctions();
const API = 'packages/api_client/lib/src/api_client.dart';
const SOCIAL = 'apps/mobile_android/lib/social_service.dart';

/**
 * @param {string} rel @param {string} from @param {string} to
 * @returns {string[]} the findings for a copy of the tree with one edit
 */
function findingsAfter(rel, from, to) {
	const files = new Map(TREE);
	const src = files.get(rel);
	assert.ok(src !== undefined, `${rel} is not in the scanned set`);
	assert.equal(src.split(from).length, 2, `${rel}: \`${from}\` must match exactly once`);
	files.set(rel, src.replace(from, to));
	return checkDartRpcTransport(files, FUNCTIONS).findings;
}

test('the real tree is clean, and the scan reached both client trees', () => {
	const { findings, sites } = checkDartRpcTransport(TREE, FUNCTIONS);
	assert.deepEqual(findings, []);
	assert.ok(sites.length >= 60, `only ${sites.length} .rpc() call sites found`);
	assert.ok(sites.filter((s) => s.get).length >= 30, 'fewer than 30 GETs: the get: reader has stopped matching');
	for (const tree of ['packages/api_client/lib/', 'apps/mobile_android/lib/']) {
		assert.ok(sites.some((s) => s.where.startsWith(tree)), `no call site read under ${tree}`);
	}
});

test('the three reads § 1791 left POSTing from Dart now go out as GETs', () => {
	const { sites } = checkDartRpcTransport(TREE, FUNCTIONS);
	for (const name of ['my_pending_safety_requests', 'clip_route_for_viewer', 'get_event_meet_point']) {
		assert.equal(FUNCTIONS.get(name)?.volatility, 'stable', name);
		const calls = sites.filter((s) => s.fn === name);
		assert.ok(calls.length > 0, `${name} has no Dart call site`);
		assert.deepEqual(calls.filter((s) => !s.get).map((s) => s.where), [], `${name} is still a POST`);
	}
});

test('a stable all-scalar read sent as a POST is reported', () => {
	const found = findingsAfter(SOCIAL, "params: {'p_event_id': eventId}, get: true);", "params: {'p_event_id': eventId});");
	assert.equal(found.length, 1);
	assert.match(found[0], /get_event_meet_point: stable.*pass `get: true`/);
});

test('a no-argument read sent as a POST is told it needs a params map too', () => {
	const found = findingsAfter(API, "rpc('is_pro', params: const {}, get: true)", "rpc('is_pro')");
	assert.equal(found.length, 1);
	assert.match(found[0], /is_pro: .*`get: true` and `params: const \{\}`/);
});

test('a GET to a volatile function is reported', () => {
	const found = findingsAfter(API, "_client.rpc('confirm_age_and_terms')", "_client.rpc('confirm_age_and_terms', params: const {}, get: true)");
	assert.equal(found.length, 1);
	assert.match(found[0], /confirm_age_and_terms: sent as a GET, but volatile/);
});

test('a GET to a function taking a jsonb argument is reported', () => {
	const site = [...TREE.entries()].find(([, src]) => src.includes("'delete_notifications'"));
	assert.ok(site, 'delete_notifications has no Dart call site any more; pick another non-scalar RPC');
	const found = findingsAfter(site[0], "params: {'p_ids': ids})", "params: {'p_ids': ids}, get: true)");
	assert.equal(found.length, 1);
	assert.match(found[0], /delete_notifications: sent as a GET, but .*cannot be a query parameter: p_ids/);
});

test('a GET without a params map is reported, because postgrest-dart throws on one', () => {
	const found = findingsAfter(API, "rpc('my_pending_safety_requests',\n          params: const {}, get: true)", "rpc('my_pending_safety_requests', get: true)");
	assert.equal(found.length, 1);
	assert.match(found[0], /my_pending_safety_requests: a GET without a params map throws ArgumentError/);
});

test('a GET that would send null is reported', () => {
	const found = findingsAfter(API, "if (q != null && q.isNotEmpty) 'p_query': q,", "'p_query': (q != null && q.isNotEmpty) ? q : null,");
	assert.equal(found.length, 1);
	assert.match(found[0], /search_public_events\.p_query: a GET sends null as the string "null"/);
});

test('omitting a parameter whose default is not NULL is reported', () => {
	const found = findingsAfter(API, "        'p_tz': tz,\n        'p_source': ?source,", "        'p_tz': ?tz,\n        'p_source': ?source,");
	assert.equal(found.length, 1);
	assert.match(found[0], /run_streaks_for_user\.p_tz: omitted conditionally, but the parameter defaults to something other than NULL/);
});

test('a parameter name the function does not have is reported', () => {
	const found = findingsAfter(API, "'route_markers_for_viewer',\n      params: {'p_route_id': routeId},", "'route_markers_for_viewer',\n      params: {'p_route': routeId},");
	assert.ok(found.some((f) => /route_markers_for_viewer\.p_route: the function has no such parameter/.test(f)), found.join('\n'));
	assert.ok(found.some((f) => /route_markers_for_viewer\.p_route_id: a required parameter the GET never sends/.test(f)), found.join('\n'));
});

test('a non-literal function name or get flag is reported, never skipped', () => {
	const { unreadable } = readSites('x.dart', "await c.rpc(name, params: const {});");
	assert.equal(unreadable.length, 1);
	const files = new Map([['x.dart', "await c.rpc('is_pro', params: const {}, get: flag);"]]);
	assert.match(checkDartRpcTransport(files, FUNCTIONS).findings[0], /`get:` must be the literal/);
});

test('a commented-out call is not a call site', () => {
	const { sites } = readSites('x.dart', "// await c.rpc('is_pro');\n/* c.rpc('is_pro') */\nfinal ok = 1;");
	assert.deepEqual(sites, []);
});

test('a stale POST exemption is reported', () => {
	const found = checkDartRpcTransport(TREE, FUNCTIONS, { is_pro: 'test' }).findings;
	assert.deepEqual(found, ['POST_EXEMPT is_pro (test): no POST call site left']);
	const volatile = checkDartRpcTransport(TREE, FUNCTIONS, { confirm_age_and_terms: 'test' }).findings;
	assert.deepEqual(volatile, ['POST_EXEMPT confirm_age_and_terms (test): no longer a GET candidate']);
});

test('map literals are read entry by entry, collection-ifs included', () => {
	assert.deepEqual(mapEntries("const {}"), []);
	assert.deepEqual(mapEntries("<String, dynamic>{'a': 1, if (b != null) 'b': f(b, 2)}"), [
		{ key: 'a', conditional: false, value: '1' },
		{ key: 'b', conditional: true, value: 'f(b, 2)' }
	]);
	assert.deepEqual(mapEntries("{'a': ?a, 'b': a ?? b}"), [
		{ key: 'a', conditional: true, value: 'a' },
		{ key: 'b', conditional: false, value: 'a ?? b' }
	]);
	assert.deepEqual(mapEntries('{...rest}'), [{ key: null, conditional: false, value: '...rest' }]);
	assert.equal(mapEntries('params'), null);
});
