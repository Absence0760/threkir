import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	handleRouteDescribe,
	LANGUAGE_NAME,
	MAX_ROUTE_NAME_CHARS,
	parseRequestedLocale,
	parseRequestedUnit,
	parseRouteId,
	routeDescribeUserMessage,
	ROUTE_DESCRIBE_RATE_BUCKET,
	ROUTE_DESCRIBE_RATE_MAX,
	ROUTE_DESCRIBE_RATE_WINDOW_S,
	WITHHELD_ROUTE_NAME,
} from './handler';
import type { RouteDescribeConfig } from './handler';
import { describeRoute } from '../route_description';
import { SUPPORTED_LOCALES } from '../../i18n/locale';

function baseConfig(): RouteDescribeConfig {
	return {
		anthropicApiKey: 'sk-ant-test-FAKE-KEY-NEVER-USED',
		publicSupabaseUrl: 'http://127.0.0.1:24321',
		publicSupabaseAnonKey: 'sb_publishable_fake_local_anon_key',
		bypassPaywallEnabled: false,
	};
}

function parse(result: Awaited<ReturnType<typeof handleRouteDescribe>>): {
	status: number;
	body: {
		error?: string;
		description?: string;
		source?: string;
		upgrade?: boolean;
		code?: string;
		required_version?: number;
	};
} {
	return { status: result.status, body: JSON.parse(result.body) };
}

test('returns 400 when the body is not an object', async () => {
	const r = parse(await handleRouteDescribe('Bearer x', null, baseConfig()));
	assert.equal(r.status, 400);
	assert.equal(r.body.error, 'invalid route input');
});

test('returns 400 when distance_m is missing or non-numeric', async () => {
	const r1 = parse(await handleRouteDescribe('Bearer x', { name: 'x' }, baseConfig()));
	assert.equal(r1.status, 400);
	const r2 = parse(
		await handleRouteDescribe('Bearer x', { name: 'x', distance_m: '10000' }, baseConfig()),
	);
	assert.equal(r2.status, 400);
});

test('returns 401 when there is no auth header (body is otherwise valid)', async () => {
	const r = parse(
		await handleRouteDescribe(null, { name: 'Park loop', distance_m: 5000 }, baseConfig()),
	);
	assert.equal(r.status, 401);
	assert.equal(r.body.error, 'not authenticated');
});

test('returns 401 for an empty Bearer token', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer ', { name: 'x', distance_m: 5000 }, baseConfig()),
	);
	assert.equal(r.status, 401);
});

test('input parse accepts a valid route shape (no early 400) — fails later on auth', async () => {
	// A fully-formed body must NOT 400; it should fall through to the
	// auth check (401 here, since the fake token can't resolve a user
	// against the unreachable local stack — but the point is it's past
	// input validation, returning 401 not 400).
	const r = parse(
		await handleRouteDescribe(
			null,
			{
				name: 'Riverside 10K',
				distance_m: 10000,
				elevation_m: 150,
				surface: 'mixed',
				start: { lat: 51.5, lng: -0.12 },
				end: { lat: 51.5, lng: -0.12 },
			},
			baseConfig(),
		),
	);
	assert.equal(r.status, 401);
});

test('MAX_ROUTE_NAME_CHARS is a sane cap', () => {
	// Guards against an accidental 0 / negative that would blank every
	// name. Not a behavioural assertion on the handler, but pins the
	// constant the prompt-injection guard depends on.
	assert.ok(MAX_ROUTE_NAME_CHARS >= 100 && MAX_ROUTE_NAME_CHARS <= 1000);
});

// ─────────────── AI-disclosure consent gate (issue #734) ───────────────

/// Minimal Supabase stand-in: enough for auth.getUser + the two RPCs the
/// gates read. Injected through `config.createClient`, which exists so the
/// post-auth branches are reachable without a live stack.
function stubClient(profileRow: unknown, opts: { isPro?: boolean; profileError?: unknown } = {}) {
	return () =>
		({
			auth: {
				getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }),
			},
			rpc: (name: string) => {
				if (name === 'get_my_profile') {
					return {
						maybeSingle: async () => ({
							data: profileRow,
							error: opts.profileError ?? null,
						}),
					};
				}
				return Promise.resolve({ data: opts.isPro === true, error: null });
			},
		}) as never;
}

const ACCEPTED_AT = '2026-01-01T00:00:00Z';
const VALID_BODY = { name: 'Riverside 10K', distance_m: 10000 };

test('refuses a caller who accepted only the Coach disclosure', async () => {
	// Reason: issue #734. route-describe ships the route name + stats to
	// Anthropic, which the v1 Coach copy never described. A v1 acceptance
	// must not be read as covering it.
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 1, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
	assert.equal(r.body.required_version, 2);
	// Layered resilience: the templated baseline still rides along.
	assert.equal(r.body.source, 'template');
	assert.ok((r.body.description ?? '').length > 0);
});

test('refuses a caller with no consent record at all', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: null, coach_consent_at: null }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

test('refuses a version this build does not know — fail closed, never grant', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 99, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

test('an unreadable consent record is a 500, not a silent pass', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient(null, { profileError: { code: '42501', message: 'denied' } }),
		}),
	);
	assert.equal(r.status, 500);
	assert.equal(r.body.error, 'consent check failed');
	assert.equal(r.body.source, 'template');
});

test('the widened acceptance clears the consent gate — the tier gate is what answers next', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: stubClient(
				{ ai_disclosure_version: 2, coach_consent_at: ACCEPTED_AT },
				{ isPro: false },
			),
		}),
	);
	assert.equal(r.status, 200);
	assert.equal(r.body.upgrade, true);
	assert.equal(r.body.code, undefined);
});

test('the dev paywall bypass does not bypass the consent gate', async () => {
	// Reason: BYPASS_PAYWALL exists to skip a billing check in local dev.
	// A lawful basis for sending a real person's data to a real
	// sub-processor is not a billing check.
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			bypassPaywallEnabled: true,
			createClient: stubClient({ ai_disclosure_version: 1, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
});

// ─────────────── Rate-limit slot: spent before the model, refunded on failure ───────────────

/// A Pro caller whose throttle hands out ticket `ticket-1`; records every RPC.
/// [profile] is merged into the consenting profile row `get_my_profile` returns;
/// [settings] is what a `user_settings` read answers; [routes] what a read of
/// `routes` (the base table, under the caller's RLS) and of the `public_routes`
/// view answer.
type Answer = { data?: unknown; error?: unknown; throws?: boolean };
function proClient(
	profile: Record<string, unknown> = {},
	settings: Answer = {},
	routes: { routes?: Answer; public_routes?: Answer } = {},
) {
	const calls: Array<{ name: string; args?: unknown }> = [];
	const settingsReads: Array<{ table: string; column: string; value: unknown }> = [];
	const routeReads: Array<{ table: string; column: string; value: unknown }> = [];
	const factory = () =>
		({
			auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
			from: (table: string) => ({
				select: () => ({
					eq: (column: string, value: unknown) => ({
						maybeSingle: async () => {
							const isRoute = table === 'routes' || table === 'public_routes';
							(isRoute ? routeReads : settingsReads).push({ table, column, value });
							const answer: Answer = isRoute
								? (routes[table as 'routes' | 'public_routes'] ?? {})
								: settings;
							if (answer.throws) throw new Error('socket hang up');
							return { data: answer.data ?? null, error: answer.error ?? null };
						},
					}),
				}),
			}),
			rpc: (name: string, args?: unknown) => {
				calls.push({ name, args });
				if (name === 'get_my_profile') {
					return {
						maybeSingle: async () => ({
							data: { ai_disclosure_version: 2, coach_consent_at: ACCEPTED_AT, ...profile },
							error: null,
						}),
					};
				}
				if (name === 'spend_rate_limit_slot') {
					return Promise.resolve({
						data: [{ allowed: true, retry_after_seconds: 0, spend_id: 'ticket-1' }],
						error: null,
					});
				}
				return Promise.resolve({ data: true, error: null });
			},
		}) as never;
	return { factory, names: () => calls.map((c) => c.name), calls, settingsReads, routeReads };
}

function fakeModel(respond: () => unknown) {
	let calls = 0;
	return {
		create: () => ({
			messages: {
				create: async () => {
					calls += 1;
					return respond() as never;
				},
			},
		}),
		calls: () => calls,
	};
}

function quietly<T>(fn: () => Promise<T>): Promise<T> {
	const [err, warn] = [console.error, console.warn];
	console.error = () => {};
	console.warn = () => {};
	return fn().finally(() => {
		console.error = err;
		console.warn = warn;
	});
}

test('an AI description spends one slot of the route-describe bucket and keeps it', async () => {
	const sb = proClient();
	const r = parse(
		await handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			createClient: sb.factory,
			createAnthropic: fakeModel(() => ({
				stop_reason: 'end_turn',
				content: [{ type: 'text', text: 'A flat riverside loop.' }],
			})).create,
		}),
	);
	assert.equal(r.status, 200);
	assert.equal(r.body.source, 'ai');
	assert.deepEqual(sb.names(), ['get_my_profile', 'is_pro', 'spend_rate_limit_slot']);
	assert.deepEqual(sb.calls[2].args, {
		p_user_id: 'user-1',
		p_bucket: ROUTE_DESCRIBE_RATE_BUCKET,
		p_max: ROUTE_DESCRIBE_RATE_MAX,
		p_window_seconds: ROUTE_DESCRIBE_RATE_WINDOW_S,
	});
});

test('a refusal, an empty completion and a provider failure each serve the template and refund the slot', async () => {
	for (const respond of [
		() => ({ stop_reason: 'refusal', content: [] }),
		() => ({ stop_reason: 'max_tokens', content: [{ type: 'text', text: '  ' }] }),
		() => {
			throw Object.assign(new Error('529 overloaded'), { status: 529 });
		},
	]) {
		const sb = proClient();
		const r = parse(
			await quietly(() =>
				handleRouteDescribe('Bearer x', VALID_BODY, {
					...baseConfig(),
					createClient: sb.factory,
					createAnthropic: fakeModel(respond).create,
				}),
			),
		);
		assert.equal(r.status, 200);
		assert.equal(r.body.source, 'template');
		assert.deepEqual(sb.names(), ['get_my_profile', 'is_pro', 'spend_rate_limit_slot', 'refund_rate_limit_slot']);
		assert.deepEqual(sb.calls[3].args, {
			p_user_id: 'user-1',
			p_bucket: ROUTE_DESCRIBE_RATE_BUCKET,
			p_spend_id: 'ticket-1',
		});
	}
});

test('a missing key serves the template without spending a slot', async () => {
	const sb = proClient();
	const r = parse(
		await quietly(() =>
			handleRouteDescribe('Bearer x', VALID_BODY, {
				...baseConfig(),
				anthropicApiKey: undefined,
				createClient: sb.factory,
			}),
		),
	);
	assert.equal(r.body.source, 'template');
	assert.equal(sb.names().includes('spend_rate_limit_slot'), false);
});

// ─────────────── the viewer's unit (miles runners get miles) ───────────────

const SUMMIT = describeRoute({
	name: 'Summit Trail',
	distanceM: 12000,
	elevationM: 480,
	surface: 'trail',
	start: { lat: 51.5, lng: -0.12 },
	end: { lat: 51.7, lng: 0.0 },
});

test('the prompt for a km viewer states km and m and requires them', () => {
	const msg = routeDescribeUserMessage({ parts: SUMMIT, name: 'Summit Trail', unit: 'km', locale: 'en' });
	assert.match(msg, /Summit Trail is a 12\.0 km trail point-to-point route with 480 m of climbing/);
	assert.match(msg, /Write every distance in kilometres \(km\) and every climb in metres \(m\)\. Never use miles or feet\./);
	assert.doesNotMatch(msg, /\bmi\b|\bft\b/);
});

test('the prompt for a miles viewer states mi and ft and requires them', () => {
	const msg = routeDescribeUserMessage({ parts: SUMMIT, name: 'Summit Trail', unit: 'mi', locale: 'en' });
	assert.match(msg, /Summit Trail is a 7\.5 mi trail point-to-point route with 1575 ft of climbing/);
	assert.match(msg, /Write every distance in miles \(mi\) and every climb in feet \(ft\)\. Never use kilometres or metres\./);
	assert.doesNotMatch(msg, /\bkm\b|\d m\b/);
});

test('parseRequestedUnit admits only the PreferredUnit members', () => {
	assert.equal(parseRequestedUnit({ unit: 'km' }), 'km');
	assert.equal(parseRequestedUnit({ unit: 'mi' }), 'mi');
	for (const unit of ['MI', 'miles', 'm', '', 1, null, undefined, ['mi'], { mi: true }]) {
		assert.equal(parseRequestedUnit({ unit }), null, `unit ${JSON.stringify(unit)}`);
	}
	assert.equal(parseRequestedUnit(null), null);
});

/// A model fake that records the user turn it was sent.
function capturingModel() {
	const prompts: string[] = [];
	return {
		create: () => ({
			messages: {
				create: async (body: { messages: Array<{ content: unknown }> }) => {
					prompts.push(String(body.messages[0].content));
					return { stop_reason: 'end_turn', content: [{ type: 'text', text: 'A loop.' }] } as never;
				},
			},
		}),
		prompts,
	};
}

test('the requested unit reaches the prompt and wins over the stored preference', async () => {
	const model = capturingModel();
	await handleRouteDescribe('Bearer x', { ...VALID_BODY, unit: 'mi' }, {
		...baseConfig(),
		createClient: proClient({ preferred_unit: 'km' }).factory,
		createAnthropic: model.create,
	});
	assert.equal(model.prompts.length, 1);
	assert.match(model.prompts[0], /6\.2 mi/);
	assert.match(model.prompts[0], /Write every distance in miles/);
});

test('a missing or malformed unit falls back to the stored preference, then km', async () => {
	for (const [body, stored, expected] of [
		[VALID_BODY, 'mi', /6\.2 mi/],
		[{ ...VALID_BODY, unit: 'furlongs' }, 'mi', /6\.2 mi/],
		[{ ...VALID_BODY, unit: 'furlongs' }, null, /10\.0 km/],
		[VALID_BODY, 'leagues', /10\.0 km/],
	] as const) {
		const model = capturingModel();
		await handleRouteDescribe('Bearer x', body, {
			...baseConfig(),
			createClient: proClient({ preferred_unit: stored }).factory,
			createAnthropic: model.create,
		});
		assert.match(model.prompts[0], expected, `${JSON.stringify(body)} / stored ${stored}`);
	}
});

test('the templated fallback is in the viewer unit too', async () => {
	const r = parse(
		await handleRouteDescribe('Bearer x', { ...VALID_BODY, unit: 'mi' }, {
			...baseConfig(),
			createClient: stubClient({ ai_disclosure_version: 2, coach_consent_at: ACCEPTED_AT }),
		}),
	);
	assert.equal(r.body.source, 'template');
	assert.equal(r.body.upgrade, true);
	assert.match(r.body.description ?? '', /^Riverside 10K is a 6\.2 mi /);
});

// ─────────────── the viewer's language (a French reader gets French) ───────────────

test('the prompt names the viewer language in English and keeps names untranslated', () => {
	for (const locale of SUPPORTED_LOCALES) {
		const msg = routeDescribeUserMessage({ parts: SUMMIT, name: 'Summit Trail', unit: 'km', locale });
		assert.ok(
			msg.includes(`Write the paragraph in ${LANGUAGE_NAME[locale]}.`),
			`${locale}: ${msg}`,
		);
		assert.match(msg, /Keep the route name and any place names exactly as given; do not translate them\./);
		// The unit rule from the miles fix survives alongside the language rule.
		assert.match(msg, /Write every distance in kilometres \(km\)/);
	}
	assert.equal(LANGUAGE_NAME['pt-PT'], 'European Portuguese (as written in Portugal)');
	assert.equal(LANGUAGE_NAME['pt-BR'], 'Brazilian Portuguese');
});

test('parseRequestedLocale admits only the seven canonical tags the clients ship', () => {
	for (const locale of SUPPORTED_LOCALES) {
		assert.equal(parseRequestedLocale({ locale }), locale);
	}
	for (const locale of ['pt', 'pt-br', 'PT-PT', 'fr-CA', 'de_DE', 'zh', '', 1, null, undefined, ['fr'], { fr: true }]) {
		assert.equal(parseRequestedLocale({ locale }), null, `locale ${JSON.stringify(locale)}`);
	}
	assert.equal(parseRequestedLocale(null), null);
});

test('the requested locale reaches the prompt and wins over the stored language, with no settings read', async () => {
	const model = capturingModel();
	const sb = proClient({}, { data: { prefs: { locale: 'de' } } });
	await handleRouteDescribe('Bearer x', { ...VALID_BODY, locale: 'ja' }, {
		...baseConfig(),
		createClient: sb.factory,
		createAnthropic: model.create,
	});
	assert.match(model.prompts[0], /Write the paragraph in Japanese\./);
	assert.deepEqual(sb.settingsReads, []);
});

test('a missing or malformed locale falls back to the stored language, then English', async () => {
	for (const [body, settings, expected] of [
		[VALID_BODY, { data: { prefs: { locale: 'fr' } } }, 'French'],
		[{ ...VALID_BODY, locale: 'klingon' }, { data: { prefs: { locale: 'pt-BR' } } }, 'Brazilian Portuguese'],
		// The stored tag is whatever a client wrote, so it is normalised like
		// the email renderer does: exact, then base language, then English.
		[VALID_BODY, { data: { prefs: { locale: 'pt' } } }, 'European Portuguese (as written in Portugal)'],
		[VALID_BODY, { data: { prefs: { locale: 'de-AT' } } }, 'German'],
		[VALID_BODY, { data: { prefs: { locale: 'zh' } } }, 'English'],
		[VALID_BODY, { data: { prefs: { locale: 7 } } }, 'English'],
		[VALID_BODY, { data: { prefs: {} } }, 'English'],
		[VALID_BODY, { data: null }, 'English'],
		[VALID_BODY, { error: { message: 'boom', code: 'XX000' } }, 'English'],
		[VALID_BODY, { throws: true }, 'English'],
	] as const) {
		const model = capturingModel();
		const sb = proClient({}, settings);
		const r = parse(
			await quietly(() =>
				handleRouteDescribe('Bearer x', body, {
					...baseConfig(),
					createClient: sb.factory,
					createAnthropic: model.create,
				}),
			),
		);
		const label = `${JSON.stringify(body)} / ${JSON.stringify(settings)}`;
		// A failed lookup is auxiliary: the paragraph is still written.
		assert.equal(r.body.source, 'ai', label);
		assert.ok(model.prompts[0].includes(`Write the paragraph in ${expected}.`), label);
		assert.deepEqual(sb.settingsReads, [{ table: 'user_settings', column: 'user_id', value: 'user-1' }], label);
	}
});

test('a caller who never reaches the model costs no settings read', async () => {
	const sb = proClient();
	await quietly(() =>
		handleRouteDescribe('Bearer x', VALID_BODY, {
			...baseConfig(),
			anthropicApiKey: undefined,
			createClient: sb.factory,
		}),
	);
	assert.deepEqual(sb.settingsReads, []);
});

// ─────────────── Route name scope: owner or public only ───────────────

const ROUTE_ID = '5f0c1e2a-3b4c-4d5e-8f60-718293a4b5c6';

test('parseRouteId admits only a UUID', () => {
	assert.equal(parseRouteId({ route_id: ROUTE_ID }), ROUTE_ID);
	for (const id of ['', 'route-1', 7, null, undefined, [ROUTE_ID], `${ROUTE_ID}x`]) {
		assert.equal(parseRouteId({ route_id: id }), null, `route_id ${JSON.stringify(id)}`);
	}
	assert.equal(parseRouteId(null), null);
});

/// Drive one model-reaching request and return the user turn the model got.
async function promptFor(
	body: Record<string, unknown>,
	routes: Parameters<typeof proClient>[2],
): Promise<{ prompt: string; sb: ReturnType<typeof proClient> }> {
	const model = capturingModel();
	const sb = proClient({}, { data: { prefs: { locale: 'en' } } }, routes);
	const r = parse(
		await quietly(() =>
			handleRouteDescribe('Bearer x', body, {
				...baseConfig(),
				createClient: sb.factory,
				createAnthropic: model.create,
			}),
		),
	);
	assert.equal(r.body.source, 'ai');
	assert.equal(model.prompts.length, 1);
	return { prompt: model.prompts[0], sb };
}

test("the owner's route name reaches the prompt, read from the database, not the body", async () => {
	const { prompt, sb } = await promptFor(
		{ ...VALID_BODY, name: 'Typed by the client', route_id: ROUTE_ID },
		{ routes: { data: { name: 'Stored Name', user_id: 'user-1', is_public: false } } },
	);
	assert.match(prompt, /Stored Name is a /);
	assert.ok(!prompt.includes('Typed by the client'));
	assert.deepEqual(sb.routeReads, [{ table: 'routes', column: 'id', value: ROUTE_ID }]);
});

test("a public route's name reaches the prompt, through the view when the base table hides it", async () => {
	const viaView = await promptFor(
		{ ...VALID_BODY, route_id: ROUTE_ID },
		{ public_routes: { data: { name: 'Public Loop' } } },
	);
	assert.match(viaView.prompt, /Public Loop is a /);
	assert.deepEqual(
		viaView.sb.routeReads.map((r) => r.table),
		['routes', 'public_routes'],
	);
	const viaBase = await promptFor(
		{ ...VALID_BODY, route_id: ROUTE_ID },
		{ routes: { data: { name: 'Club Public', user_id: 'someone-else', is_public: true } } },
	);
	assert.match(viaBase.prompt, /Club Public is a /);
});

test("a route the caller can open but neither owns nor is public keeps its name out of the prompt", async () => {
	// A club-mate, a named share recipient or a follower reads the row under
	// RLS; the name is still the owner's.
	const { prompt } = await promptFor(
		{ ...VALID_BODY, route_id: ROUTE_ID },
		{ routes: { data: { name: 'Secret Club Route', user_id: 'someone-else', is_public: false } } },
	);
	assert.ok(!prompt.includes('Secret Club Route'));
	assert.ok(!prompt.includes('Riverside 10K'));
	assert.match(prompt, new RegExp(`${WITHHELD_ROUTE_NAME} is a `));
});

test('no route id, an unresolvable one, or a failed lookup sends no name at all', async () => {
	for (const [label, body, routes] of [
		['no route_id', VALID_BODY, {}],
		['malformed route_id', { ...VALID_BODY, route_id: 'r1' }, {}],
		['not found', { ...VALID_BODY, route_id: ROUTE_ID }, {}],
		['base error', { ...VALID_BODY, route_id: ROUTE_ID }, { routes: { error: { message: 'boom' } } }],
		['view error', { ...VALID_BODY, route_id: ROUTE_ID }, { public_routes: { error: { message: 'boom' } } }],
		['throws', { ...VALID_BODY, route_id: ROUTE_ID }, { routes: { throws: true } }],
	] as const) {
		const { prompt } = await promptFor(body, routes);
		assert.ok(!prompt.includes('Riverside 10K'), label);
		assert.match(prompt, new RegExp(`${WITHHELD_ROUTE_NAME} is a `), label);
	}
});

test('the stored name is cut to MAX_ROUTE_NAME_CHARS', async () => {
	const { prompt } = await promptFor(
		{ ...VALID_BODY, route_id: ROUTE_ID },
		{ routes: { data: { name: 'x'.repeat(MAX_ROUTE_NAME_CHARS + 50), user_id: 'user-1', is_public: false } } },
	);
	assert.ok(prompt.includes('x'.repeat(MAX_ROUTE_NAME_CHARS)));
	assert.ok(!prompt.includes('x'.repeat(MAX_ROUTE_NAME_CHARS + 1)));
});

test('a caller who never reaches the model costs no route read', async () => {
	const sb = proClient();
	await quietly(() =>
		handleRouteDescribe('Bearer x', { ...VALID_BODY, route_id: ROUTE_ID }, {
			...baseConfig(),
			anthropicApiKey: undefined,
			createClient: sb.factory,
		}),
	);
	assert.deepEqual(sb.routeReads, []);
});
