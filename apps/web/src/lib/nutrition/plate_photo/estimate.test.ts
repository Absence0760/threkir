import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	clampNutrient,
	cleanItemName,
	MAX_ITEM_NAME_CHARS,
	MAX_PLATE_ITEMS,
	PLATE_ITEM_LIMITS,
	validatePlateEstimate,
} from './estimate';

test('a well-formed item passes through, rounded per field', () => {
	const out = validatePlateEstimate({
		meal_slot: 'lunch',
		items: [
			{
				item_name: 'Grilled chicken breast',
				confidence: 'high',
				calories: 280.6,
				protein_g: 52.34,
				carbs_g: 0,
				fat_g: 6.06,
				sodium_mg: 120.4,
			},
		],
	});
	assert.equal(out.meal_slot, 'lunch');
	assert.equal(out.items.length, 1);
	const [i] = out.items;
	assert.equal(i.item_name, 'Grilled chicken breast');
	assert.equal(i.confidence, 'high');
	assert.equal(i.calories, 281);
	assert.equal(i.protein_g, 52.3);
	assert.equal(i.carbs_g, 0);
	assert.equal(i.fat_g, 6.1);
	assert.equal(i.sodium_mg, 120);
	assert.equal(i.fiber_g, null, 'an unstated nutrient is null, not zero');
});

test('an out-of-range number is clamped to the per-item ceiling', () => {
	const [i] = validatePlateEstimate({ items: [{ item_name: 'Salad', calories: 40000, fat_g: 9999 }] }).items;
	assert.equal(i.calories, PLATE_ITEM_LIMITS.calories.max);
	assert.equal(i.fat_g, PLATE_ITEM_LIMITS.fat_g.max);
});

test('a negative, NaN, infinite or string number is dropped, never floored', () => {
	for (const bad of [-5, Number.NaN, Infinity, '300', null, true]) {
		assert.equal(clampNutrient(bad, 100, 0), null, String(bad));
	}
});

test('an unknown meal slot or confidence is dropped', () => {
	const out = validatePlateEstimate({
		meal_slot: 'brunch',
		items: [{ item_name: 'Toast', confidence: 'certain' }],
	});
	assert.equal(out.meal_slot, null);
	assert.equal(out.items[0].confidence, null);
});

test('an item with no usable name is dropped', () => {
	const out = validatePlateEstimate({ items: [{ calories: 100 }, { item_name: '   ' }, { item_name: 7 }, 'rice'] });
	assert.deepEqual(out.items, []);
});

test('names lose control and bidi characters, collapse whitespace and are capped', () => {
	assert.equal(cleanItemName('Rice\n\twith ‮evil‬ beans'), 'Rice with evil beans');
	assert.equal(cleanItemName('x'.repeat(500))?.length, MAX_ITEM_NAME_CHARS);
});

test('at most eight items are kept', () => {
	const items = Array.from({ length: 12 }, (_, n) => ({ item_name: `Item ${n}` }));
	assert.equal(validatePlateEstimate({ items }).items.length, MAX_PLATE_ITEMS);
});

test('unknown fields never reach the result', () => {
	const [i] = validatePlateEstimate({
		items: [{ item_name: 'Soup', calories: 200, user_id: 'someone-else', is_public: true }],
	}).items;
	assert.equal('user_id' in i, false);
	assert.equal('is_public' in i, false);
});

test('a non-object or missing items list yields an empty estimate', () => {
	for (const raw of [null, 'text', 42, { items: 'many' }]) {
		assert.deepEqual(validatePlateEstimate(raw), { items: [], meal_slot: null });
	}
});
