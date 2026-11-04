import { mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
	SIGN_OUT_SETTLE_TIMEOUT_MS,
	signOutWithScope,
	type AuthSignOutClient,
	type SignOutScope,
} from './sign_out';

function mockAuth(error: { message?: string } | null = null): {
	client: AuthSignOutClient;
	calls: SignOutScope[];
} {
	const calls: SignOutScope[] = [];
	return {
		calls,
		client: {
			async signOut({ scope }) {
				calls.push(scope);
				return { error };
			},
		},
	};
}

test('signOutWithScope forwards the local scope to the auth client', async () => {
	const { client, calls } = mockAuth();
	const err = await signOutWithScope(client, 'local');
	assert.equal(err, null);
	assert.deepEqual(calls, ['local']);
});

test('signOutWithScope forwards the global scope to the auth client', async () => {
	const { client, calls } = mockAuth();
	const err = await signOutWithScope(client, 'global');
	assert.equal(err, null);
	assert.deepEqual(calls, ['global']);
});

test('signOutWithScope returns the provider error rather than throwing', async () => {
	const { client } = mockAuth({ message: 'network down' });
	const err = await signOutWithScope(client, 'global');
	assert.equal(err?.message, 'network down');
});

test('a delete still inside its undo window commits before the session ends', async () => {
	const order: string[] = [];
	let release!: () => void;
	const committing = new Promise<void>((r) => (release = r));
	const client: AuthSignOutClient = {
		async signOut({ scope }) {
			order.push(`signOut:${scope}`);
			return { error: null };
		},
	};
	const done = signOutWithScope(client, 'local', async () => {
		order.push('flush:start');
		await committing;
		order.push('flush:done');
	});
	await Promise.resolve();
	assert.deepEqual(order, ['flush:start']);
	release();
	await done;
	assert.deepEqual(order, ['flush:start', 'flush:done', 'signOut:local']);
});

test('a pending delete that cannot settle never keeps the session open', async () => {
	const scopes: string[] = [];
	const client: AuthSignOutClient = {
		async signOut({ scope }) {
			scopes.push(scope);
			return { error: null };
		},
	};
	const warn = console.error;
	console.error = () => {};
	try {
		const err = await signOutWithScope(client, 'local', async () => {
			throw new Error('restore threw');
		});
		assert.equal(err, null);
	} finally {
		console.error = warn;
	}
	assert.deepEqual(scopes, ['local']);
});

// Reason: the settle had no time limit, so a commit request that never
// answered (a stalled network) kept Sign out spinning with the session still
// open on the device the user was leaving.
test('a pending delete that never settles stops holding the sign-out after the cap', async () => {
	assert.equal(SIGN_OUT_SETTLE_TIMEOUT_MS, 5_000);
	mock.timers.enable({ apis: ['setTimeout'] });
	const warn = console.warn;
	const warned: unknown[] = [];
	console.warn = (...args: unknown[]) => warned.push(args[0]);
	try {
		const { client, calls } = mockAuth();
		const done = signOutWithScope(client, 'local', () => new Promise<void>(() => {}));
		await Promise.resolve();
		mock.timers.tick(SIGN_OUT_SETTLE_TIMEOUT_MS - 1);
		await Promise.resolve();
		assert.deepEqual(calls, []);
		mock.timers.tick(1);
		assert.equal(await done, null);
		assert.deepEqual(calls, ['local']);
		assert.equal(warned.length, 1);
		assert.match(String(warned[0]), /had not settled after 5000 ms/);
	} finally {
		console.warn = warn;
		mock.timers.reset();
	}
});

test('a pending delete that settles quickly signs out at once, with no cap left running', async () => {
	mock.timers.enable({ apis: ['setTimeout'] });
	try {
		const { client, calls } = mockAuth();
		const err = await signOutWithScope(client, 'local', async () => {});
		assert.equal(err, null);
		assert.deepEqual(calls, ['local']);
		// The cap's timer was cleared: running the clock past it fires nothing.
		mock.timers.tick(SIGN_OUT_SETTLE_TIMEOUT_MS * 2);
		assert.deepEqual(calls, ['local']);
	} finally {
		mock.timers.reset();
	}
});

// Source-level guard for the store wiring — auth.svelte.ts uses Svelte $state
// runes (and imports the runes-laden units signal), so it can't execute under
// raw tsx. These assertions pin that the two affordances stay distinct: the
// sidebar's local Sign out passes 'local', and logoutEverywhere() passes
// 'global' AND fails closed (throws) on a revocation error instead of clearing
// the local session and implying success.
const here = dirname(fileURLToPath(import.meta.url));
const store = readFileSync(resolve(here, './auth.svelte.ts'), 'utf8');

test('logout() routes through the local scope', () => {
	const body = store.slice(store.indexOf('async function logout('), store.indexOf('async function logoutEverywhere('));
	assert.match(body, /signOutWithScope\(\s*supabase\.auth\s*,\s*'local'\s*,\s*undoStore\.flush\s*\)/);
	assert.doesNotMatch(body, /signOutWithScope\(\s*supabase\.auth\s*,\s*'global'/);
});

test('logoutEverywhere() routes through the global scope and fails closed', () => {
	const start = store.indexOf('async function logoutEverywhere(');
	assert.ok(start > 0, 'logoutEverywhere must exist on the store');
	const body = store.slice(start, store.indexOf('// Listen for auth state changes'));
	assert.match(body, /signOutWithScope\(\s*supabase\.auth\s*,\s*'global'\s*,\s*undoStore\.flush\s*\)/);
	// The error branch must throw BEFORE the local teardown (user = null),
	// so a failed global revocation can't masquerade as a successful sign-out.
	const throwIdx = body.indexOf('throw');
	const teardownIdx = body.indexOf('user = null');
	assert.ok(throwIdx > 0 && teardownIdx > 0 && throwIdx < teardownIdx,
		'logoutEverywhere must throw on error before clearing local session');
});

test('the store exposes logoutEverywhere alongside logout', () => {
	assert.match(store, /\blogoutEverywhere\b\s*,/);
});

const layout = readFileSync(resolve(here, '../../routes/+layout.svelte'), 'utf8');

test('a session that ends or changes outside our Sign out puts a pending delete back', () => {
	assert.match(layout, /const undoOwnerId = \$derived\(auth\.user\?\.id\);/);
	assert.match(
		layout,
		/\$effect\(\(\) => \{\s*const uid = undoOwnerId;\s*return \(\) => \{\s*if \(uid\) undoStore\.undo\(\);\s*\};\s*\}\);/,
	);
});

test('the undo queue hears a session ended only when it has, not while a profile loads', () => {
	assert.match(layout, /const undoSessionEnded = \$derived\(!auth\.loading && !auth\.loggedIn\);/);
	assert.match(
		layout,
		/\$effect\(\(\) => \{\s*setUndoOwner\(undoOwnerId \?\? \(undoSessionEnded \? null : undefined\)\);\s*\}\);/,
	);
});

test('signing out drops the conversation deletes held for the unread badge', () => {
	assert.match(layout, /if \(!browser \|\| !uid\) \{\s*dmUnreadStore\.clear\(\);\s*dmPendingHides\.clear\(\);/);
});

test('the undo queue is told who is signed in, so a commit failing after a sign-out is not toasted', () => {
	const undo = readFileSync(resolve(here, './undo.svelte.ts'), 'utf8');
	assert.match(undo, /owner: \(\) => ownerId,/);
	assert.match(undo, /export function setUndoOwner\(userId: UndoOwner\): void \{\s*ownerId = userId;/);
});
