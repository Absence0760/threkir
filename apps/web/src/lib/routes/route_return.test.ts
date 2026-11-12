import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newRouteHref, savedRouteDestination } from './route_return';

test('newRouteHref encodes the return path as one query value', () => {
	assert.equal(newRouteHref('/runs/new'), '/routes/new?return=%2Fruns%2Fnew');
	assert.equal(newRouteHref('/runs/new?a=1&b=2'), '/routes/new?return=%2Fruns%2Fnew%3Fa%3D1%26b%3D2');
});

test('a same-origin return gets the saved route id appended', () => {
	assert.equal(savedRouteDestination('/runs/new', 'r1'), '/runs/new?route=r1');
	assert.equal(savedRouteDestination('/runs/new?x=1', 'r1'), '/runs/new?x=1&route=r1');
	assert.equal(savedRouteDestination('/runs/new?route=old#f', 'r1'), '/runs/new?route=r1#f');
});

test('round trip: the href the editor builds yields a destination back on it', () => {
	const href = newRouteHref('/runs/new');
	const raw = new URL(href, 'https://x.invalid').searchParams.get('return');
	assert.equal(savedRouteDestination(raw, 'abc'), '/runs/new?route=abc');
});

test('no return target means no redirect', () => {
	assert.equal(savedRouteDestination(null, 'r1'), null);
	assert.equal(savedRouteDestination(undefined, 'r1'), null);
	assert.equal(savedRouteDestination('', 'r1'), null);
});

test('off-origin and protocol-relative targets are refused, not followed', () => {
	for (const raw of [
		'https://evil.example/runs/new',
		'//evil.example',
		'/\\evil.example',
		'/\\/evil.example',
		'/.//evil.example',
		'javascript:alert(1)',
		'runs/new',
	]) {
		assert.equal(savedRouteDestination(raw, 'r1'), null, raw);
	}
});
