import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PrefsSaveQueue, type PrefsSaveStatus } from './prefs_save_queue';
import type { PrefsBag } from './settings_overlay';

function harness(write: (batch: PrefsBag) => Promise<unknown>) {
	const timers = new Map<number, { fn: () => void; ms: number }>();
	let next = 1;
	const statuses: PrefsSaveStatus[] = [];
	const errors: Error[] = [];
	const queue = new PrefsSaveQueue({
		write,
		onStatus: (s) => statuses.push(s),
		onError: (e) => errors.push(e),
		setTimer: (fn, ms) => {
			const id = next++;
			timers.set(id, { fn, ms });
			return id;
		},
		clearTimer: (id) => void timers.delete(id as number),
	});
	function fire(ms: number) {
		for (const [id, t] of [...timers]) {
			if (t.ms !== ms) continue;
			timers.delete(id);
			t.fn();
		}
	}
	return { queue, statuses, errors, timers, fire };
}

test('edits made inside the debounce window go out as one write', async () => {
	const writes: PrefsBag[] = [];
	const h = harness(async (b) => void writes.push(b));
	h.queue.enqueue({ resting_hr_bpm: 48 });
	h.queue.enqueue({ max_hr_bpm: 182 });
	assert.equal([...h.timers.values()].filter((t) => t.ms === 350).length, 1);
	await h.queue.flush();
	assert.deepEqual(writes, [{ resting_hr_bpm: 48, max_hr_bpm: 182 }]);
});

test('a later edit to the same key replaces the earlier one', async () => {
	const writes: PrefsBag[] = [];
	const h = harness(async (b) => void writes.push(b));
	h.queue.enqueue({ map_style: 'dark' });
	h.queue.enqueue({ map_style: 'satellite' });
	await h.queue.flush();
	assert.deepEqual(writes, [{ map_style: 'satellite' }]);
});

test('the status reads saving, then saved, then clears', async () => {
	const h = harness(async () => undefined);
	h.queue.enqueue({ undo_window_s: 30 });
	await h.queue.flush();
	assert.deepEqual(h.statuses, ['saving', 'saved']);
	h.fire(1800);
	assert.deepEqual(h.statuses, ['saving', 'saved', 'idle']);
});

test('flushing with nothing pending writes nothing', async () => {
	let calls = 0;
	const h = harness(async () => void calls++);
	await h.queue.flush();
	assert.equal(calls, 0);
	assert.deepEqual(h.statuses, []);
});

test('a failed batch is reported and kept, under any edit made meanwhile', async () => {
	const writes: PrefsBag[] = [];
	let fail = true;
	let queueRef: PrefsSaveQueue | null = null;
	const h = harness(async (b) => {
		writes.push(b);
		if (fail) {
			queueRef!.enqueue({ units_pace_format: 'kph' });
			throw new Error('refused');
		}
	});
	queueRef = h.queue;
	h.queue.enqueue({ units_pace_format: 'min_per_mi', week_start_day: 'sunday' });
	await h.queue.flush();
	assert.equal(h.errors[0]?.message, 'refused');
	assert.equal(h.statuses.at(-1), 'idle');

	fail = false;
	await h.queue.flush();
	assert.deepEqual(writes.at(-1), { units_pace_format: 'kph', week_start_day: 'sunday' });
});
