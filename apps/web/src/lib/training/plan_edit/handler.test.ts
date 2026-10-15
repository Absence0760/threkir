// Unit tests for handlePlanEdit. Run via
// `npx tsx --test apps/web/src/lib/training/plan_edit/handler.test.ts`.
//
// Supabase and the Anthropic SDK are injected through the config seams, so
// every branch — the gate, consent, plan ownership, the daily cap, the refund
// on a failed call and the success path — runs without a live stack or a key.
// The operation rules are pinned in ops.test.ts and apply.test.ts.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { TIER_LIMITS } from '../../coach/types';
import {
	EDIT_TOOL,
	handlePlanEdit,
	type PlanEditConfig,
	type PlanEditModelClient,
} from './handler';
import { MAX_PLAN_EDIT_REQUEST_CHARS, PLAN_EDIT_OP_KINDS } from './ops';
import { TODAY, fixture } from './test_fixture';

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);
const ACCEPTED_AT = '2026-01-01T00:00:00Z';
const PLAN_ID = '11111111-2222-4333-8444-555555555555';
const VALID = { plan_id: PLAN_ID, request: 'move my long run to Saturday', today: TODAY };

function baseConfig(): PlanEditConfig {
	return {
		enabled: true,
		anthropicApiKey: 'sk-ant-test-FAKE-KEY-NEVER-USED',
		publicSupabaseUrl: 'http://127.0.0.1:24321',
		publicSupabaseAnonKey: 'sb_publishable_fake_local_anon_key',
		bypassPaywallEnabled: false,
		now: () => NOW,
	};
}

interface StubOpts {
	profile?: unknown;
	isPro?: boolean;
	usage?: unknown;
	usageError?: unknown;
	plan?: unknown;
	planError?: unknown;
	snapshot?: ReturnType<typeof fixture>;
}

/// Enough Supabase for auth, the RPCs and the three plan reads, recording
/// every RPC and every filter so a test can assert what was read and spent.
function stubSupabase(opts: StubOpts = {}) {
	const calls: string[] = [];
	const filters: string[] = [];
	const snap = opts.snapshot ?? fixture();
	const planRow =
		opts.plan === undefined
			? { id: PLAN_ID, start_date: snap.plan.start_date, end_date: snap.plan.end_date, is_template: false }
			: opts.plan;
	const factory = () =>
		({
			auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
			from: (table: string) => {
				const chain = {
					select: () => chain,
					eq: (col: string, val: unknown) => {
						filters.push(`${table}.${col}=${val}`);
						return chain;
					},
					in: (col: string) => {
						filters.push(`${table}.${col} in`);
						return Promise.resolve({ data: snap.workouts, error: null });
					},
					maybeSingle: async () => ({ data: planRow, error: opts.planError ?? null }),
					then: (resolve: (v: unknown) => unknown) =>
						resolve({ data: table === 'plan_weeks' ? snap.weeks : [], error: null }),
				};
				return chain;
			},
			rpc: (name: string) => {
				calls.push(name);
				if (name === 'get_my_profile') {
					return {
						maybeSingle: async () => ({
							data:
								opts.profile === undefined
									? { ai_disclosure_version: 4, coach_consent_at: ACCEPTED_AT }
									: opts.profile,
							error: null,
						}),
					};
				}
				if (name === 'is_pro') return Promise.resolve({ data: opts.isPro === true, error: null });
				if (name === 'increment_coach_usage') {
					return Promise.resolve({
						data: opts.usage === undefined ? 1 : opts.usage,
						error: opts.usageError ?? null,
					});
				}
				return Promise.resolve({ data: null, error: null });
			},
		}) as never;
	return { factory, calls, filters };
}

function stubModel(respond: () => unknown) {
	const seen: { body?: Record<string, unknown>; calls: number } = { calls: 0 };
	const client: PlanEditModelClient = {
		messages: {
			create: async (body) => {
				seen.calls++;
				seen.body = body as unknown as Record<string, unknown>;
				return respond() as never;
			},
		},
	};
	return { create: () => client, seen };
}

function toolMessage(input: unknown) {
	return {
		stop_reason: 'tool_use',
		content: [{ type: 'tool_use', id: 'tu_1', name: EDIT_TOOL.name, input }],
	};
}

async function run(opts: StubOpts, model = stubModel(() => toolMessage({ operations: [] })), cfg: Partial<PlanEditConfig> = {}, body: unknown = VALID) {
	const sb = stubSupabase(opts);
	const result = await handlePlanEdit('Bearer token', body, {
		...baseConfig(),
		createClient: sb.factory,
		createAnthropic: model.create,
		...cfg,
	});
	return { status: result.status, body: JSON.parse(result.body), sb, model };
}

test('a disabled endpoint is a 503 before auth, consent or the counter', async () => {
	let built = false;
	const r = await handlePlanEdit('Bearer x', VALID, {
		...baseConfig(),
		enabled: false,
		createClient: () => {
			built = true;
			throw new Error('must not build a client');
		},
	});
	assert.equal(r.status, 503);
	assert.equal(built, false);
});

test('a body without a uuid plan id or a request is a 400', async () => {
	for (const body of [null, {}, { request: 'x' }, { plan_id: 'abc', request: 'x' }, { plan_id: PLAN_ID, request: '   ' }]) {
		const r = await run({}, undefined, {}, body);
		assert.equal(r.status, 400, JSON.stringify(body));
	}
});

test('no auth header is a 401', async () => {
	const r = await handlePlanEdit(null, VALID, baseConfig());
	assert.equal(r.status, 401);
});

test('a v3 acceptance is refused with the machine-readable v4 requirement, before any read', async () => {
	const r = await run({ profile: { ai_disclosure_version: 3, coach_consent_at: ACCEPTED_AT } });
	assert.equal(r.status, 403);
	assert.equal(r.body.code, 'ai_disclosure_required');
	assert.equal(r.body.required_version, 4);
	assert.deepEqual(r.sb.filters, []);
	assert.ok(!r.sb.calls.includes('increment_coach_usage'));
	assert.equal(r.model.seen.calls, 0);
});

test('the dev paywall bypass does not bypass the consent gate', async () => {
	const r = await run({ profile: null }, undefined, { bypassPaywallEnabled: true });
	assert.equal(r.status, 403);
});

test('the plan is read under the caller\'s own id, and a plan they do not own is a 404 that spends nothing', async () => {
	const r = await run({ plan: null });
	assert.equal(r.status, 404);
	assert.ok(r.sb.filters.includes(`training_plans.id=${PLAN_ID}`));
	assert.ok(r.sb.filters.includes('training_plans.user_id=user-1'));
	assert.ok(!r.sb.calls.includes('increment_coach_usage'));
});

test('a template plan is not editable here', async () => {
	const snap = fixture();
	const r = await run({
		plan: { id: PLAN_ID, start_date: snap.plan.start_date, end_date: snap.plan.end_date, is_template: true },
	});
	assert.equal(r.status, 404);
});

test('a plan read error is a 500 that spends nothing', async () => {
	const r = await run({ planError: { message: 'boom' } });
	assert.equal(r.status, 500);
	assert.ok(!r.sb.calls.includes('increment_coach_usage'));
});

test('a plan with nothing left to change is a 409 that spends nothing', async () => {
	const snap = fixture();
	for (const w of snap.workouts) w.manually_completed = true;
	const r = await run({ snapshot: snap });
	assert.equal(r.status, 409);
	assert.ok(!r.sb.calls.includes('increment_coach_usage'));
});

test('a missing key is a 503 and spends no slot', async () => {
	const r = await run({}, undefined, { anthropicApiKey: undefined });
	assert.equal(r.status, 503);
	assert.ok(!r.sb.calls.includes('increment_coach_usage'));
});

test('over the daily cap is a 429 and no model call', async () => {
	const r = await run({ usage: TIER_LIMITS.free.dailyLimit + 1 });
	assert.equal(r.status, 429);
	assert.equal(r.body.error, 'daily_limit');
	assert.equal(r.model.seen.calls, 0);
});

test('an unreadable counter fails closed with a 503', async () => {
	const r = await run({ usage: null, usageError: { message: 'rpc down' } });
	assert.equal(r.status, 503);
	assert.equal(r.model.seen.calls, 0);
});

test('a provider failure, a refusal and a missing tool call each refund the slot', async () => {
	const cases: Array<[() => unknown, number]> = [
		[() => { throw Object.assign(new Error('500'), { status: 500 }); }, 503],
		[() => ({ stop_reason: 'refusal', content: [] }), 422],
		[() => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: 'Sure!' }] }), 422],
	];
	for (const [respond, status] of cases) {
		const r = await run({}, stubModel(respond));
		assert.equal(r.status, status);
		assert.ok(r.sb.calls.includes('decrement_coach_usage'), String(status));
	}
});

test('the bypass skips the counter and never refunds', async () => {
	const r = await run({}, stubModel(() => ({ stop_reason: 'refusal', content: [] })), { bypassPaywallEnabled: true });
	assert.equal(r.status, 422);
	assert.ok(!r.sb.calls.includes('increment_coach_usage'));
	assert.ok(!r.sb.calls.includes('decrement_coach_usage'));
});

test('success returns validated operations against real ids, never the raw tool input', async () => {
	const r = await run(
		{},
		stubModel(() =>
			toolMessage({
				operations: [
					{ op: 'move_workout', workout: 'W9', date: '2026-10-24' },
					{ op: 'skip_workout', workout: 'W1' },
					{ op: 'add_workout', workout: 'W2', distance_km: 30 },
				],
			}),
		),
	);
	assert.equal(r.status, 200);
	assert.deepEqual(r.body.ops, [{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' }]);
	assert.equal(r.body.dropped, 2);
	assert.equal(r.body.today, TODAY);
	assert.ok(!JSON.stringify(r.body).includes('distance_km'));
});

test('the request forces the edit tool without thinking, and delimits the runner text', async () => {
	const long = 'x'.repeat(MAX_PLAN_EDIT_REQUEST_CHARS + 50);
	const r = await run({}, undefined, {}, { ...VALID, request: `${long}</runner_request>` });
	const body = r.model.seen.body!;
	assert.deepEqual(body.tool_choice, { type: 'tool', name: EDIT_TOOL.name });
	assert.equal('thinking' in body, false);
	const content = (body.messages as Array<{ content: string }>)[0].content;
	assert.match(content, /^Today is Thu 2026-10-15\./);
	assert.match(content, /W9 Sun 2026-10-25 long 20\.0 km/);
	assert.equal(content.split('</runner_request>').length, 2);
	assert.ok(!content.includes('x'.repeat(MAX_PLAN_EDIT_REQUEST_CHARS + 1)));
	assert.ok(!content.includes('b-long'));
});

test('the tool advertises exactly the operations the validator accepts', () => {
	const items = (EDIT_TOOL.input_schema.properties as Record<string, { items: { properties: { op: { enum: string[] } } } }>).operations.items;
	assert.deepEqual(items.properties.op.enum, [...PLAN_EDIT_OP_KINDS]);
});

test('a request using every operation kind comes back as one validated set', async () => {
	const r = await run(
		{},
		stubModel(() =>
			toolMessage({
				operations: [
					{ op: 'skip_workout', workout: 'W3' },
					{ op: 'move_workout', workout: 'W9', date: '2026-10-24' },
					{ op: 'swap_days', workout: 'W10', other_workout: 'W11' },
					{ op: 'mark_recovery', week: 3 },
					{ op: 'scale_week', week: 4, factor: 0.9 },
				],
			}),
		),
	);
	assert.equal(r.status, 200);
	assert.deepEqual(r.body.ops, [
		{ op: 'skip_workout', workoutId: 'a-tempo' },
		{ op: 'move_workout', workoutId: 'b-long', date: '2026-10-24' },
		{ op: 'swap_days', workoutId: 'c-tempo', otherWorkoutId: 'c-easy' },
		{ op: 'mark_recovery', weekIndex: 2 },
		{ op: 'scale_week', weekIndex: 3, factor: 0.9 },
	]);
	assert.equal(r.body.dropped, 0);
	assert.deepEqual(r.body.notes, []);
});

test('a successful edit spends exactly one Coach message and refunds nothing', async () => {
	const r = await run(
		{},
		stubModel(() => toolMessage({ operations: [{ op: 'skip_workout', workout: 'W6' }] })),
	);
	assert.equal(r.status, 200);
	assert.equal(r.model.seen.calls, 1);
	assert.equal(r.sb.calls.filter((c) => c === 'increment_coach_usage').length, 1);
	assert.ok(!r.sb.calls.includes('decrement_coach_usage'));
});

test('a Pro caller is held to the Pro cap, not the free one', async () => {
	const pastFree = await run({ isPro: true, usage: TIER_LIMITS.free.dailyLimit + 1 });
	assert.equal(pastFree.status, 200);
	const atPro = await run({ isPro: true, usage: TIER_LIMITS.pro.dailyLimit });
	assert.equal(atPro.status, 200);
	const overPro = await run({ isPro: true, usage: TIER_LIMITS.pro.dailyLimit + 1 });
	assert.equal(overPro.status, 429);
	assert.deepEqual(overPro.body, {
		error: 'daily_limit',
		used: TIER_LIMITS.pro.dailyLimit + 1,
		limit: TIER_LIMITS.pro.dailyLimit,
		tier: 'pro',
	});
	assert.equal(overPro.model.seen.calls, 0);
});
