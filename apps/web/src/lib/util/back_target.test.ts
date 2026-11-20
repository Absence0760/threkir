import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { BACK_PLACE_KEY, backTargetFrom, isBackTarget, type BackTarget } from './back_target';

const PARK = '/parks/us-va/pocahontas';
const FALLBACK: BackTarget = { href: '/races?show=courses', place: 'races' };

test('backTargetFrom: Races & courses comes back with its show state', () => {
	assert.deepEqual(backTargetFrom('/races?show=courses', PARK, FALLBACK), {
		href: '/races?show=courses',
		place: 'races',
	});
	assert.deepEqual(backTargetFrom('/races', PARK, FALLBACK), { href: '/races', place: 'races' });
});

test('backTargetFrom: the parks index and its search keep their query', () => {
	assert.deepEqual(backTargetFrom('/parks?q=lake', PARK, FALLBACK), { href: '/parks?q=lake', place: 'parks' });
	assert.deepEqual(backTargetFrom('/parks/', PARK, FALLBACK), { href: '/parks', place: 'parks' });
});

test('backTargetFrom: any other in-app page is plain Back to it', () => {
	assert.deepEqual(backTargetFrom('/segments/abc', PARK, FALLBACK), { href: '/segments/abc', place: 'previous' });
	assert.deepEqual(backTargetFrom('/', PARK, FALLBACK), { href: '/', place: 'previous' });
});

test('backTargetFrom: no departure, the page itself or one of its children keeps the fallback', () => {
	assert.equal(backTargetFrom(null, PARK, FALLBACK), FALLBACK);
	assert.equal(backTargetFrom(undefined, PARK, FALLBACK), FALLBACK);
	assert.equal(backTargetFrom('', PARK, FALLBACK), FALLBACK);
	assert.equal(backTargetFrom(`${PARK}?course=5k`, PARK, FALLBACK), FALLBACK);
	assert.equal(backTargetFrom(`${PARK}/5k`, PARK, FALLBACK), FALLBACK);
	assert.equal(backTargetFrom(`${PARK}/`, `${PARK}/`, FALLBACK), FALLBACK);
});

test('backTargetFrom: a sibling whose path merely starts the same is a referrer', () => {
	assert.deepEqual(backTargetFrom(`${PARK}-north`, PARK, FALLBACK), { href: `${PARK}-north`, place: 'previous' });
});

test('backTargetFrom: nothing that could leave the site is a referrer', () => {
	for (const bad of ['https://evil.example/', '//evil.example/x', '/\\evil.example', 'javascript:alert(1)', 'races']) {
		assert.equal(backTargetFrom(bad, PARK, FALLBACK), FALLBACK, bad);
	}
});

test('isBackTarget: reads only a well-formed in-app target back out of history', () => {
	assert.equal(isBackTarget({ href: '/races?show=courses', place: 'races' }), true);
	assert.equal(isBackTarget({ href: '//evil.example', place: 'races' }), false);
	assert.equal(isBackTarget({ href: '/races', place: 'elsewhere' }), false);
	assert.equal(isBackTarget({ href: '/races', place: 'toString' }), false);
	assert.equal(isBackTarget(null), false);
	assert.equal(isBackTarget('/races'), false);
});

test('BACK_PLACE_KEY: every place has a label', () => {
	assert.deepEqual(Object.keys(BACK_PLACE_KEY).sort(), ['parks', 'previous', 'races']);
});
