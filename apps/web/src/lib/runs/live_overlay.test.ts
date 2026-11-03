import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import type { SupabaseClient } from '@supabase/supabase-js';

import type { AppDatabase } from '#lib/core/database.ts';

import {
	DEFAULT_OVERLAY_CONFIG,
	OVERLAY_DEFAULT_DELAY_S,
	OVERLAY_DELAY_PRESETS,
	overlayPaceSpan,
	overlayQuery,
	overlayTracePath,
	overlayUrl,
	parseOverlayConfig,
	parseOverlayToken,
	readOverlayGate,
	saveLiveOverlaySettings,
	type OverlayPing,
} from './live_overlay.ts';

const TOKEN = 'Ab3_-xYz0123456789abcdEF';

function ping(over: Partial<OverlayPing>): OverlayPing {
	return { at: '2026-11-03T10:00:00Z', elapsed_s: null, distance_m: null, lat: null, lng: null, bpm: null, ...over };
}

test('the token is read from the fragment and refused when malformed', () => {
	assert.equal(parseOverlayToken(`#${TOKEN}`), TOKEN);
	assert.equal(parseOverlayToken(TOKEN), TOKEN);
	assert.equal(parseOverlayToken(''), null);
	assert.equal(parseOverlayToken('#short'), null);
	assert.equal(parseOverlayToken(`#${TOKEN}&x=1`), null);
	assert.equal(parseOverlayToken('#a+b/c=defghijklmnopqrs'), null);
});

test('an empty query is the default config: every stat, km, a row, no map', () => {
	assert.deepEqual(parseOverlayConfig(new URLSearchParams('')), DEFAULT_OVERLAY_CONFIG);
	assert.equal(DEFAULT_OVERLAY_CONFIG.map, false);
});

test('the query picks stats in a fixed order and ignores unknown ones', () => {
	const c = parseOverlayConfig(new URLSearchParams('stats=hr,bogus,distance&units=mi&layout=column&map=1'));
	assert.deepEqual(c, { stats: ['distance', 'hr'], units: 'mi', layout: 'column', map: true });
	assert.deepEqual(parseOverlayConfig(new URLSearchParams('stats=')).stats, []);
	assert.equal(parseOverlayConfig(new URLSearchParams('units=furlong&layout=grid&map=yes')).units, 'km');
	assert.equal(parseOverlayConfig(new URLSearchParams('layout=grid')).layout, 'row');
	assert.equal(parseOverlayConfig(new URLSearchParams('map=yes')).map, false);
});

test('a built URL round-trips and carries the token only in the fragment', () => {
	const config = { stats: ['pace', 'distance'] as const, units: 'mi' as const, layout: 'column' as const, map: true };
	const url = overlayUrl('https://threkir.com/', TOKEN, { ...config, stats: [...config.stats] });
	assert.equal(url, `https://threkir.com/live/overlay?stats=distance,pace&units=mi&layout=column&map=1#${TOKEN}`);
	const parsed = new URL(url!);
	assert.equal(parsed.pathname, '/live/overlay');
	assert.ok(!parsed.search.includes(TOKEN));
	assert.equal(parseOverlayToken(parsed.hash), TOKEN);
	assert.deepEqual(parseOverlayConfig(parsed.searchParams), { ...config, stats: ['distance', 'pace'] });
	assert.equal(overlayQuery(DEFAULT_OVERLAY_CONFIG), 'stats=distance,pace,elapsed,hr&units=km&layout=row');
});

test('a malformed token never becomes a link', () => {
	assert.equal(overlayUrl('https://threkir.com', 'nope', DEFAULT_OVERLAY_CONFIG), null);
});

test('the delay presets are within the server bound and include the default', () => {
	for (const d of OVERLAY_DELAY_PRESETS) assert.ok(d >= 0 && d <= 900);
	assert.ok((OVERLAY_DELAY_PRESETS as readonly number[]).includes(OVERLAY_DEFAULT_DELAY_S));
});

test('pace is priced over the last minute once there is a minute to price', () => {
	const pings = [
		ping({ elapsed_s: 0, distance_m: 0 }),
		ping({ elapsed_s: 240, distance_m: 1000 }),
		ping({ elapsed_s: 300, distance_m: 1300 }),
	];
	assert.deepEqual(overlayPaceSpan(pings), { seconds: 60, metres: 300 });
});

test('pace falls back to the whole run while the window is too short or too still', () => {
	assert.deepEqual(
		overlayPaceSpan([ping({ elapsed_s: 10, distance_m: 30 }), ping({ elapsed_s: 30, distance_m: 100 })]),
		{ seconds: 30, metres: 100 },
	);
	assert.deepEqual(
		overlayPaceSpan([ping({ elapsed_s: 100, distance_m: 500 }), ping({ elapsed_s: 200, distance_m: 510 })]),
		{ seconds: 200, metres: 510 },
	);
});

test('pace is null before any distance, and pings without odometer fields are skipped', () => {
	assert.equal(overlayPaceSpan([]), null);
	assert.equal(overlayPaceSpan([ping({ elapsed_s: 30, distance_m: 0 })]), null);
	assert.deepEqual(
		overlayPaceSpan([ping({ elapsed_s: 30, distance_m: 100 }), ping({ bpm: 150 })]),
		{ seconds: 30, metres: 100 },
	);
});

test('the trace draws only rows the server sent coordinates for', () => {
	assert.equal(overlayTracePath([ping({ distance_m: 10 }), ping({ distance_m: 20 })]), null);
	assert.equal(overlayTracePath([ping({ lat: 51.5, lng: -0.1 })]), null);
	const path = overlayTracePath([
		ping({ lat: 51.5, lng: -0.1 }),
		ping({ distance_m: 50 }),
		ping({ lat: 51.501, lng: -0.1 }),
	]);
	assert.ok(path);
	assert.equal(path!.d.split(/[ML]/).filter(Boolean).length, 2);
	assert.deepEqual(path!.end, { x: 50, y: 6 });
});

test('the trace fits the viewBox with its margin, north up', () => {
	const path = overlayTracePath([ping({ lat: 0, lng: 0 }), ping({ lat: 0.01, lng: 0 })], 100, 6)!;
	const nums = path.d.match(/-?\d+(\.\d+)?/g)!.map(Number);
	for (const n of nums) assert.ok(n >= 6 && n <= 94, `${n} outside the padded box`);
	assert.ok(nums[1] > nums[3], 'the northern point is drawn higher');
});

test('the overlay gate fails closed when it cannot be read', async () => {
	assert.equal(await readOverlayGate(async () => true), 'open');
	assert.equal(await readOverlayGate(async () => false), 'closed');
	const warn = console.warn;
	console.warn = () => {};
	try {
		assert.equal(
			await readOverlayGate(async () => {
				throw new Error('network');
			}),
			'error',
		);
	} finally {
		console.warn = warn;
	}
});

function overlayServer(row: Record<string, unknown> | null) {
	const updates: unknown[] = [];
	const client = {
		rpc: async (name: string, args?: unknown) => {
			if (name === 'get_live_overlay') return { data: row ? [row] : [], error: null };
			if (name === 'update_live_overlay_settings') {
				updates.push(args);
				return { data: null, error: null };
			}
			throw new Error(`unexpected rpc ${name}`);
		},
	} as unknown as SupabaseClient<AppDatabase>;
	return { client, updates };
}

test('saving one setting keeps the others as the server holds them now', async () => {
	const { client, updates } = overlayServer({
		token: TOKEN,
		delay_s: 300,
		show_map: false,
		show_heart_rate: true,
		created_at: '2026-11-03T10:00:00Z',
		heart_rate_consent: true,
	});
	const saved = await saveLiveOverlaySettings(client, { showMap: true });
	assert.deepEqual(updates, [{ p_delay_s: 300, p_show_map: true, p_show_heart_rate: true }]);
	assert.equal(saved?.delayS, 300);
	assert.equal(saved?.showMap, true);
	assert.equal(saved?.showHeartRate, true);
});

test('saving writes nothing when the overlay no longer exists', async () => {
	const { client, updates } = overlayServer(null);
	assert.equal(await saveLiveOverlaySettings(client, { delayS: 30 }), null);
	assert.deepEqual(updates, []);
});
