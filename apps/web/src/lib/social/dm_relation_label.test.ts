import { test } from 'node:test';
import assert from 'node:assert/strict';
import { en } from '../i18n/locales/en';
import { dmRelationLabelKey } from './dm_relation_label.ts';

test('each follow relation names itself', () => {
	const label = (r: Parameters<typeof dmRelationLabelKey>[0]) => (en as Record<string, string>)[dmRelationLabelKey(r)];
	assert.equal(label('mutual'), 'You follow each other');
	assert.equal(label('follows_you'), 'Follows you');
	assert.equal(label('you_follow'), 'You follow them');
});
