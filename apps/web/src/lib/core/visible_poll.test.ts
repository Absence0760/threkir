import { test } from 'node:test';
import assert from 'node:assert/strict';

import { startVisiblePoll, type VisiblePollDeps } from './visible_poll';

function harness(initial: 'visible' | 'hidden') {
	const timers = new Map<number, { fn: () => void; ms: number }>();
	let next = 1;
	const listeners = new Set<() => void>();
	const doc = {
		visibilityState: initial as string,
		addEventListener: (_: 'visibilitychange', fn: () => void) => listeners.add(fn),
		removeEventListener: (_: 'visibilitychange', fn: () => void) => listeners.delete(fn)
	};
	const deps: VisiblePollDeps = {
		setInterval: (fn, ms) => {
			const id = next++;
			timers.set(id, { fn, ms });
			return id;
		},
		clearInterval: (h) => timers.delete(h as number),
		doc
	};
	return {
		deps,
		timers,
		listeners,
		fire: () => [...timers.values()].forEach((t) => t.fn()),
		setVisibility(state: 'visible' | 'hidden') {
			doc.visibilityState = state;
			listeners.forEach((fn) => fn());
		}
	};
}

test('a visible tab polls at the given cadence', () => {
	const h = harness('visible');
	let ticks = 0;
	startVisiblePoll(() => ticks++, 10_000, h.deps);
	assert.equal(h.timers.size, 1);
	assert.equal([...h.timers.values()][0].ms, 10_000);
	assert.equal(ticks, 0, 'nothing runs before the first period');
	h.fire();
	h.fire();
	assert.equal(ticks, 2);
});

test('hiding the tab stops the interval and showing it ticks at once and restarts', () => {
	const h = harness('visible');
	let ticks = 0;
	startVisiblePoll(() => ticks++, 30_000, h.deps);
	h.setVisibility('hidden');
	assert.equal(h.timers.size, 0, 'no timer while hidden');
	h.setVisibility('visible');
	assert.equal(ticks, 1, 'catches up as soon as the tab is visible');
	assert.equal(h.timers.size, 1);
});

test('a tab opened hidden does not poll until it is shown', () => {
	const h = harness('hidden');
	let ticks = 0;
	startVisiblePoll(() => ticks++, 10_000, h.deps);
	assert.equal(h.timers.size, 0);
	h.setVisibility('visible');
	assert.equal(ticks, 1);
	assert.equal(h.timers.size, 1);
});

test('a repeated visible event does not stack a second interval', () => {
	const h = harness('visible');
	let ticks = 0;
	startVisiblePoll(() => ticks++, 10_000, h.deps);
	h.setVisibility('visible');
	assert.equal(h.timers.size, 1);
	assert.equal(ticks, 0);
});

test('teardown clears the interval and the listener', () => {
	const h = harness('visible');
	let ticks = 0;
	const stop = startVisiblePoll(() => ticks++, 10_000, h.deps);
	stop();
	assert.equal(h.timers.size, 0);
	assert.equal(h.listeners.size, 0);
	h.setVisibility('visible');
	assert.equal(ticks, 0);
});
