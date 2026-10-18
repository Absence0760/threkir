import { test } from 'node:test';
import assert from 'node:assert/strict';

import { startLocalDayTicker, type DayTickerDeps } from './local_day_ticker';

/// A clock and timer queue the test advances by hand.
function fakeClock(start: Date) {
	let now = start.getTime();
	let pending: { at: number; fn: () => void; id: number } | null = null;
	let nextId = 1;
	const listeners = new Map<string, () => void>();
	const winListeners = new Map<string, () => void>();
	let visibility = 'visible';
	const deps: DayTickerDeps = {
		now: () => new Date(now),
		setTimeout: (fn, ms) => {
			pending = { at: now + ms, fn, id: nextId++ };
			return pending.id;
		},
		clearTimeout: (h) => {
			if (pending?.id === h) pending = null;
		},
		doc: {
			addEventListener: (type, fn) => {
				listeners.set(type, fn);
			},
			removeEventListener: (type) => {
				listeners.delete(type);
			},
			get visibilityState() {
				return visibility;
			},
		},
		win: {
			addEventListener: (type, fn) => {
				winListeners.set(type, fn);
			},
			removeEventListener: (type) => {
				winListeners.delete(type);
			},
		},
	};
	return {
		deps,
		advance(ms: number) {
			now += ms;
			while (pending && pending.at <= now) {
				const p = pending;
				pending = null;
				p.fn();
			}
		},
		/// Moves the clock without firing timers: a slept machine.
		sleep(ms: number) {
			now += ms;
		},
		show() {
			visibility = 'visible';
			listeners.get('visibilitychange')?.();
		},
		fire(type: 'focus' | 'pageshow') {
			winListeners.get(type)?.();
		},
		get armed() {
			return pending !== null;
		},
		get listening() {
			return listeners.has('visibilitychange') || winListeners.size > 0;
		},
	};
}

test('startLocalDayTicker reports today at once and the next day at local midnight, not before', () => {
	const clock = fakeClock(new Date(2026, 9, 17, 23, 58));
	const days: string[] = [];
	startLocalDayTicker((iso) => days.push(iso), clock.deps);
	assert.deepEqual(days, ['2026-10-17']);
	clock.advance(60_000);
	assert.deepEqual(days, ['2026-10-17']);
	clock.advance(60_000);
	assert.deepEqual(days, ['2026-10-17', '2026-10-18']);
	clock.advance(24 * 3600_000);
	assert.deepEqual(days, ['2026-10-17', '2026-10-18', '2026-10-19']);
});

test('startLocalDayTicker catches up on visibility after the machine slept through midnight', () => {
	const clock = fakeClock(new Date(2026, 9, 17, 22, 0));
	const days: string[] = [];
	startLocalDayTicker((iso) => days.push(iso), clock.deps);
	clock.sleep(5 * 3600_000);
	assert.deepEqual(days, ['2026-10-17']);
	clock.show();
	assert.deepEqual(days, ['2026-10-17', '2026-10-18']);
});

test('startLocalDayTicker catches up on focus and pageshow when the tab stayed visible through a suspend', () => {
	for (const event of ['focus', 'pageshow'] as const) {
		const clock = fakeClock(new Date(2026, 9, 17, 22, 0));
		const days: string[] = [];
		startLocalDayTicker((iso) => days.push(iso), clock.deps);
		clock.sleep(5 * 3600_000);
		clock.fire(event);
		assert.deepEqual(days, ['2026-10-17', '2026-10-18'], event);
	}
});

test('startLocalDayTicker teardown clears the timer and the listener', () => {
	const clock = fakeClock(new Date(2026, 9, 17, 12, 0));
	const stop = startLocalDayTicker(() => {}, clock.deps);
	assert.equal(clock.armed, true);
	assert.equal(clock.listening, true);
	stop();
	assert.equal(clock.armed, false);
	assert.equal(clock.listening, false);
});

test('/plans/[id] takes its today from the ticker, not a $derived(todayISO()) that never re-runs', async () => {
	const { readFileSync } = await import('node:fs');
	const { resolve } = await import('node:path');
	const src = readFileSync(resolve(import.meta.dirname, '../../routes/plans/[id]/+page.svelte'), 'utf8');
	assert.doesNotMatch(src, /\$derived\(todayISO\(\)\)/);
	assert.match(src, /startLocalDayTicker\(\(iso\) => \(today = iso\)\)/);
});
