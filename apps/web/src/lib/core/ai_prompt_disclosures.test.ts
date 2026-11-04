// Every field a single-shot Anthropic prompt sends has a disclosure line, and
// every disclosure line names a field the prompt still sends (decisions § 2338).
// Run with `npx tsx --test src/lib/core/ai_prompt_disclosures.test.ts` from apps/web.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

import { AI_PROMPT_DISCLOSURES, type AiPromptEntry, type AiPromptId } from './ai_prompt_disclosures';
import { en } from '../i18n/locales/en';
import { platePhotoUserContent } from '../nutrition/plate_photo/handler';
import { describeRoute } from '../routes/route_description';
import { routeDescribeUserMessage } from '../routes/route_describe/handler';
import { routeRequestUserMessage } from '../routes/route_request/handler';
import { planEditUserTurn } from '../training/plan_edit/handler';
import { buildPlanEditContext } from '../training/plan_edit/ops';
import { fixture as planFixture, TODAY } from '../training/plan_edit/test_fixture';
import { planRequestUserTurn } from '../training/plan_request/handler';
import { seasonRequestUserTurn } from '../training/season_request/handler';

const LIB = resolve(import.meta.dirname ?? '.', '..');
const WEB = resolve(LIB, '../..');
const REPO = resolve(WEB, '../..');

/// Wrap `root` so every leaf the builder reads is recorded, with the value it
/// read. Array elements share one `[]` path; a Map, Set or Date is a leaf.
function recording<T extends object>(root: T, seen: Map<string, unknown>, path = ''): T {
	return new Proxy(root, {
		get(target, key, receiver) {
			const value = Reflect.get(target, key, receiver);
			if (typeof key === 'symbol') return value;
			const isArray = Array.isArray(target);
			if (isArray && !/^\d+$/.test(key)) return value;
			const at = isArray ? `${path}[]` : path ? `${path}.${key}` : key;
			if (
				value !== null &&
				typeof value === 'object' &&
				!(value instanceof Map) &&
				!(value instanceof Set) &&
				!(value instanceof Date)
			) {
				return recording(value, seen, at);
			}
			if (!seen.has(at)) seen.set(at, value);
			return value;
		},
	});
}

/// Run `build` over `input` and return the paths it read and what it produced.
function probe<I extends object>(
	build: (input: I) => unknown,
	input: I,
): { read: Map<string, unknown>; output: string } {
	const read = new Map<string, unknown>();
	const out = build(recording(input, read));
	return { read, output: typeof out === 'string' ? out : JSON.stringify(out) };
}

/// One realistic input per prompt, every optional field present.
const PROBES: { [P in AiPromptId]: () => { read: Map<string, unknown>; output: string } } = {
	'route-describe': () =>
		probe(routeDescribeUserMessage, {
			parts: describeRoute({
				name: 'unused',
				distanceM: 12_000,
				elevationM: 480,
				surface: 'trail',
				start: { lat: 51.5, lng: -0.12 },
				end: { lat: 51.5, lng: -0.12 },
			}),
			name: 'Summit Trail',
			unit: 'km',
			locale: 'de',
		}),
	'route-request': () =>
		probe(routeRequestUserMessage, { requestText: 'a quiet 10k loop', locationLabel: 'Hackney' }),
	'plan-request': () =>
		probe(planRequestUserTurn, { requestText: 'sub-2 half in March', today: '2026-11-04' }),
	'season-request': () =>
		probe(seasonRequestUserTurn, { requestText: 'Two Oceans then Comrades', today: '2026-11-04' }),
	'plan-edit': () => {
		const snapshot = planFixture();
		snapshot.workouts[2] = { ...snapshot.workouts[2], skipped_at: '2026-10-14T08:00:00Z' };
		snapshot.workouts[3] = { ...snapshot.workouts[3], target_duration_seconds: 5400 };
		return probe(planEditUserTurn, {
			requestText: 'make this week easier',
			today: TODAY,
			plan: buildPlanEditContext(snapshot, TODAY),
		});
	},
	'plate-photo': () =>
		probe(platePhotoUserContent, {
			image: { mediaType: 'image/jpeg', base64: 'QUJDREVGR0hJSktMTU5PUA==' },
			note: 'half portion of rice',
		}),
};

const ENTRIES = Object.entries(AI_PROMPT_DISCLOSURES) as [AiPromptId, AiPromptEntry][];

/// The paths a builder read that the registry does not name, and the other way.
function drift(entry: AiPromptEntry, read: Map<string, unknown>) {
	const registered = new Set(Object.keys(entry.fields));
	return {
		unregistered: [...read.keys()].filter((p) => !registered.has(p)).sort(),
		stale: [...registered].filter((p) => !read.has(p)).sort(),
	};
}

test('every field each prompt builder reads is registered, and every registered field is read', () => {
	for (const [id, entry] of ENTRIES) {
		const { read } = PROBES[id]();
		const { unregistered, stale } = drift(entry, read);
		assert.deepEqual(
			unregistered,
			[],
			`${id}: ${entry.builder} reads fields with no disclosure line in AI_PROMPT_DISCLOSURES`,
		);
		assert.deepEqual(stale, [], `${id}: AI_PROMPT_DISCLOSURES names fields ${entry.builder} no longer reads`);
	}
});

test('the probe catches a builder that starts reading a new field', () => {
	// The mutation the registry exists to catch: a builder that gains a field.
	const entry = AI_PROMPT_DISCLOSURES['route-request'];
	const { read } = probe(
		(input: { requestText: string; locationLabel: string | null; homeTown: string }) =>
			routeRequestUserMessage(input) + input.homeTown,
		{ requestText: 'a 5k', locationLabel: null, homeTown: 'Leeds' },
	);
	assert.deepEqual(drift(entry, read).unregistered, ['homeTown']);
});

test('a field marked not-sent never appears in the prompt', () => {
	for (const [id, entry] of ENTRIES) {
		const { read, output } = PROBES[id]();
		for (const [path, d] of Object.entries(entry.fields)) {
			if (!('notSent' in d)) continue;
			const value = read.get(path);
			if (typeof value !== 'string' || value.length < 3 || path.endsWith('today')) continue;
			assert.ok(!output.includes(value), `${id}: ${path} is marked not-sent but its value is in the prompt`);
		}
	}
});

test('every registered handler sends the user turn its builder makes, in its one model call', () => {
	for (const [id, entry] of ENTRIES) {
		const src = readFileSync(join(LIB, entry.handler), 'utf8');
		const calls = src.split('messages.create(').length - 1;
		assert.equal(calls, 1, `${id}: ${entry.handler} should make exactly one model call`);
		const call = src.slice(src.indexOf('messages.create('));
		const body = call.slice(0, call.indexOf('{ timeout:'));
		assert.match(body, new RegExp(`content: ${entry.builder}\\(`), `${id}: the model call does not send ${entry.builder}(...)`);
		assert.match(src, new RegExp(`export function ${entry.builder}\\(`), `${id}: ${entry.builder} is not exported`);
	}
});

/// Files under these trees that call the model and are NOT in the registry,
/// with what covers them instead.
const COVERED_ELSEWHERE: Readonly<Record<string, string>> = {
	'src/lib/coach/providers.ts': 'the AI Coach: COACH_CONTEXT_REGISTRY in coach/context.ts, per field',
};

function sourceFiles(dir: string): string[] {
	return readdirSync(dir).flatMap((name) => {
		const path = join(dir, name);
		if (name === 'node_modules' || name.startsWith('.')) return [];
		if (statSync(path).isDirectory()) return sourceFiles(path);
		return /\.(ts|js|mjs)$/.test(name) && !/\.test\.(ts|mjs)$/.test(name) ? [path] : [];
	});
}

test('every Anthropic call site in the web app and its Lambda is registered or covered elsewhere', () => {
	const registered = new Set(ENTRIES.map(([, e]) => `src/lib/${e.handler}`));
	const callers = [...sourceFiles(join(WEB, 'src')), ...sourceFiles(join(WEB, 'lambda'))]
		.filter((f) => /messages\.(create|stream)\(/.test(readFileSync(f, 'utf8')))
		.map((f) => relative(WEB, f));
	const unknown = callers.filter((f) => !registered.has(f) && !(f in COVERED_ELSEWHERE));
	assert.deepEqual(unknown, [], 'a new model call site needs an AI_PROMPT_DISCLOSURES entry');
	for (const f of [...registered, ...Object.keys(COVERED_ELSEWHERE)]) {
		assert.ok(callers.includes(f), `${f} is registered but no longer calls the model`);
	}
});

test("every prompt's consent bullet is a real catalogue key", () => {
	for (const [id, entry] of ENTRIES) {
		assert.equal(typeof en[entry.bullet], 'string', `${id}: ${entry.bullet} is not in en.ts`);
	}
});

/// The Anthropic row of the sub-processor record, cut into one section per
/// prompt at its `**<id>**` label.
function anthropicSections(): Map<string, string> {
	const doc = readFileSync(join(REPO, 'docs/compliance/sub-processors.md'), 'utf8');
	const row = doc.split('\n').find((l) => l.startsWith('| **Anthropic**'));
	assert.ok(row, 'sub-processors.md has no Anthropic row');
	const ids = ENTRIES.map(([id]) => id);
	const at = ids
		.map((id) => ({ id, i: row.indexOf(`**${id}**`) }))
		.filter((x) => x.i >= 0)
		.sort((a, b) => a.i - b.i);
	const sections = new Map<string, string>();
	at.forEach(({ id, i }, n) => {
		const end = n + 1 < at.length ? at[n + 1].i : row.indexOf(' | ', i);
		sections.set(id, row.slice(i, end));
	});
	return sections;
}

test('every sent field has its disclosure line in the Anthropic row of sub-processors.md', () => {
	const sections = anthropicSections();
	for (const [id, entry] of ENTRIES) {
		const section = sections.get(id);
		assert.ok(section, `sub-processors.md's Anthropic row has no **${id}** section`);
		for (const [path, d] of Object.entries(entry.fields)) {
			if (!('sent' in d)) continue;
			assert.ok(section.includes(d.sent), `${id}: "${d.sent}" (${path}) is not in its sub-processors.md section`);
		}
	}
});
