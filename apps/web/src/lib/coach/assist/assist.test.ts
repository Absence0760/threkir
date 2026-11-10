// The coach assistant (issue #1215 Phase 4): the consent ladder, the context
// registry and every gate of handleCoachAssist, with Supabase and the model
// injected through the config seams.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { en } from '../../i18n/locales/en';
import { COACH_ASSIST_CONSENT_VERSION, coachAssistConsentCovers } from './consent';
import {
	COACH_ASSIST_REGISTRY,
	buildCoachAssistContext,
	coachAssistAllows,
	withholdUnconsented,
} from './context';
import {
	ATHLETE_CONSENT_REQUIRED,
	coachAssistToday,
	handleCoachAssist,
	parseCoachAssistInput,
	type CoachAssistConfig,
	type CoachAssistModelClient,
} from './handler';

const ATHLETE = '11111111-2222-4333-8444-555555555555';
const COACH = 'c0ac0000-0000-4000-8000-000000000001';
const NOW = Date.UTC(2026, 10, 10, 12);
const VALID = { athlete_id: ATHLETE, mode: 'reply', today: '2026-11-10', locale: 'en' };

test('the consent version is the one coach_assist_consent_current_version() returns', () => {
	const dir = fileURLToPath(new URL('../../../../../backend/supabase/migrations/', import.meta.url));
	const file = readdirSync(dir).find((f) => f.endsWith('_coach_assist.sql'));
	assert.ok(file, 'the coach_assist migration is missing — re-anchor');
	const m = readFileSync(dir + file, 'utf8').match(
		/function coach_assist_consent_current_version\(\)[\s\S]*?select (\d+)::smallint/,
	);
	assert.ok(m, 'the version was not found in the migration — re-anchor');
	assert.equal(COACH_ASSIST_CONSENT_VERSION, Number(m[1]));
});

test('a stored consent covers a lane only inside the known ladder', () => {
	assert.equal(coachAssistConsentCovers(1, 1), true);
	assert.equal(coachAssistConsentCovers(null, 1), false);
	assert.equal(coachAssistConsentCovers(0, 1), false);
	assert.equal(coachAssistConsentCovers(COACH_ASSIST_CONSENT_VERSION + 1, 1), false);
	assert.equal(coachAssistConsentCovers('1', 1), false);
});

test('every athlete lane is named by a bullet in the English copy', () => {
	for (const [path, entry] of Object.entries(COACH_ASSIST_REGISTRY)) {
		if ('sentFrom' in entry) {
			assert.ok(entry.bullet in en, `${path} names a bullet that is not in en.ts`);
			assert.ok(entry.sentFrom <= COACH_ASSIST_CONSENT_VERSION, `${path} is sent from a version that does not exist`);
		}
	}
});

test('an unregistered key throws rather than reaching the model', () => {
	assert.throws(() => coachAssistAllows('recent_runs.avg_bpm', 1));
	assert.throws(() => withholdUnconsented({ recent_runs: [{ metadata: {} }] }, 1));
	assert.throws(() => withholdUnconsented({ date_of_birth: '1990-01-01' }, 1));
});

test('nothing an athlete has not consented to survives', () => {
	const out = withholdUnconsented(
		{ mode: 'reply', thread: [{ from: 'athlete', text: 'sore calf', sent_at: 'x' }], plan: null },
		0,
	);
	assert.deepEqual(out, { mode: 'reply', thread: [{}], plan: null });
});

test('input: a uuid athlete, a known mode, a trimmed capped request', () => {
	assert.equal(parseCoachAssistInput({ ...VALID, athlete_id: 'nope' }), null);
	assert.equal(parseCoachAssistInput({ ...VALID, mode: 'chat' }), null);
	const parsed = parseCoachAssistInput({ ...VALID, request: `  ${'x'.repeat(600)}  ` });
	assert.equal(parsed?.request?.length, 500);
	assert.equal(parseCoachAssistInput({ ...VALID, locale: 'xx' })?.locale, null);
});

test('the client date is kept within a day of the server, else the server wins', () => {
	assert.equal(coachAssistToday('2026-11-10', NOW), '2026-11-10');
	assert.equal(coachAssistToday('2026-11-11', NOW), '2026-11-11');
	assert.equal(coachAssistToday('2026-12-25', NOW), '2026-11-10');
	assert.equal(coachAssistToday(null, NOW), '2026-11-10');
});

interface StubOpts {
	profile?: unknown;
	link?: unknown;
	isPro?: boolean;
	limited?: boolean;
	readError?: boolean;
	blocked?: boolean;
}

function stub(opts: StubOpts = {}) {
	const rpcs: string[] = [];
	const reads: string[] = [];
	const filters: string[] = [];
	const factory = () =>
		({
			auth: { getUser: async () => ({ data: { user: { id: COACH } }, error: null }) },
			from: (table: string) => {
				reads.push(table);
				const rows: Record<string, unknown[]> = {
					direct_messages: [
						{ sender_id: ATHLETE, body: 'calf is sore', created_at: '2026-11-09T10:00:00Z' },
						{ sender_id: COACH, body: 'how was the tempo?', created_at: '2026-11-08T10:00:00Z' },
					],
					training_plans: [
						{ id: 'p1', name: 'Spring half', goal_event: 'half', goal_distance_m: 21097, goal_time_seconds: 6000, start_date: '2026-10-01', end_date: '2027-01-01' },
					],
					plan_weeks: [{ id: 'w1' }],
					plan_workouts: [{ scheduled_date: '2026-11-11', kind: 'easy', target_distance_m: 8000, target_duration_seconds: null, target_pace_sec_per_km: null, completed_at: null, skipped_at: null }],
					runs: [{ started_at: '2026-11-09T07:00:00Z', distance_m: 10000, duration_s: 3000, activity_type: 'run' }],
				};
				const chain: Record<string, unknown> = {};
				for (const k of ['select', 'eq', 'in', 'is', 'neq', 'gte', 'lte', 'order', 'limit']) {
					chain[k] = (...args: unknown[]) => {
						filters.push(`${table}.${k}:${args.map(String).join(',')}`);
						return chain;
					};
				}
				chain.maybeSingle = async () => ({
					data:
						opts.link === undefined
							? { ai_assist_consent_version: 1, accepted_at: '2026-10-01T00:00:00Z' }
							: opts.link,
					error: null,
				});
				chain.then = (resolve: (v: unknown) => unknown) =>
					resolve(
						opts.readError && table === 'runs'
							? { data: null, error: { code: 'XX000', message: 'boom' } }
							: { data: rows[table] ?? [], error: null },
					);
				return chain;
			},
			rpc: (name: string) => {
				rpcs.push(name);
				if (name === 'get_my_profile') {
					return {
						maybeSingle: async () => ({
							data:
								opts.profile === undefined
									? { ai_disclosure_version: 7, coach_consent_at: '2026-01-01T00:00:00Z' }
									: opts.profile,
							error: null,
						}),
					};
				}
				if (name === 'is_blocked_either_way') return Promise.resolve({ data: opts.blocked === true, error: null });
				if (name === 'is_pro') return Promise.resolve({ data: opts.isPro !== false, error: null });
				if (name === 'spend_rate_limit_slot') {
					return Promise.resolve({
						data: [{ allowed: opts.limited !== true, spend_id: 'ticket' }],
						error: null,
					});
				}
				return Promise.resolve({ data: true, error: null });
			},
		}) as never;
	return { factory, rpcs, reads, filters };
}

function model(text: string, stop = 'end_turn') {
	const sent: unknown[] = [];
	const client: CoachAssistModelClient = {
		messages: {
			create: async (body) => {
				sent.push(body);
				return { content: [{ type: 'text', text }], stop_reason: stop } as never;
			},
		},
	};
	return { client, sent };
}

function config(s: ReturnType<typeof stub>, m = model('Easy week, rest the calf.')): CoachAssistConfig {
	return {
		enabled: true,
		anthropicApiKey: 'sk-ant-test-FAKE',
		publicSupabaseUrl: 'http://127.0.0.1:24321',
		publicSupabaseAnonKey: 'anon',
		bypassPaywallEnabled: false,
		createClient: s.factory,
		createAnthropic: () => m.client,
		now: () => NOW,
	};
}

const AUTH = 'Bearer token';

test('the deploy flag off answers 503 and reads nothing', async () => {
	const s = stub();
	const res = await handleCoachAssist(AUTH, VALID, { ...config(s), enabled: false });
	assert.equal(res.status, 503);
	assert.deepEqual(s.reads, []);
	assert.deepEqual(s.rpcs, []);
});

test('the coach without the v7 disclosure is refused before any athlete read', async () => {
	const s = stub({ profile: { ai_disclosure_version: 6, coach_consent_at: '2026-01-01T00:00:00Z' } });
	const res = await handleCoachAssist(AUTH, VALID, config(s));
	assert.equal(res.status, 403);
	assert.equal(JSON.parse(res.body).required_version, 7);
	assert.deepEqual(s.reads, []);
});

test('no active link, or no athlete consent on it, is refused before any athlete read', async () => {
	const noLink = stub({ link: null });
	assert.equal((await handleCoachAssist(AUTH, VALID, config(noLink))).status, 403);
	assert.deepEqual(noLink.reads, ['coach_athletes']);

	const noConsent = stub({ link: { ai_assist_consent_version: null } });
	const res = await handleCoachAssist(AUTH, VALID, config(noConsent));
	assert.equal(res.status, 403);
	assert.equal(JSON.parse(res.body).code, ATHLETE_CONSENT_REQUIRED);
	assert.deepEqual(noConsent.reads, ['coach_athletes']);
});

test('a block either way refuses before any athlete read, though the link stays active', async () => {
	const s = stub({ blocked: true });
	const res = await handleCoachAssist(AUTH, VALID, config(s));
	assert.equal(res.status, 403);
	assert.deepEqual(s.reads, ['coach_athletes']);
});

test('the thread leaves out shared AI answers and messages from before the link', async () => {
	const s = stub();
	await handleCoachAssist(AUTH, VALID, config(s));
	assert.ok(s.filters.includes('direct_messages.neq:kind,coach_share'));
	assert.ok(s.filters.includes('direct_messages.gte:created_at,2026-10-01T00:00:00Z'));
});

test('a free coach is offered the upgrade and nothing is sent', async () => {
	const s = stub({ isPro: false });
	const m = model('x');
	const res = await handleCoachAssist(AUTH, VALID, config(s, m));
	assert.equal(res.status, 403);
	assert.equal(JSON.parse(res.body).upgrade, true);
	assert.equal(m.sent.length, 0);
});

test('a spent rate limit answers 429', async () => {
	const s = stub({ limited: true });
	assert.equal((await handleCoachAssist(AUTH, VALID, config(s))).status, 429);
});

test('a failed read refunds the slot and sends nothing', async () => {
	const s = stub({ readError: true });
	const m = model('x');
	const res = await handleCoachAssist(AUTH, VALID, config(s, m));
	assert.equal(res.status, 503);
	assert.ok(s.rpcs.includes('refund_rate_limit_slot'));
	assert.equal(m.sent.length, 0);
});

test('with every gate open the draft comes back, from registered fields only', async () => {
	const s = stub();
	const m = model('  Easy week, rest the calf.  ');
	const res = await handleCoachAssist(AUTH, { ...VALID, request: 'be kind' }, config(s, m));
	assert.equal(res.status, 200);
	assert.equal(JSON.parse(res.body).draft, 'Easy week, rest the calf.');
	const prompt = JSON.stringify(m.sent[0]);
	assert.match(prompt, /calf is sore/);
	assert.match(prompt, /Spring half/);
	assert.doesNotMatch(prompt, /"id"/);
});

test('a refusal or an empty draft refunds the slot', async () => {
	for (const m of [model('', 'end_turn'), model('x', 'refusal')]) {
		const s = stub();
		const res = await handleCoachAssist(AUTH, VALID, config(s, m));
		assert.equal(res.status, 502);
		assert.ok(s.rpcs.includes('refund_rate_limit_slot'));
	}
});

test('the context the builder assembles passes its own registry', async () => {
	const s = stub();
	const ctx = await buildCoachAssistContext(s.factory() as never, {
		coachId: COACH,
		athleteId: ATHLETE,
		mode: 'plan_tweak',
		request: null,
		today: '2026-11-10',
		consentVersion: 1,
		linkedSince: null,
	});
	assert.deepEqual(Object.keys(ctx).sort(), [
		'coach_request',
		'mode',
		'plan',
		'recent_runs',
		'thread',
		'today',
		'upcoming_workouts',
	]);
	assert.deepEqual((ctx.thread as { from: string }[]).map((t) => t.from), ['coach', 'athlete']);
});

test('the client reads each refusal as the state the panel shows', async () => {
	const { coachAssistErrorKind } = await import('./client_kind');
	assert.equal(coachAssistErrorKind(403, { code: 'ai_disclosure_required' }), 'coach_consent');
	assert.equal(coachAssistErrorKind(403, { code: ATHLETE_CONSENT_REQUIRED }), 'athlete_consent');
	assert.equal(coachAssistErrorKind(403, { upgrade: true }), 'upgrade');
	assert.equal(coachAssistErrorKind(403, null), 'not_your_athlete');
	assert.equal(coachAssistErrorKind(429, null), 'rate_limited');
	assert.equal(coachAssistErrorKind(503, null), 'unavailable');
	assert.equal(coachAssistErrorKind(401, null), 'not_authenticated');
});
