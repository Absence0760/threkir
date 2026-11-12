// Transport-agnostic handler for the AI route-description enhancement.
//
// The templated describer (`#lib/routes/route_description`) is the
// always-works L1 baseline and is rendered for everyone, free or Pro,
// with no network call. This handler is the strictly-additive L4
// enhancement: a Pro perk that asks Claude to turn the templated facts
// into a richer, more evocative paragraph. It is fail-closed on the
// paywall and degrades to the templated text on every failure mode —
// not-Pro, unconfigured key, model error, model refusal, or timeout —
// so the affordance never breaks the baseline.
//
// Wrapped twice, exactly like the coach handler (decisions.md § 53):
//   - apps/web/src/routes/api/coach/route-describe/+server.ts (dev)
//   - apps/web/lambda/coach/src/index.ts routes /route-describe (prod)
//
// Single non-streaming request — a route description is one short
// paragraph, well under the streaming-timeout threshold, so there's no
// SSE protocol here. Always returns JSON.

import Anthropic from '@anthropic-ai/sdk';
import { createClient } from '@supabase/supabase-js';

import {
	assembleEnglish,
	describeRoute,
	type RouteDescriptionInput,
	type RouteDescriptionParts,
} from '../route_description';
import { parsePreferredUnit, type PreferredUnit } from '../../types';
import { DEFAULT_LOCALE, isSupportedLocale, negotiateLocale, type Locale } from '../../i18n/locale';
import { parseAuthHeader } from '../../coach/limits';
import type { SupabaseClientFactory } from '../../coach/types';
import {
	AI_DISCLOSURE_VERSION_ROUTE_AI,
	aiDisclosureDenialBody,
	gateAiDisclosure,
} from '../../core/ai_disclosure';
import { refundRouteRateLimitSlot, spendRouteRateLimitSlot } from '../rate_limit';
import { supabaseErrorFields, thrownMessage } from '../../core/supabase_error';

/// Per-user ceiling on the billed Anthropic call. Sized like the sibling
/// `generate-route` bucket: 60/hour is far past any interactive use (one
/// tap per route on the route-detail page) while capping a scripted Pro
/// caller at 60 Opus requests an hour instead of unbounded.
export const ROUTE_DESCRIBE_RATE_BUCKET = 'route-describe';
export const ROUTE_DESCRIBE_RATE_MAX = 60;
export const ROUTE_DESCRIBE_RATE_WINDOW_S = 3600;

/**
 * Model + budget for the enhancement. The visible output is one short
 * 2-3 sentence paragraph, but adaptive thinking draws from the same
 * `max_tokens` ceiling — so the cap has to leave room for a thinking
 * block *plus* the paragraph, or the model can spend the budget thinking
 * and return empty text (which would then fall back to the template).
 * 1024 comfortably covers both; the prose itself stays short because the
 * system prompt asks for one paragraph. No streaming — well under the
 * streaming-timeout threshold.
 */
const ROUTE_DESCRIBE_MODEL = 'claude-opus-4-8';
const ROUTE_DESCRIBE_MAX_TOKENS = 1024;

/** Hard wall-clock cap so a slow model call can't hang the request. */
const ROUTE_DESCRIBE_TIMEOUT_MS = 12_000;

/**
 * Cap on the route name — the only free-text field that reaches the
 * prompt. The rest of the input is numeric. Names longer than this are
 * almost certainly junk / an injection attempt; truncate rather than
 * reject so a legitimately long name still yields a description.
 */
export const MAX_ROUTE_NAME_CHARS = 200;

/**
 * What the prompt calls the route when its name may not be sent: the caller
 * neither owns the route nor is it public, or the route could not be resolved.
 */
export const WITHHELD_ROUTE_NAME = 'This route';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// The structural surface the handler uses — narrow enough that a test can
/// hand in a fake without the SDK's whole client.
export interface RouteDescribeModelClient {
	messages: {
		create(
			body: Anthropic.MessageCreateParamsNonStreaming,
			options?: { timeout?: number },
		): PromiseLike<Anthropic.Message>;
	};
}

export interface RouteDescribeConfig {
	anthropicApiKey: string | undefined;
	publicSupabaseUrl: string;
	publicSupabaseAnonKey: string;
	/** Dev-only escape hatch — see the +server.ts / Lambda gates. */
	bypassPaywallEnabled: boolean;
	/**
	 * Both wrappers leave this unset and the handler falls back to the real
	 * `createClient`; unit tests inject a fake so the post-auth gates
	 * (consent, tier) are exercisable without a live Supabase. Same hook
	 * `CoachConfig` carries.
	 */
	createClient?: SupabaseClientFactory;
	/// Same hook for the model: unset in both wrappers, a fake in unit tests.
	createAnthropic?: (apiKey: string) => RouteDescribeModelClient;
}

export interface RouteDescribeResult {
	status: number;
	headers: Record<string, string>;
	body: string;
}

function json(
	status: number,
	payload: Record<string, unknown>,
): RouteDescribeResult {
	return {
		status,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(payload),
	};
}

/**
 * Coerce an untrusted request body into a `RouteDescriptionInput`.
 * Returns null when the body can't yield a usable input (no numeric
 * distance). Numbers are passed through to `describeRoute`, which does
 * its own NaN / negative clamping, so we only need shape validation
 * here.
 */
function parseInput(raw: unknown): RouteDescriptionInput | null {
	if (!raw || typeof raw !== 'object') return null;
	const o = raw as Record<string, unknown>;
	if (typeof o.distance_m !== 'number') return null;
	const name =
		typeof o.name === 'string' ? o.name.slice(0, MAX_ROUTE_NAME_CHARS) : WITHHELD_ROUTE_NAME;
	const surface =
		o.surface === 'road' || o.surface === 'trail' || o.surface === 'mixed'
			? o.surface
			: null;
	const pt = (v: unknown): { lat: number; lng: number } | undefined => {
		if (!v || typeof v !== 'object') return undefined;
		const p = v as Record<string, unknown>;
		return typeof p.lat === 'number' && typeof p.lng === 'number'
			? { lat: p.lat, lng: p.lng }
			: undefined;
	};
	return {
		name,
		distanceM: o.distance_m,
		elevationM: typeof o.elevation_m === 'number' ? o.elevation_m : null,
		surface,
		start: pt(o.start),
		end: pt(o.end),
	};
}

/** The `route_id` the caller named, or null when absent or not a UUID. */
export function parseRouteId(raw: unknown): string | null {
	if (!raw || typeof raw !== 'object') return null;
	const id = (raw as Record<string, unknown>).route_id;
	return typeof id === 'string' && UUID.test(id) ? id : null;
}

/**
 * The route name the prompt may carry, read from the database rather than the
 * request body: the stored name when the caller owns the route or it is
 * public, else null. A club-mate, a named share recipient or a follower can
 * open a route that is neither, and that route's name is its owner's, so it
 * does not go to a sub-processor on someone else's tap. The body's `name` is
 * never trusted here — a caller could otherwise send any route's name under
 * their own route's id. Every failure is null: the paragraph is still written,
 * just without the name.
 */
export async function promptRouteName(
	supabase: ReturnType<SupabaseClientFactory>,
	userId: string,
	routeId: string | null,
): Promise<string | null> {
	if (!routeId) return null;
	try {
		const own = await supabase
			.from('routes')
			.select('name, user_id, is_public')
			.eq('id', routeId)
			.maybeSingle();
		if (own.error) {
			console.error('[route-describe] route name lookup failed', supabaseErrorFields(own.error));
			return null;
		}
		const row = own.data as { name?: unknown; user_id?: unknown; is_public?: unknown } | null;
		if (row && (row.user_id === userId || row.is_public === true)) {
			return typeof row.name === 'string' ? row.name.slice(0, MAX_ROUTE_NAME_CHARS) : null;
		}
		// A public route the caller does not own is not readable on the base
		// table (decisions § 33); the view is the public read, and it already
		// leaves out a shadow-hidden route.
		const pub = await supabase.from('public_routes').select('name').eq('id', routeId).maybeSingle();
		if (pub.error) {
			console.error('[route-describe] public route name lookup failed', supabaseErrorFields(pub.error));
			return null;
		}
		const name = (pub.data as { name?: unknown } | null)?.name;
		return typeof name === 'string' ? name.slice(0, MAX_ROUTE_NAME_CHARS) : null;
	} catch (e) {
		console.error('[route-describe] route name lookup threw', { message: thrownMessage(e) });
		return null;
	}
}

/**
 * The unit the caller asked for, or null when the field is absent or not one
 * of `PreferredUnit`'s members — the handler then falls back to the account's
 * stored preference rather than trusting a malformed value.
 */
export function parseRequestedUnit(raw: unknown): PreferredUnit | null {
	if (!raw || typeof raw !== 'object') return null;
	const unit = (raw as Record<string, unknown>).unit;
	return unit === 'km' || unit === 'mi' ? unit : null;
}

/** Read `preferred_unit` off the profile row; anything unrecognised is km. */
function storedUnit(row: unknown): PreferredUnit {
	const raw = row && typeof row === 'object' ? (row as Record<string, unknown>).preferred_unit : null;
	return parsePreferredUnit(typeof raw === 'string' ? raw : null);
}

/**
 * The UI locale the caller asked for, or null when the field is absent or not
 * one of the seven canonical tags the clients ship (`SUPPORTED_LOCALES`) — the
 * handler then falls back to the account's stored language. Exact canonical
 * tags only: both clients send the identifier they already resolved, so a
 * `pt` or `fr-CA` here is a malformed caller, not a viewer to negotiate for.
 */
export function parseRequestedLocale(raw: unknown): Locale | null {
	if (!raw || typeof raw !== 'object') return null;
	const locale = (raw as Record<string, unknown>).locale;
	return typeof locale === 'string' && isSupportedLocale(locale) ? locale : null;
}

/**
 * The account's stored language, `user_settings.prefs.locale` — the universal
 * key both clients write from the language picker for server-sent copy
 * (docs/backend/settings.md). Normalised exactly as the email renderer does
 * (exact tag, then base language, then English). A failed read is an
 * auxiliary failure: logged, and answered in English rather than refusing
 * the paragraph.
 */
async function storedLocale(
	supabase: ReturnType<SupabaseClientFactory>,
	userId: string,
): Promise<Locale> {
	try {
		const res = await supabase
			.from('user_settings')
			.select('prefs')
			.eq('user_id', userId)
			.maybeSingle();
		if (res.error) {
			console.error('[route-describe] stored locale lookup failed', supabaseErrorFields(res.error));
			return DEFAULT_LOCALE;
		}
		const prefs: unknown = res.data?.prefs;
		const tag =
			prefs && typeof prefs === 'object' && !Array.isArray(prefs)
				? (prefs as Record<string, unknown>).locale
				: null;
		return negotiateLocale(null, typeof tag === 'string' ? tag : null);
	} catch (e) {
		console.error('[route-describe] stored locale lookup threw', { message: thrownMessage(e) });
		return DEFAULT_LOCALE;
	}
}

/**
 * The English name of each shipped locale's language, as the model is told
 * it. Portuguese names its variant: the two catalogues differ on a third of
 * their strings, and a Lisbon reader handed Brazilian prose is the divergence
 * the separate locale exists to close.
 */
export const LANGUAGE_NAME: Record<Locale, string> = {
	en: 'English',
	de: 'German',
	fr: 'French',
	es: 'Spanish',
	ja: 'Japanese',
	'pt-PT': 'European Portuguese (as written in Portugal)',
	'pt-BR': 'Brazilian Portuguese',
};

const UNIT_RULE: Record<PreferredUnit, string> = {
	km: 'Write every distance in kilometres (km) and every climb in metres (m). Never use miles or feet.',
	mi: 'Write every distance in miles (mi) and every climb in feet (ft). Never use kilometres or metres.',
};

/**
 * The user turn: the verified facts, stated in the viewer's unit, and an
 * instruction that the paragraph keeps to that unit and is written in the
 * viewer's language. The facts stay English — they are the model's input,
 * not the reader's text.
 */
export interface RouteDescribePromptInput {
	parts: RouteDescriptionParts;
	/** `promptRouteName`'s answer, or `WITHHELD_ROUTE_NAME`. */
	name: string;
	unit: PreferredUnit;
	locale: Locale;
}

export function routeDescribeUserMessage({
	parts,
	name,
	unit,
	locale,
}: RouteDescribePromptInput): string {
	return (
		`Facts about the route:\n${assembleEnglish(parts, name, unit)}\n\n` +
		`Surface: ${parts.surface ?? 'unspecified'}. ` +
		`Elevation character: ${parts.elevation}. ` +
		`Shape: ${parts.shape}.\n\n` +
		`${UNIT_RULE[unit]}\n\n` +
		`Write the paragraph in ${LANGUAGE_NAME[locale]}. Keep the route name and any ` +
		'place names exactly as given; do not translate them.\n\n' +
		'Write the description paragraph now.'
	);
}

const SYSTEM_PROMPT =
	'You write short, vivid descriptions of running routes for a running app. ' +
	'You are given the verified facts about one route (distance, surface, ' +
	'elevation character, shape). Write ONE paragraph of 2-3 sentences that a ' +
	'runner browsing routes would find useful and inviting. Stay strictly ' +
	'grounded in the facts provided — do not invent landmarks, scenery, ' +
	'difficulty ratings, or place names that are not in the facts. Do not use ' +
	'markdown, headings, or bullet points. Write distances and climbing only ' +
	'in the unit the facts are given in. Write in the language the request ' +
	'names, even though the facts are given in English. Return only the paragraph.';

/**
 * Enhance a route description with Claude. Always resolves to a
 * `RouteDescribeResult` carrying a `description` and a `source`
 * (`'ai'` when the model produced it, `'template'` on any fallback) so
 * the client can show the right attribution. Never throws — the
 * templated text is the floor.
 */
export async function handleRouteDescribe(
	authHeader: string | null,
	rawBody: unknown,
	config: RouteDescribeConfig,
): Promise<RouteDescribeResult> {
	const input = parseInput(rawBody);
	if (!input) return json(400, { error: 'invalid route input' });

	const parts = describeRoute(input);
	const routeId = parseRouteId(rawBody);
	const requestedUnit = parseRequestedUnit(rawBody);
	const requestedLocale = parseRequestedLocale(rawBody);

	const accessToken = parseAuthHeader(authHeader);
	if (!accessToken) return json(401, { error: 'not authenticated' });

	const makeClient = config.createClient ?? createClient;
	const supabase = makeClient(config.publicSupabaseUrl, config.publicSupabaseAnonKey, {
		global: { headers: { Authorization: `Bearer ${accessToken}` } },
	});
	const userRes = await supabase.auth.getUser(accessToken);
	if (!userRes.data.user) {
		// Mirror the coach handler: log the detail, return a generic 401
		// so the GoTrue error can't be used as a token-shape oracle.
		console.error('[route-describe] auth failed', {
			error: userRes.error?.message ?? 'no user returned',
		});
		return json(401, { error: 'not authenticated' });
	}

	// GDPR Art 6(1)(a) — issue #734. This endpoint ships the route's stats
	// (and its name, when the caller owns it or it is public) to Anthropic, which the Coach-scoped disclosure never
	// described, so it requires the widened version of the record. A user
	// who only ever accepted the Coach disclosure is refused here until
	// they accept the wider one. The bypass flag is deliberately NOT
	// honoured: it exists to skip the paywall in dev, not the lawful basis
	// for sending a real person's data to a real sub-processor.
	//
	// Sits before the tier check so the order matches the coach handler and
	// there is exactly one place the fan-out can be reasoned about. The
	// templated description still rides along on the 403, so the L1
	// baseline survives a refusal (layered resilience).
	let profileRow: unknown = null;
	const disclosure = await gateAiDisclosure(
		async () => {
			const res = await supabase.rpc('get_my_profile', undefined, { get: true }).maybeSingle();
			profileRow = res.data;
			return res;
		},
		AI_DISCLOSURE_VERSION_ROUTE_AI,
		'route-describe',
	);
	// A client that sent no unit (or one outside `PreferredUnit`) is answered
	// in the account's stored unit, km when that is unset. The templated
	// description in that unit is the response on every branch from here
	// that does not reach the model.
	const unit = requestedUnit ?? storedUnit(profileRow);
	const templated = assembleEnglish(parts, input.name, unit);
	if (!disclosure.ok) {
		return json(disclosure.status, {
			error:
				disclosure.reason === 'lookup_failed' ? 'consent check failed' : 'ai disclosure required',
			...(disclosure.status === 403 ? aiDisclosureDenialBody(AI_DISCLOSURE_VERSION_ROUTE_AI) : {}),
			description: templated,
			source: 'template',
		});
	}

	// Paywall gate — the AI enhancement is a Pro perk. Fail-closed: an
	// RPC error or a non-true result leaves the caller on the templated
	// description with a 403, never silently granting the perk. The
	// bypass is honoured only when the wrapper computed it from the
	// dev-only env gates.
	let isPro = false;
	if (config.bypassPaywallEnabled) {
		isPro = true;
	} else {
		const proRes = await supabase.rpc('is_pro', undefined, { get: true });
		if (proRes.error) {
			console.error('[route-describe] is_pro lookup failed', supabaseErrorFields(proRes.error));
			return json(500, { error: 'tier check failed', description: templated, source: 'template' });
		}
		isPro = proRes.data === true;
	}
	if (!isPro) {
		// Not an error — the free tier gets the templated description.
		// 200 with source:'template' + upgrade:true lets the UI surface a
		// "Enhance with AI (Pro)" upsell without a failed-request banner.
		return json(200, {
			description: templated,
			source: 'template',
			upgrade: true,
		});
	}

	// Pro path. Missing key → degrade to templated rather than 503 — the
	// runner still gets a description. Checked before the throttle so a
	// misconfiguration never spends a slot.
	if (!config.anthropicApiKey) {
		console.error('[route-describe] missing ANTHROPIC_API_KEY — serving templated description');
		return json(200, { description: templated, source: 'template' });
	}

	// Per-user ceiling on the billed fan-out. Pro is a monthly price, not a
	// per-call one, so without this a single subscription (or one leaked Pro
	// JWT) buys unbounded Opus calls on the operator's key — the per-IP WAF
	// rule can't see a JWT spread over an IP pool. Only Pro callers reach
	// here, so a free caller is never charged a slot. Fail-closed: a throttle
	// error serves the templated description rather than the model. A call
	// that falls back to the template gives its slot back.
	const userId = userRes.data.user.id;
	let spendId: string | null = null;
	if (!config.bypassPaywallEnabled) {
		const rl = await spendRouteRateLimitSlot(
			supabase,
			userId,
			ROUTE_DESCRIBE_RATE_BUCKET,
			ROUTE_DESCRIBE_RATE_MAX,
			ROUTE_DESCRIBE_RATE_WINDOW_S,
		);
		if (rl.verdict !== 'ok') {
			return json(200, { description: templated, source: 'template' });
		}
		spendId = rl.spendId;
	}

	// Read only on the path that reaches the model: every response before this
	// one is the server's English template, which both clients replace with
	// their own localised sentence.
	const locale = requestedLocale ?? (await storedLocale(supabase, userId));
	const promptName = (await promptRouteName(supabase, userId, routeId)) ?? WITHHELD_ROUTE_NAME;

	async function refundSlot(reason: string): Promise<void> {
		await refundRouteRateLimitSlot(supabase, userId, ROUTE_DESCRIBE_RATE_BUCKET, spendId, reason);
	}

	try {
		const anthropic: RouteDescribeModelClient = config.createAnthropic
			? config.createAnthropic(config.anthropicApiKey)
			: new Anthropic({ apiKey: config.anthropicApiKey });
		const message = await anthropic.messages.create(
			{
				model: ROUTE_DESCRIBE_MODEL,
				max_tokens: ROUTE_DESCRIBE_MAX_TOKENS,
				thinking: { type: 'adaptive' },
				system: SYSTEM_PROMPT,
				messages: [
					{
						role: 'user',
						content: routeDescribeUserMessage({ parts, name: promptName, unit, locale }),
					},
				],
			},
			{ timeout: ROUTE_DESCRIBE_TIMEOUT_MS },
		);

		// Claude Fable/Opus can return stop_reason: "refusal" (HTTP 200,
		// empty/partial content). Check it before reading content[] —
		// degrade to the templated text on a refusal.
		if (message.stop_reason === 'refusal') {
			console.warn('[route-describe] model refused — serving templated description');
			await refundSlot('refusal');
			return json(200, { description: templated, source: 'template' });
		}

		const text = message.content
			.filter((b): b is Anthropic.TextBlock => b.type === 'text')
			.map((b) => b.text)
			.join('')
			.trim();

		if (!text) {
			// Empty completion (hit max_tokens before any text, etc.) —
			// fall back rather than show a blank box.
			await refundSlot('empty_text');
			return json(200, { description: templated, source: 'template' });
		}
		return json(200, { description: text, source: 'ai' });
	} catch (e) {
		// Any provider failure (rate limit, timeout, 5xx, network) →
		// templated description. Layered resilience: the L4 enhancement
		// can never break the L1 baseline.
		// Normalised rather than handed over whole -- see the sibling note in
		// route_request/handler.ts.
		console.error('[route-describe] provider call failed — serving templated description', {
			message: thrownMessage(e),
			stack: e instanceof Error ? e.stack : undefined,
		});
		await refundSlot('provider_error');
		return json(200, { description: templated, source: 'template' });
	}
}
