// Mirrors apps/mobile_android/test/share_look_test.dart case for case.

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DEFAULT_SHARE_LOOK,
	DEFAULT_SHARE_STATS,
	MAX_SHARE_STATS,
	SHARE_LOOK_STORAGE_KEY,
	loadShareLook,
	saveShareLook,
	shareLookFromJson,
	shareLookToJson,
	toggleShareStat,
	withSharePlacement,
	type RunShareLook,
} from './share_look';
import { DEFAULT_SHARE_PLACEMENT } from './share_placement';
import { RUN_SHARE_STAT_KINDS } from './run_share_stats';

const look = (over: Partial<RunShareLook> = {}): RunShareLook => ({
	...DEFAULT_SHARE_LOOK,
	stats: [...DEFAULT_SHARE_LOOK.stats],
	...over,
});

function memoryStorage(init: Record<string, string> = {}) {
	const data = new Map(Object.entries(init));
	return {
		getItem: (k: string) => data.get(k) ?? null,
		setItem: (k: string, v: string) => void data.set(k, v),
	};
}

describe('toggleShareStat', () => {
	test('adds a stat in display order, whatever order it was picked in', () => {
		assert.deepEqual(toggleShareStat(look({ stats: ['time'] }), 'distance').stats, ['distance', 'time']);
	});

	test('removes a picked stat', () => {
		assert.deepEqual(toggleShareStat(look(), 'pace').stats, ['distance', 'time']);
	});

	test('never empties the set', () => {
		const one = look({ stats: ['distance'] });
		assert.equal(toggleShareStat(one, 'distance'), one);
	});

	test('never grows past MAX_SHARE_STATS', () => {
		const full = look({ stats: ['distance', 'pace', 'time', 'climb'] });
		assert.equal(full.stats.length, MAX_SHARE_STATS);
		assert.equal(toggleShareStat(full, 'heartRate'), full);
	});
});

describe('share look json', () => {
	test('round-trips every field', () => {
		const l = look({ layout: 'hero', ink: 'brand', aspect: 'post', stats: ['distance', 'heartRate'], mark: false });
		assert.deepEqual(shareLookFromJson(JSON.parse(JSON.stringify(shareLookToJson(l)))), l);
	});

	test('an unknown value takes its default and keeps the rest', () => {
		const l = shareLookFromJson({ layout: 'carousel', ink: 'dark', aspect: 'post', stats: ['distance', 'cadence'] });
		assert.equal(l.layout, DEFAULT_SHARE_LOOK.layout);
		assert.equal(l.ink, 'dark');
		assert.equal(l.aspect, 'post');
		assert.deepEqual(l.stats, ['distance']);
	});

	test('a stored set past MAX_SHARE_STATS is cut to it', () => {
		assert.equal(shareLookFromJson({ stats: [...RUN_SHARE_STAT_KINDS] }).stats.length, MAX_SHARE_STATS);
	});

	test('anything that is not an object is the default look', () => {
		for (const junk of [null, 7, 'stack', []]) {
			assert.deepEqual(shareLookFromJson(junk), look(), String(junk));
		}
	});

	test('the mark is on by default and only a stored boolean turns it off', () => {
		assert.equal(DEFAULT_SHARE_LOOK.mark, true);
		assert.equal(shareLookFromJson({ layout: 'strip' }).mark, true);
		assert.equal(shareLookFromJson({ mark: 'no' }).mark, true);
		assert.equal(shareLookFromJson({ mark: false }).mark, false);
	});

	test('each aspect keeps its own placement, and only the current one moves', () => {
		const moved = withSharePlacement(look({ aspect: 'post' }), { x: 0.3, y: 0.4, scale: 0.7 });
		assert.deepEqual(moved.placements.post, { x: 0.3, y: 0.4, scale: 0.7 });
		assert.deepEqual(moved.placements.story, DEFAULT_SHARE_PLACEMENT);
		assert.deepEqual(shareLookFromJson(JSON.parse(JSON.stringify(shareLookToJson(moved)))), moved);
	});

	test('a bad stored placement fails closed for its aspect and keeps the other', () => {
		const l = shareLookFromJson({
			placements: { story: { x: 9, y: 0.5, scale: 1 }, post: { x: 0.2, y: 0.8, scale: 0.6 } },
		});
		assert.deepEqual(l.placements.story, DEFAULT_SHARE_PLACEMENT);
		assert.deepEqual(l.placements.post, { x: 0.2, y: 0.8, scale: 0.6 });
		assert.deepEqual(shareLookFromJson({ placements: 'top' }).placements, look().placements);
	});

	test('an empty or absent stat list is the default set', () => {
		assert.deepEqual(shareLookFromJson({ stats: [] }).stats, DEFAULT_SHARE_STATS);
		assert.deepEqual(shareLookFromJson({ layout: 'strip' }).stats, DEFAULT_SHARE_STATS);
	});
});

describe('load / save', () => {
	test('a saved look is what the next load returns', () => {
		const storage = memoryStorage();
		const l = look({ layout: 'strip', ink: 'dark' });
		saveShareLook(l, storage);
		assert.deepEqual(loadShareLook(storage), l);
	});

	test('nothing saved loads the default', () => {
		assert.deepEqual(loadShareLook(memoryStorage()), look());
	});

	test('a corrupt saved value loads the default instead of throwing', () => {
		assert.deepEqual(loadShareLook(memoryStorage({ [SHARE_LOOK_STORAGE_KEY]: '{not json' })), look());
	});
});
