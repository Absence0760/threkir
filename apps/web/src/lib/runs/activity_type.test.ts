import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ACTIVITY_TYPES, activityUsesSpeed } from './activity_type';

test('only a ride is read by speed, matching core_models ActivityType.usesSpeed', () => {
	assert.deepEqual(
		ACTIVITY_TYPES.filter((type) => activityUsesSpeed(type)),
		['cycle'],
	);
});

test('an untagged or unknown activity reads by pace, like the column default', () => {
	assert.equal(activityUsesSpeed(null), false);
	assert.equal(activityUsesSpeed(undefined), false);
	assert.equal(activityUsesSpeed('rowing'), false);
});
