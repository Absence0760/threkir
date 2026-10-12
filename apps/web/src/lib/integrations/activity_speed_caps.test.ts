import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { maxSpeedMpsForActivity } from './garmin-fit';
import {
	ACTIVITY_TYPES,
	ACTIVITY_TYPE_ICONS,
	activityTypeIcon,
	isActivityType,
} from '../runs/activity_type';

// The per-activity speed cap is where a GPS jump stops being distance. The
// web importer and the Dart recorder must agree, or the same file measures
// differently on each.

const DART = fileURLToPath(
	new URL('../../../../../packages/core_models/lib/src/activity_type.dart', import.meta.url),
);

function dartCaps(): Record<string, number> {
	const src = readFileSync(DART, 'utf8');
	const body = src.slice(src.indexOf('double get maxSpeedMps'));
	const end = body.indexOf('\n  }\n');
	const caps: Record<string, number> = {};
	for (const m of body.slice(0, end).matchAll(/case ActivityType\.(\w+):\s*return ([\d.]+);/g)) {
		caps[m[1]] = Number(m[2]);
	}
	return caps;
}

test('every activity speed cap matches ActivityType.maxSpeedMps in core_models', () => {
	const caps = dartCaps();
	assert.deepEqual(Object.keys(caps).sort(), [...ACTIVITY_TYPES].sort());
	for (const type of ACTIVITY_TYPES) {
		assert.equal(maxSpeedMpsForActivity(type), caps[type], type);
	}
});

test('an unknown or missing activity type gets the run cap, not a looser one', () => {
	assert.equal(maxSpeedMpsForActivity(null), maxSpeedMpsForActivity('run'));
	assert.equal(maxSpeedMpsForActivity(undefined), maxSpeedMpsForActivity('run'));
	assert.equal(
		maxSpeedMpsForActivity('skateboard' as unknown as 'run'),
		maxSpeedMpsForActivity('run'),
	);
});

test('the caps keep the physical order: walk < hike < stroller < run < cycle', () => {
	const order = ['walk', 'hike', 'stroller', 'run', 'cycle'] as const;
	for (let i = 1; i < order.length; i++) {
		assert.ok(
			maxSpeedMpsForActivity(order[i - 1]) < maxSpeedMpsForActivity(order[i]),
			`${order[i - 1]} < ${order[i]}`,
		);
	}
});

test('isActivityType accepts the vocabulary exactly, case and prototype names included', () => {
	for (const t of ACTIVITY_TYPES) assert.equal(isActivityType(t), true, t);
	for (const bad of ['Run', 'RUN', ' run', '', 'constructor', 'toString', '__proto__', 'swim']) {
		assert.equal(isActivityType(bad), false, JSON.stringify(bad));
	}
});

test('every activity type has its own icon, and anything else falls back to the run icon', () => {
	const icons = ACTIVITY_TYPES.map((t) => ACTIVITY_TYPE_ICONS[t]);
	assert.ok(icons.every((i) => typeof i === 'string' && i.length > 0));
	assert.equal(new Set(icons).size, icons.length);
	assert.equal(activityTypeIcon(null), ACTIVITY_TYPE_ICONS.run);
	assert.equal(activityTypeIcon(undefined), ACTIVITY_TYPE_ICONS.run);
	assert.equal(activityTypeIcon('constructor'), ACTIVITY_TYPE_ICONS.run);
	assert.equal(activityTypeIcon('cycle'), ACTIVITY_TYPE_ICONS.cycle);
});
