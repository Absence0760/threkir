import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expandInstances } from './recurrence';
import type { Event } from '../types';

// Replays fixtures/recurrence_vectors.json, the occurrence vectors shared with
// the Dart twin (apps/mobile_android/test/recurrence_vectors_test.dart) and
// with the database (apps/backend/supabase/tests/event_occurrence_vectors_test.sql):
// private.is_event_occurrence's membership verdict on every probe, and
// private.event_occurrences' list for every series with a canonical set. The
// photo and order triggers refuse any instant the SQL rejects, so a client
// offering an occurrence the SQL disagrees with is a write the database
// refuses (decisions § 1905, § 1918). This file is also the generator:
//
//   RECURRENCE_VECTORS_WRITE=1 npx tsx --test src/lib/social/recurrence_vectors.test.ts
//
// recomputes `expected` and `probes` for every series from the hand-written
// inputs and rewrites both the fixture and the pgTAP file.

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', '..');
const FIXTURE = join(REPO, 'fixtures', 'recurrence_vectors.json');
const PGTAP = join(REPO, 'apps', 'backend', 'supabase', 'tests', 'event_occurrence_vectors_test.sql');

interface SeriesInput {
	starts_at: string;
	recurrence_freq: Event['recurrence_freq'];
	recurrence_byday: Event['recurrence_byday'];
	recurrence_until: string | null;
	recurrence_count: number | null;
	timezone: string | null;
}
interface Probe {
	at: string;
	occurrence: Record<string, boolean>;
	sql: boolean;
}
interface Series {
	name: string;
	event: SeriesInput;
	from: string;
	to: string;
	expected?: Record<string, string[]>;
	probes?: Probe[];
}
interface Fixture {
	_about: string;
	viewer_zones: string[];
	series: Series[];
}

const DAY = 86_400_000;
const NEAR_MISSES = [-DAY, -30 * 60_000, -1000, 1000, 30 * 60_000, DAY];

function ev(input: SeriesInput): Event {
	return input as unknown as Event;
}

function inZone<T>(zone: string, fn: () => T): T {
	const prev = process.env.TZ;
	process.env.TZ = zone;
	try {
		return fn();
	} finally {
		if (prev === undefined) delete process.env.TZ;
		else process.env.TZ = prev;
	}
}

function isOccurrence(event: Event, at: Date): boolean {
	return expandInstances(event, at, at).some((d) => d.getTime() === at.getTime());
}

// While the § 1918 transition window is open the database also accepts the
// instant the pre-§ 1918 expansion minted for a timezoned series, which is the
// same series read on the UTC clock.
function utcClockOccurrence(e: SeriesInput, at: Date): boolean {
	return isOccurrence(ev({ ...e, timezone: 'UTC' }), at);
}

function canonical(e: SeriesInput): boolean {
	return e.recurrence_freq == null || e.timezone != null;
}

// The SQL's documented rule for a legacy (timezone-null) series: no single
// instant is canonical, so it holds the series to its bounds and to a
// whole-day offset from starts_at (±1 h for a DST shift). byday, biweekly
// parity and recurrence_count are NOT checked. Restated here so the pgTAP
// file pins exactly that, and so the test below can prove every instant any
// viewer zone offers still passes it.
function legacySqlRule(e: SeriesInput, at: Date): boolean {
	const startSec = Math.floor(new Date(e.starts_at).getTime() / 1000) * 1000;
	if (at.getTime() < startSec) return false;
	if (e.recurrence_until && at.getTime() > new Date(e.recurrence_until).getTime()) return false;
	if (e.recurrence_freq === 'monthly') return true;
	const rem = ((at.getTime() - startSec) / 1000) % 86_400;
	return rem <= 3600 || rem >= 82_800;
}

function compute(fx: Fixture, s: Series): Required<Series> {
	const event = ev(s.event);
	const from = new Date(s.from);
	const to = new Date(s.to);
	const expected: Record<string, string[]> = {};
	for (const zone of fx.viewer_zones) {
		expected[zone] = inZone(zone, () => expandInstances(event, from, to, 1000)).map((d) =>
			d.toISOString()
		);
	}

	const candidates = new Set<number>([new Date(s.event.starts_at).getTime()]);
	for (const list of Object.values(expected)) {
		for (const iso of list) {
			const t = new Date(iso).getTime();
			candidates.add(t);
			for (const d of NEAR_MISSES) candidates.add(t + d);
		}
	}
	// What the pre-§ 1918 expansion offered for a timezoned series: the UTC
	// clock. Every client must refuse these now; the database accepts them only
	// while the transition window is open.
	if (s.event.recurrence_freq && s.event.timezone) {
		for (const d of expandInstances(ev({ ...s.event, timezone: 'UTC' }), from, to, 1000)) {
			candidates.add(d.getTime());
		}
	}
	// The first instant each cap removes: what the series would have offered
	// next had the cap not been there.
	if (s.event.recurrence_freq) {
		for (const zone of fx.viewer_zones) {
			inZone(zone, () => {
				if (s.event.recurrence_count != null) {
					const uncapped = ev({ ...s.event, recurrence_count: null });
					const far = new Date(to.getTime() + 400 * 7 * DAY);
					const all = expandInstances(uncapped, new Date(s.event.starts_at), far, s.event.recurrence_count + 1);
					const past = all[s.event.recurrence_count];
					if (past) candidates.add(past.getTime());
				}
				if (s.event.recurrence_until) {
					const until = new Date(s.event.recurrence_until);
					const unbounded = ev({ ...s.event, recurrence_until: null });
					const [past] = expandInstances(unbounded, new Date(until.getTime() + 1), new Date(until.getTime() + 400 * DAY), 1);
					if (past) candidates.add(past.getTime());
				}
			});
		}
	}

	const legacy = s.event.recurrence_freq != null && s.event.timezone == null;
	const probes: Probe[] = [...candidates]
		.sort((a, b) => a - b)
		.map((t) => {
			const at = new Date(t);
			const occurrence: Record<string, boolean> = {};
			for (const zone of fx.viewer_zones) {
				occurrence[zone] = inZone(zone, () => isOccurrence(event, at));
			}
			const sql = legacy ? legacySqlRule(s.event, at) : occurrence[fx.viewer_zones[0]];
			return { at: at.toISOString(), occurrence, sql };
		});
	return { ...s, expected, probes };
}

function sqlLit(v: string | number | null | string[]): string {
	if (v === null) return 'null';
	if (typeof v === 'number') return String(v);
	if (Array.isArray(v)) return `array[${v.map((x) => `'${x}'`).join(',')}]::text[]`;
	return `'${v.replaceAll("'", "''")}'`;
}

function eventId(i: number): string {
	return `eeeeeeee-0000-0000-1145-${String(i + 1).padStart(12, '0')}`;
}

function renderPgtap(fx: Fixture): string {
	const lines: string[] = [];
	const timezoned = fx.series.filter((s) => s.event.recurrence_freq != null && s.event.timezone != null);
	const asserts = 1 + fx.series.length + fx.series.filter((s) => canonical(s.event)).length + 2 * timezoned.length;
	lines.push(
		'-- GENERATED from fixtures/recurrence_vectors.json by',
		'-- apps/web/src/lib/social/recurrence_vectors.test.ts — never hand-edit.',
		'-- Regenerate: cd apps/web && RECURRENCE_VECTORS_WRITE=1 npx tsx --test src/lib/social/recurrence_vectors.test.ts',
		'--',
		'-- private.is_event_occurrence and private.event_occurrences (migration',
		'-- 20270808000011) are the SQL leg of the clients\' expandInstances. Every',
		'-- probe below carries the web expansion\'s verdict; the web and Dart suites',
		'-- replay the same vectors, so this file is the third leg of one golden set.',
		'-- With the § 1918 transition window CLOSED the SQL must agree with the',
		'-- client exactly for every series with a timezone (and every one-off), and',
		'-- event_occurrences must list exactly the client\'s instants. With the window',
		'-- OPEN a timezoned series also admits its UTC-clock instants, the ones every',
		'-- build before § 1918 mints, on the lenient default, while a strict caller',
		'-- (p_allow_legacy => false, the money paths) still agrees with the client',
		'-- exactly. The window is the recurrence_utc_clock_legacy flag: the closed',
		'-- pass deletes its row, so an absent flag is pinned strict. For a legacy',
		'-- series with no timezone the clients expand in each viewer\'s local zone,',
		'-- so the SQL deliberately checks only the bounds and a whole-day offset',
		'-- (±1 h): those probes pin that documented rule, and the generator refuses',
		'-- a fixture in which any viewer zone offers an instant the rule rejects.',
		'',
		'begin;',
		`select plan(${asserts});`,
		'',
		"insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)",
		"values ('99999999-9999-9999-9999-99991145b001', 'vectors-1145@example.com', '', now(),",
		"        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')",
		'on conflict (id) do nothing;',
		'',
		"insert into clubs (id, owner_id, name, slug, is_public, join_policy)",
		"values ('dddddddd-0000-0000-1145-00000000000c', '99999999-9999-9999-9999-99991145b001',",
		"        'Occurrence Vectors 1145', 'occurrence-vectors-1145', true, 'open');",
		'',
		'insert into events (id, club_id, title, author_id, starts_at, recurrence_freq,',
		'                    recurrence_byday, recurrence_until, recurrence_count, timezone)',
		'values'
	);
	fx.series.forEach((s, i) => {
		const e = s.event;
		const sep = i === fx.series.length - 1 ? ';' : ',';
		lines.push(
			`  (${sqlLit(eventId(i))}, 'dddddddd-0000-0000-1145-00000000000c', ${sqlLit(`vectors ${i + 1}`)},` +
				` '99999999-9999-9999-9999-99991145b001', ${sqlLit(e.starts_at)}, ${sqlLit(e.recurrence_freq)},` +
				` ${sqlLit(e.recurrence_byday)}, ${sqlLit(e.recurrence_until)}, ${sqlLit(e.recurrence_count)},` +
				` ${sqlLit(e.timezone)})${sep}`
		);
	});
	lines.push(
		'',
		'create temp table occurrence_probes (event_id uuid, at timestamptz, expect boolean, expect_open boolean) on commit drop;',
		'insert into occurrence_probes (event_id, at, expect, expect_open) values'
	);
	const rows: string[] = [];
	fx.series.forEach((s, i) => {
		const tz = s.event.recurrence_freq != null && s.event.timezone != null;
		for (const p of s.probes ?? []) {
			const open = p.sql || (tz && utcClockOccurrence(s.event, new Date(p.at)));
			rows.push(`  (${sqlLit(eventId(i))}, ${sqlLit(p.at)}, ${p.sql}, ${open})`);
		}
	});
	lines.push(rows.join(',\n') + ';', '');
	lines.push(
		'select is((select count(*)::int from occurrence_probes), ' +
			`${rows.length}, 'every generated probe was loaded');`,
		'',
		'-- The window closed (no flag row): wall-clock instants only.',
		"delete from private.feature_flags where name = 'recurrence_utc_clock_legacy';",
		''
	);
	const probeCheck = (i: number, column: string, label: string, strict = false) => {
		lines.push(
			'select is(',
			'  array(select to_char(at at time zone \'UTC\', \'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"\') || \'=\' ||',
			`               private.is_event_occurrence(event_id, at${strict ? ', false' : ''})::text`,
			`          from occurrence_probes where event_id = ${sqlLit(eventId(i))} order by at),`,
			`  array(select to_char(at at time zone \'UTC\', \'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"\') || \'=\' || ${column}::text`,
			`          from occurrence_probes where event_id = ${sqlLit(eventId(i))} order by at),`,
			`  ${sqlLit(label)});`,
			''
		);
	};
	fx.series.forEach((s, i) => {
		const legacy = s.event.recurrence_freq != null && s.event.timezone == null;
		const what = legacy
			? 'matches the documented legacy rule (bounds + whole-day offset)'
			: 'agrees with expandInstances on every probe';
		probeCheck(i, 'expect', `${s.name}: is_event_occurrence ${what}`);
	});
	fx.series.forEach((s, i) => {
		if (!canonical(s.event)) return;
		const list = s.expected![fx.viewer_zones[0]];
		const want = list.length ? `array[${list.map((x) => sqlLit(x)).join(', ')}]::timestamptz[]` : "'{}'::timestamptz[]";
		lines.push(
			'select is(',
			`  array(select private.event_occurrences(${sqlLit(eventId(i))}, ${sqlLit(s.from)}, ${sqlLit(s.to)})),`,
			`  ${want},`,
			`  ${sqlLit(`${s.name}: event_occurrences lists exactly the expandInstances window`)});`,
			''
		);
	});
	lines.push(
		'-- The window open: a timezoned series also admits its UTC-clock instants.',
		"insert into private.feature_flags (name, enabled) values ('recurrence_utc_clock_legacy', true)",
		'on conflict (name) do update set enabled = true;',
		''
	);
	fx.series.forEach((s, i) => {
		if (s.event.recurrence_freq == null || s.event.timezone == null) return;
		probeCheck(i, 'expect_open', `${s.name}: inside the transition window the UTC-clock instants are accepted too`);
	});
	fx.series.forEach((s, i) => {
		if (s.event.recurrence_freq == null || s.event.timezone == null) return;
		probeCheck(i, 'expect', `${s.name}: inside the window a strict caller still agrees with expandInstances`, true);
	});
	lines.push('select * from finish();', 'rollback;', '');
	return lines.join('\n');
}

// One probe or one zone's list per line, so a regeneration diffs by instant.
function formatFixture(fx: Fixture): string {
	const j = JSON.stringify;
	const series = fx.series.map((s) => {
		const expected = Object.entries(s.expected ?? {})
			.map(([zone, list]) => `    ${j(zone)}: ${j(list)}`)
			.join(',\n');
		const probes = (s.probes ?? []).map((p) => `    ${j(p)}`).join(',\n');
		return [
			'  {',
			`   "name": ${j(s.name)},`,
			`   "event": ${j(s.event)},`,
			`   "from": ${j(s.from)},`,
			`   "to": ${j(s.to)},`,
			`   "expected": {\n${expected}\n   },`,
			`   "probes": [\n${probes}\n   ]`,
			'  }'
		].join('\n');
	});
	return [
		'{',
		` "_about": ${j(fx._about)},`,
		` "viewer_zones": ${j(fx.viewer_zones)},`,
		` "series": [\n${series.join(',\n')}\n ]`,
		'}',
		''
	].join('\n');
}

const fixture: Fixture = JSON.parse(readFileSync(FIXTURE, 'utf-8'));

if (process.env.RECURRENCE_VECTORS_WRITE === '1') {
	fixture.series = fixture.series.map((s) => compute(fixture, s));
	writeFileSync(FIXTURE, formatFixture(fixture));
	writeFileSync(PGTAP, renderPgtap(fixture));
}

for (const s of fixture.series) {
	test(`recurrence vectors — ${s.name}: expandInstances reproduces the fixture in every viewer zone`, () => {
		const fresh = compute(fixture, s);
		assert.deepEqual(fresh.expected, s.expected);
		assert.deepEqual(fresh.probes, s.probes);
	});
}

test('recurrence vectors — a series with a timezone expands identically in every viewer zone', () => {
	for (const s of fixture.series) {
		if (s.event.recurrence_freq != null && s.event.timezone == null) continue;
		const [first, ...rest] = fixture.viewer_zones;
		for (const zone of rest) {
			assert.deepEqual(s.expected![zone], s.expected![first], `${s.name} in ${zone}`);
		}
	}
});

test('recurrence vectors — the SQL is held to the client verdict, and a legacy series never refuses an offered instant', () => {
	for (const s of fixture.series) {
		const legacy = s.event.recurrence_freq != null && s.event.timezone == null;
		for (const p of s.probes!) {
			const offered = Object.values(p.occurrence).some(Boolean);
			if (legacy) {
				if (offered) assert.equal(p.sql, true, `${s.name}: SQL would refuse ${p.at}, which a viewer is offered`);
			} else {
				assert.equal(p.sql, p.occurrence[fixture.viewer_zones[0]], `${s.name} at ${p.at}`);
			}
		}
	}
});

test('recurrence vectors — the committed pgTAP file is what the fixture renders', () => {
	assert.equal(readFileSync(PGTAP, 'utf-8'), renderPgtap(fixture));
});
