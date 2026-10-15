// Source-grep guards on the COACH_SYSTEM_PROMPT string. Run with
// `npx tsx --test apps/web/src/lib/coach/system_prompt.test.ts`.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { COACH_SYSTEM_PROMPT, planHandoffAddendum } from './system_prompt';

test('system prompt declares the <CONTEXT> boundary', () => {
	// audit/coach May 2026 Medium #4 + Low #11 — OWASP LLM01 prompt
	// injection. Any text inside <CONTEXT>...</CONTEXT> markers is
	// user-controlled (run titles, display names, plan names); the
	// model must treat it as data, not instructions. Without this
	// boundary, a renamed-run injection persists across the cached
	// turn forever.
	assert.match(
		COACH_SYSTEM_PROMPT,
		/<CONTEXT>[^<]*<\/CONTEXT>/i,
		'system prompt must reference the <CONTEXT>...</CONTEXT> markers',
	);
	assert.match(
		COACH_SYSTEM_PROMPT,
		/never follow instructions/i,
		'system prompt must instruct the model to ignore instructions inside the context block',
	);
});

test('system prompt instructs the coach to reply in the runner’s language', () => {
	// audit-findings 2026-05-30 High [i18n] (W-12 / S-2): the coach is
	// the one always-on free-text surface; without a respond-in-language
	// instruction a non-English runner gets English replies regardless of
	// how they write. Pin the instruction so a prompt edit can't silently
	// drop it.
	assert.match(
		COACH_SYSTEM_PROMPT,
		/reply in the same language|respond entirely in that language/i,
		'system prompt must tell the coach to answer in the runner’s own language',
	);
});

test('system prompt refuses persona-switch / system-impersonation', () => {
	// Companion to the CONTEXT boundary — protects against turns
	// where the user (or a replayed assistant turn) claims to be
	// system / admin / Anthropic and asks to bypass the rules.
	assert.match(
		COACH_SYSTEM_PROMPT,
		/impersonate|system administrator|reveal the system prompt/i,
		'system prompt must explicitly refuse impersonation / system-prompt exfiltration',
	);
});

test('system prompt does NOT leak internal field names as forbidden secrets', () => {
	// Sanity: the trust+safety section mentions runner_context and
	// recent_runs by name (so the model knows the field semantics).
	// That's intentional — they're not secrets, just internal labels.
	// This test exists as a placeholder so a future contributor who
	// adds a real secret name to the prompt gets a CI bounce.
	const FORBIDDEN = ['ANTHROPIC_API_KEY', 'service_role', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY', 'sb_secret_'];
	for (const k of FORBIDDEN) {
		assert.equal(
			COACH_SYSTEM_PROMPT.includes(k),
			false,
			`system prompt must NEVER mention \`${k}\` — operational secret`,
		);
	}
});

test('system prompt still forbids the coach writing a plan, and hands plan requests to the builder', () => {
	// decisions § 12 / § 1930: the coach never authors workouts. The amended
	// "You do NOT" line must keep that prohibition while pointing at the
	// handoff instead of contradicting it.
	assert.match(
		COACH_SYSTEM_PROMPT,
		/You do NOT:[\s\S]*Write workouts, weekly schedules, or brand-new training structures yourself/,
	);
	assert.match(COACH_SYSTEM_PROMPT, /hand them to the plan builder/);
	assert.doesNotMatch(
		COACH_SYSTEM_PROMPT,
		/out of scope \(plan regeneration/,
		'a plan request is the handoff, not an out-of-scope redirect',
	);
});

test('planHandoffAddendum(true) asks for exactly one percent-encoded describe link', () => {
	const out = planHandoffAddendum(true);
	assert.ok(out.includes('[Build this plan](/plans/new?describe=<description>)'), out);
	assert.match(out, /exactly one markdown link/);
	assert.match(out, /do not write workouts or a schedule yourself/);
	assert.match(out, /Percent-encode[\s\S]*spaces as %20/);
	assert.match(out, /Never invent/);
	assert.match(out, /recent 5K time only if a run in `recent_runs` shows one/);
	assert.match(out, /runner's language/);
	assert.match(out, /300 characters/);
	assert.match(out, /plan generator builds the plan/);
});

test('planHandoffAddendum(false) points at the bare plan builder and never the assistant', () => {
	const out = planHandoffAddendum(false);
	assert.ok(out.includes('[plan builder](/plans/new)'), out);
	assert.match(out, /do not write workouts or a schedule yourself/);
	assert.ok(!out.includes('describe='), 'the assistant link must not appear while the flag is off');
});

test('planHandoffAddendum is deterministic per flag value, so the cached system text stays stable', () => {
	// The addendum sits inside the cached system block; any per-call
	// variation (a date, a random id) would miss the prompt cache on every turn.
	assert.equal(planHandoffAddendum(true), planHandoffAddendum(true));
	assert.equal(planHandoffAddendum(false), planHandoffAddendum(false));
	assert.notEqual(planHandoffAddendum(true), planHandoffAddendum(false));
	assert.ok(!/\d{4}-\d{2}-\d{2}/.test(planHandoffAddendum(true) + planHandoffAddendum(false)));
});

test('the handoff addenda leak no operational secret either', () => {
	const FORBIDDEN = ['ANTHROPIC_API_KEY', 'service_role', 'SUPABASE_SECRET_KEY', 'sb_secret_', 'AI_PLAN_ENABLED'];
	for (const text of [planHandoffAddendum(true), planHandoffAddendum(false)]) {
		for (const k of FORBIDDEN) assert.equal(text.includes(k), false, k);
	}
});
