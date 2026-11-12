import { test } from 'node:test';
import assert from 'node:assert/strict';
import type Anthropic from '@anthropic-ai/sdk';

import {
	anthropicCoachRequest,
	anthropicTextTokens,
	COACH_ANTHROPIC_MODEL,
	humaniseUpstreamError,
} from './providers';
import { TIER_LIMITS } from './types';

const LOCAL = 'http://127.0.0.1:11434/v1';
const REMOTE = 'https://openrouter.ai/api/v1';

test('Ollama 404 model-not-found → ollama pull hint', () => {
	const body = JSON.stringify({
		error: {
			message: "model 'llama3.1:8b-instruct-q8_0' not found",
			type: 'not_found_error',
		},
	});
	const out = humaniseUpstreamError(404, body, 'llama3.1:8b-instruct-q8_0', LOCAL);
	assert.match(out, /model "llama3\.1:8b-instruct-q8_0"/);
	assert.match(out, /ollama pull llama3\.1:8b-instruct-q8_0/);
	assert.match(out, /ollama list/);
	// Must NOT leak the raw JSON.
	assert.doesNotMatch(out, /not_found_error/);
	assert.doesNotMatch(out, /\{"error"/);
});

test('Remote 404 model-not-found → catalogue hint, no ollama pull', () => {
	const body = JSON.stringify({
		error: { message: 'The model "claude-impossibru" does not exist' },
	});
	const out = humaniseUpstreamError(404, body, 'claude-impossibru', REMOTE);
	assert.match(out, /provider's model catalogue/);
	assert.doesNotMatch(out, /ollama pull/);
	assert.match(out, /COACH_MODEL/);
});

test('401 → API key guidance', () => {
	const out = humaniseUpstreamError(
		401,
		JSON.stringify({ error: { message: 'Invalid API key' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /401/);
	// The 401 helper deliberately stays provider-neutral — naming the
	// specific env var (e.g. OPENAI_API_KEY) leaks which provider the
	// server is wired against to anyone probing the chat error bar.
	// See commit 55e9e81 ("audit: address /audit/all Lows").
	assert.match(out, /upstream API key configuration/);
	assert.doesNotMatch(out, /OPENAI_API_KEY|ANTHROPIC_API_KEY/);
	assert.match(out, /gpt-4o/);
});

test('429 → rate-limit, surfaces upstream message', () => {
	const out = humaniseUpstreamError(
		429,
		JSON.stringify({ error: { message: 'Slow down: 2 req/min cap' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /429/);
	assert.match(out, /Slow down/);
});

test('403 geo-block → distinct region-unavailable message (not a generic upstream error)', () => {
	const out = humaniseUpstreamError(
		403,
		JSON.stringify({ error: { message: 'Country, region, or territory not supported' } }),
		'claude-opus-4-8',
		REMOTE,
	);
	assert.match(out, /region/i);
	assert.doesNotMatch(out, /^Coach upstream 403:/);
	// Must not leak the configured provider/env.
	assert.doesNotMatch(out, /OPENAI_API_KEY|ANTHROPIC_API_KEY/);
});

test('403 with a non-geo message keeps the upstream envelope', () => {
	const out = humaniseUpstreamError(
		403,
		JSON.stringify({ error: { message: 'permission denied for resource' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /403/);
	assert.match(out, /permission denied/);
});

test('Unrecognised status keeps the upstream-style envelope, capped to 300 chars', () => {
	const longMessage = 'x'.repeat(500);
	const out = humaniseUpstreamError(
		500,
		JSON.stringify({ error: { message: longMessage } }),
		'm',
		LOCAL,
	);
	assert.match(out, /^Coach upstream 500: /);
	// 300-char cap on the trailing message.
	const tail = out.replace(/^Coach upstream 500: /, '');
	assert.equal(tail.length, 300);
});

test('Non-JSON body falls through to the raw text', () => {
	const out = humaniseUpstreamError(503, '<html>bad gateway</html>', 'm', REMOTE);
	assert.match(out, /^Coach upstream 503: /);
	assert.match(out, /bad gateway/);
});

test('404 without "model" in the message falls through to the generic envelope', () => {
	// The model-not-found branch requires BOTH a 404 status AND the
	// upstream message containing the word "model" + a not-found
	// phrase. A 404 from a typoed URL ("Endpoint /v1/widgets does not
	// exist") shouldn't masquerade as a missing model.
	const out = humaniseUpstreamError(
		404,
		JSON.stringify({ error: { message: 'Endpoint /v1/widgets does not exist' } }),
		'gpt-4o',
		REMOTE,
	);
	assert.match(out, /^Coach upstream 404: /);
	assert.doesNotMatch(out, /Coach can't reach model/);
});

// ─────────────── Anthropic request shape ───────────────
//
// Pinned because the coach model is retired on a date (claude-sonnet-4-5
// reached end of life 2026-11-30) and its successor rejects shapes the
// old one accepted: non-default sampling parameters 400, and omitting
// `thinking` runs adaptive thinking whose tokens count against
// max_tokens, which would spend the free tier's 768-token reply cap
// before the reply started.

const CALLER = [
	{ role: 'user' as const, content: 'plan my week' },
	{ role: 'assistant' as const, content: 'Here is a plan.' },
	{ role: 'user' as const, content: 'swap thursday' },
];

test('anthropicCoachRequest — current Sonnet, no extended thinking, no sampling overrides', () => {
	const req = anthropicCoachRequest('SYSTEM', 'CONTEXT', CALLER, TIER_LIMITS.free);
	assert.equal(COACH_ANTHROPIC_MODEL, 'claude-sonnet-5-5');
	assert.equal(req.model, COACH_ANTHROPIC_MODEL);
	assert.deepEqual(req.thinking, { type: 'between_tools' });
	// between_tools is refused above effort `high`.
	assert.ok(
		['low', 'medium', 'high'].includes(String(req.output_config?.effort)),
		`effort must be low/medium/high with between_tools, got ${req.output_config?.effort}`,
	);
	for (const key of ['temperature', 'top_p', 'top_k'] as const) {
		assert.equal(key in req, false, `${key} is rejected by the model when non-default`);
	}
});

test('anthropicCoachRequest — max_tokens is the tier reply cap', () => {
	for (const tier of ['free', 'pro'] as const) {
		const req = anthropicCoachRequest('S', 'C', CALLER, TIER_LIMITS[tier]);
		assert.equal(req.max_tokens, TIER_LIMITS[tier].maxTokens);
	}
});

test('anthropicCoachRequest — context turn is cached and the caller turn is last', () => {
	const req = anthropicCoachRequest('S', 'C', CALLER, TIER_LIMITS.pro);
	assert.equal(req.messages.length, CALLER.length + 2);
	assert.equal(req.messages[0].role, 'user');
	assert.equal(req.messages[1].role, 'assistant');
	const last = req.messages[req.messages.length - 1];
	assert.equal(last.role, 'user');
	assert.deepEqual(last.content, [{ type: 'text', text: 'swap thursday' }]);
});

// ─────────────── Anthropic token stream ───────────────

async function* events(list: unknown[]): AsyncIterable<Anthropic.MessageStreamEvent> {
	for (const e of list) yield e as Anthropic.MessageStreamEvent;
}

async function collect(it: AsyncIterable<string>): Promise<{ out: string[]; err: Error | null }> {
	const out: string[] = [];
	try {
		for await (const t of it) out.push(t);
		return { out, err: null };
	} catch (e) {
		return { out, err: e as Error };
	}
}

test('anthropicTextTokens — yields only text deltas', async () => {
	const { out, err } = await collect(
		anthropicTextTokens(
			events([
				{ type: 'message_start' },
				{ type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: 'x' } },
				{ type: 'content_block_delta', index: 1, delta: { type: 'text_delta', text: 'Easy ' } },
				{ type: 'content_block_delta', index: 1, delta: { type: 'text_delta', text: 'run.' } },
				{ type: 'message_delta', delta: { stop_reason: 'end_turn' } },
				{ type: 'message_stop' },
			]),
		),
	);
	assert.equal(err, null);
	assert.deepEqual(out, ['Easy ', 'run.']);
});

test('anthropicTextTokens — a refusal stop throws instead of ending as a normal turn', async () => {
	// Reason: a decline arrives as stop_reason "refusal" on an otherwise
	// successful stream. Ending quietly would emit `done` with an empty
	// answer and keep the runner's daily slot; throwing sends it down the
	// handler's mid-stream error path, which refunds a zero-token turn.
	const { out, err } = await collect(
		anthropicTextTokens(
			events([
				{ type: 'message_start' },
				{ type: 'message_delta', delta: { stop_reason: 'refusal' } },
				{ type: 'message_stop' },
			]),
		),
	);
	assert.deepEqual(out, []);
	assert.ok(err, 'refusal must throw');
	assert.match(err!.message, /refusal/);
});
