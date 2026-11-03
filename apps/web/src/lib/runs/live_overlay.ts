// The streamer overlay (migration 20271104000001, decisions § 2265): a
// transparent page a creator adds to OBS as a browser source, read through a
// revocable per-user token instead of the public live link.
//
// The URL splits in two on purpose. What the overlay may SEE (the delay, the
// map, heart rate) is stored with the token and enforced by
// `live_overlay_feed`; the URL cannot widen it. How it LOOKS (which stats,
// units, layout, whether to draw the trace it is given) rides in the query
// string, so a creator can keep several sources with different layouts on one
// token. The token rides in the fragment, which a browser never sends to a
// server, so it stays out of CDN and access logs.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { AppDatabase } from '#lib/core/database.ts';
import { dbError, thrownMessage } from '#lib/core/supabase_error.ts';

export const OVERLAY_STATS = ['distance', 'pace', 'elapsed', 'hr'] as const;
export type OverlayStat = (typeof OVERLAY_STATS)[number];
export type OverlayUnits = 'km' | 'mi';
export type OverlayLayout = 'row' | 'column';

export interface OverlayConfig {
	stats: OverlayStat[];
	units: OverlayUnits;
	layout: OverlayLayout;
	map: boolean;
}

export const DEFAULT_OVERLAY_CONFIG: OverlayConfig = {
	stats: ['distance', 'pace', 'elapsed', 'hr'],
	units: 'km',
	layout: 'row',
	map: false,
};

/// The delays both clients offer. The server takes any 0-900 s.
export const OVERLAY_DELAY_PRESETS = [0, 30, 60, 120, 300, 600] as const;
export const OVERLAY_DEFAULT_DELAY_S = 60;
export const OVERLAY_POLL_MS = 5000;
/// Every Nth poll re-reads without a cursor, which is how the overlay learns
/// the run ended: a cursor poll cannot tell "nothing new" from "concluded".
export const OVERLAY_FULL_READ_EVERY = 12;
/// Pace over the last minute of running, rather than the whole-run average a
/// spectator sees: a stream's viewers are watching what the runner does now.
export const OVERLAY_PACE_WINDOW_S = 60;
const MIN_PACE_WINDOW_M = 20;

const TOKEN = /^[A-Za-z0-9_-]{16,64}$/;

export function isOverlayToken(token: string): boolean {
	return TOKEN.test(token);
}

/// The token from `location.hash`, or null when it is missing or could not
/// have been minted by `create_live_overlay_token`.
export function parseOverlayToken(hash: string): string | null {
	const raw = hash.startsWith('#') ? hash.slice(1) : hash;
	return isOverlayToken(raw) ? raw : null;
}

export function parseOverlayConfig(params: URLSearchParams): OverlayConfig {
	const statsRaw = params.get('stats');
	let stats = DEFAULT_OVERLAY_CONFIG.stats;
	if (statsRaw != null) {
		const picked = new Set(statsRaw.split(','));
		stats = OVERLAY_STATS.filter((s) => picked.has(s));
	}
	return {
		stats,
		units: params.get('units') === 'mi' ? 'mi' : 'km',
		layout: params.get('layout') === 'column' ? 'column' : 'row',
		map: params.get('map') === '1',
	};
}

export function overlayQuery(config: OverlayConfig): string {
	const q = new URLSearchParams();
	q.set('stats', OVERLAY_STATS.filter((s) => config.stats.includes(s)).join(','));
	q.set('units', config.units);
	q.set('layout', config.layout);
	if (config.map) q.set('map', '1');
	return q.toString().replaceAll('%2C', ',');
}

/// Null for a malformed token, so a bad RPC result is never offered as a link.
export function overlayUrl(origin: string, token: string, config: OverlayConfig): string | null {
	if (!isOverlayToken(token)) return null;
	return `${origin.replace(/\/+$/, '')}/live/overlay?${overlayQuery(config)}#${token}`;
}

export interface OverlayPing {
	at: string;
	elapsed_s: number | null;
	distance_m: number | null;
	lat: number | null;
	lng: number | null;
	bpm: number | null;
}

/// Elapsed seconds and metres to price a pace from: the span of the last
/// `OVERLAY_PACE_WINDOW_S` of elapsed time, or the whole run while that span
/// is too short to mean anything. Null before any distance is covered.
export function overlayPaceSpan(
	pings: readonly OverlayPing[],
): { seconds: number; metres: number } | null {
	const odo = pings.filter(
		(p): p is OverlayPing & { elapsed_s: number; distance_m: number } =>
			p.elapsed_s != null && p.distance_m != null,
	);
	const last = odo.at(-1);
	if (!last || last.distance_m <= 0 || last.elapsed_s <= 0) return null;
	const from = [...odo].reverse().find((p) => last.elapsed_s - p.elapsed_s >= OVERLAY_PACE_WINDOW_S);
	if (from) {
		const metres = last.distance_m - from.distance_m;
		const seconds = last.elapsed_s - from.elapsed_s;
		if (metres >= MIN_PACE_WINDOW_M && seconds > 0) return { seconds, metres };
	}
	return { seconds: last.elapsed_s, metres: last.distance_m };
}

/// The trace the mini-map draws, projected into a `size`-square viewBox with
/// `pad` units of margin, and where it ends (the runner's last position). Only rows the server gave coordinates for: it sends
/// none with the map off and none for a privacy-zone last-seen row.
export function overlayTracePath(
	pings: readonly OverlayPing[],
	size = 100,
	pad = 6,
): { d: string; end: { x: number; y: number } } | null {
	const pts = pings.filter(
		(p): p is OverlayPing & { lat: number; lng: number } => p.lat != null && p.lng != null,
	);
	if (pts.length < 2) return null;
	const midLat = (pts.reduce((s, p) => s + p.lat, 0) / pts.length) * (Math.PI / 180);
	const xs = pts.map((p) => p.lng * Math.cos(midLat));
	const ys = pts.map((p) => p.lat);
	const minX = Math.min(...xs);
	const maxX = Math.max(...xs);
	const minY = Math.min(...ys);
	const maxY = Math.max(...ys);
	const span = Math.max(maxX - minX, maxY - minY) || 1e-9;
	const scale = (size - pad * 2) / span;
	const offX = pad + (size - pad * 2 - (maxX - minX) * scale) / 2;
	const offY = pad + (size - pad * 2 - (maxY - minY) * scale) / 2;
	const at = (i: number) => ({
		x: Number((offX + (xs[i] - minX) * scale).toFixed(1)),
		y: Number((offY + (maxY - ys[i]) * scale).toFixed(1)),
	});
	const d = pts
		.map((_, i) => {
			const { x, y } = at(i);
			return `${i === 0 ? 'M' : 'L'}${x} ${y}`;
		})
		.join(' ');
	return { d, end: at(pts.length - 1) };
}

// ─── RPCs ───

export interface LiveOverlaySettings {
	token: string;
	delayS: number;
	showMap: boolean;
	showHeartRate: boolean;
	createdAt: string;
	/// Whether the owner has health-data consent on record; heart rate can be
	/// turned on only with it.
	heartRateConsent: boolean;
}

export async function liveOverlayEnabled(client: SupabaseClient<AppDatabase>): Promise<boolean> {
	const { data, error } = await client.rpc('live_overlay_enabled', undefined, { get: true });
	if (error) throw dbError(error);
	return data === true;
}

/// What the overlay page does with the gate. A failed read is 'error', not
/// 'open': the page shows itself unavailable and asks the gate again rather
/// than polling a feed it was never told it may read.
export type OverlayGate = 'open' | 'closed' | 'error';

export async function readOverlayGate(read: () => Promise<boolean>): Promise<OverlayGate> {
	try {
		return (await read()) ? 'open' : 'closed';
	} catch (err) {
		console.warn('live overlay: gate read failed', thrownMessage(err));
		return 'error';
	}
}

export async function fetchLiveOverlay(
	client: SupabaseClient<AppDatabase>,
): Promise<LiveOverlaySettings | null> {
	const { data, error } = await client.rpc('get_live_overlay', undefined, { get: true });
	if (error) throw dbError(error);
	const row = Array.isArray(data) ? data[0] : null;
	if (!row || typeof row.token !== 'string') return null;
	return {
		token: row.token,
		delayS: row.delay_s,
		showMap: row.show_map === true,
		showHeartRate: row.show_heart_rate === true,
		createdAt: row.created_at,
		heartRateConsent: row.heart_rate_consent === true,
	};
}

/// Makes the token, or replaces it so the old URL stops working at once.
export async function createLiveOverlayToken(client: SupabaseClient<AppDatabase>): Promise<string> {
	const { data, error } = await client.rpc('create_live_overlay_token');
	if (error) throw dbError(error);
	if (typeof data !== 'string' || !isOverlayToken(data)) {
		throw new Error('create_live_overlay_token returned no token');
	}
	return data;
}

export async function revokeLiveOverlayToken(client: SupabaseClient<AppDatabase>): Promise<void> {
	const { error } = await client.rpc('revoke_live_overlay_token');
	if (error) throw dbError(error);
}

export async function updateLiveOverlaySettings(
	client: SupabaseClient<AppDatabase>,
	settings: { delayS: number; showMap: boolean; showHeartRate: boolean },
): Promise<void> {
	const { error } = await client.rpc('update_live_overlay_settings', {
		p_delay_s: settings.delayS,
		p_show_map: settings.showMap,
		p_show_heart_rate: settings.showHeartRate,
	});
	if (error) throw dbError(error);
}

/// Saves the settings in [next] and returns the overlay as the server now
/// holds it, or null when it no longer exists. `update_live_overlay_settings`
/// writes all three settings, so the ones not being changed are read back
/// first: the copy a page loaded may predate a change made on the phone.
export async function saveLiveOverlaySettings(
	client: SupabaseClient<AppDatabase>,
	next: Partial<Pick<LiveOverlaySettings, 'delayS' | 'showMap' | 'showHeartRate'>>,
): Promise<LiveOverlaySettings | null> {
	const latest = await fetchLiveOverlay(client);
	if (!latest) return null;
	const after = { ...latest, ...next };
	await updateLiveOverlaySettings(client, after);
	return after;
}

/// A POST: the token is the capability, and a GET would put it in the query
/// string of every request log.
export async function fetchLiveOverlayFeed(
	client: SupabaseClient<AppDatabase>,
	token: string,
	since: string | null = null,
): Promise<OverlayPing[]> {
	const { data, error } = await client.rpc('live_overlay_feed', {
		p_token: token,
		...(since ? { p_since: since } : {}),
	});
	if (error) throw dbError(error);
	return Array.isArray(data) ? data : [];
}
