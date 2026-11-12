// Invocation:
//   npx tsx --test src/lib/share/share_return.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { shareReturnFor, type ShareReturnInput } from './share_return';

const ORIGIN = 'https://threkir.com';

function input(overrides: Partial<ShareReturnInput>): ShareReturnInput {
	return {
		loggedIn: true,
		referrer: '',
		origin: ORIGIN,
		historyLength: 2,
		appHref: '/runs/r1',
		...overrides,
	};
}

test('an anonymous visitor is offered nothing', () => {
	assert.equal(shareReturnFor(input({ loggedIn: false, referrer: `${ORIGIN}/feed` })), null);
	assert.equal(shareReturnFor(input({ loggedIn: false })), null);
});

test('a signed-in visitor who came from inside the app goes back', () => {
	assert.deepEqual(shareReturnFor(input({ referrer: `${ORIGIN}/social?tab=feed` })), {
		kind: 'back',
	});
});

test('a same-origin referrer with no history to return to opens the in-app view', () => {
	assert.deepEqual(
		shareReturnFor(input({ referrer: `${ORIGIN}/social`, historyLength: 1 })),
		{ kind: 'open', href: '/runs/r1' },
	);
});

test('an off-site or withheld referrer opens the in-app view, never history.back', () => {
	for (const referrer of ['', 'https://mail.example.com/inbox', 'not a url']) {
		assert.deepEqual(shareReturnFor(input({ referrer })), { kind: 'open', href: '/runs/r1' });
	}
	// A look-alike host is not the same origin.
	assert.deepEqual(
		shareReturnFor(input({ referrer: 'https://threkir.com.evil.example/x' })),
		{ kind: 'open', href: '/runs/r1' },
	);
});

test('an entity with no in-app view falls back to the dashboard', () => {
	assert.deepEqual(shareReturnFor(input({ appHref: null })), {
		kind: 'open',
		href: '/dashboard',
	});
});
