import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	SIGNUP_SOURCE_KEY,
	captureFirstTouch,
	firstTouchFrom,
	platformForHost,
	readFirstTouch,
	referrerHost,
	sourceToken,
	type SignupSourceStore,
} from './signup_source.js';

const OWN = 'threkir.com';

function memoryStore(): SignupSourceStore & { map: Map<string, string> } {
	const map = new Map<string, string>();
	return {
		map,
		getItem: (k) => map.get(k) ?? null,
		setItem: (k, v) => void map.set(k, v),
	};
}

test('bio-link UTM parameters are recorded as given', () => {
	assert.deepEqual(
		firstTouchFrom('/', '?utm_source=instagram&utm_medium=social&utm_campaign=bio', 'https://l.instagram.com/', OWN),
		{ source: 'instagram', medium: 'social', campaign: 'bio', referrer_host: 'l.instagram.com' },
	);
});

test('UTM wins over the referrer, and common aliases map to the platform name', () => {
	assert.equal(firstTouchFrom('/', '?utm_source=IG', 'https://t.co/abc', OWN)?.source, 'instagram');
	assert.equal(firstTouchFrom('/', '?utm_source=twitter', null, OWN)?.source, 'x');
	assert.equal(firstTouchFrom('/', '?utm_source=bsky', null, OWN)?.source, 'bluesky');
	assert.equal(firstTouchFrom('/', '?utm_source=newsletter', null, OWN)?.source, 'newsletter');
});

test('every platform the social accounts post on maps from its referrer host', () => {
	const cases: [string, string][] = [
		['https://l.instagram.com/?u=x', 'instagram'],
		['https://www.instagram.com/', 'instagram'],
		['https://l.facebook.com/l.php', 'facebook'],
		['https://m.facebook.com/', 'facebook'],
		['https://www.tiktok.com/', 'tiktok'],
		['https://www.youtube.com/', 'youtube'],
		['https://m.youtube.com/', 'youtube'],
		['https://www.threads.net/', 'threads'],
		['https://www.threads.com/', 'threads'],
		['https://t.co/xyz', 'x'],
		['https://x.com/', 'x'],
		['https://bsky.app/profile/a', 'bluesky'],
		['https://lnkd.in/abc', 'linkedin'],
		['https://www.linkedin.com/', 'linkedin'],
	];
	for (const [ref, platform] of cases) {
		assert.equal(firstTouchFrom('/', '', ref, OWN)?.source, platform, ref);
	}
});

test('a lookalike host is not the platform', () => {
	assert.equal(platformForHost('notinstagram.com'), null);
	assert.equal(platformForHost('instagram.com.evil.example'), null);
	assert.equal(firstTouchFrom('/', '', 'https://notinstagram.com/', OWN)?.source, 'other');
});

test('no referrer and no UTM is direct; an unknown site is other, with its host', () => {
	assert.deepEqual(firstTouchFrom('/', '', '', OWN), {
		source: 'direct',
		medium: null,
		campaign: null,
		referrer_host: null,
	});
	assert.deepEqual(firstTouchFrom('/learn', '', 'https://www.google.com/', OWN), {
		source: 'other',
		medium: null,
		campaign: null,
		referrer_host: 'www.google.com',
	});
});

test('a navigation from this site is not a landing, unless it carries UTM', () => {
	assert.equal(firstTouchFrom('/login', '', 'https://threkir.com/', OWN), null);
	assert.equal(firstTouchFrom('/login', '', 'https://www.threkir.com/', OWN), null);
	assert.deepEqual(firstTouchFrom('/', '?utm_source=x', 'https://threkir.com/', OWN), {
		source: 'x',
		medium: null,
		campaign: null,
		referrer_host: null,
	});
});

test('the auth hops are never a first touch', () => {
	assert.equal(firstTouchFrom('/auth/callback', '', 'https://accounts.google.com/', OWN), null);
	assert.equal(firstTouchFrom('/auth/callback', '?utm_source=x', null, OWN), null);
});

test('UTM values are reduced to what the database accepts', () => {
	assert.equal(sourceToken(' Summer Sale '), 'summer-sale');
	assert.equal(sourceToken('<script>'), 'script');
	assert.equal(sourceToken('---'), null);
	assert.equal(sourceToken(''), null);
	assert.equal(sourceToken(null), null);
	assert.equal(sourceToken('a'.repeat(100))?.length, 64);
});

test('referrerHost reads the host and drops anything unparseable', () => {
	assert.equal(referrerHost('https://L.Instagram.com/x?y=1'), 'l.instagram.com');
	assert.equal(referrerHost('not a url'), null);
	assert.equal(referrerHost(''), null);
	assert.equal(referrerHost(undefined), null);
});

test('the first touch is kept: a later landing in the same tab does not overwrite it', () => {
	const s = memoryStore();
	captureFirstTouch(s, '/', '?utm_source=tiktok', null, OWN);
	captureFirstTouch(s, '/', '', 'https://t.co/x', OWN);
	assert.equal(readFirstTouch(s)?.source, 'tiktok');
});

test('an internal navigation stores nothing, so the next real landing is still first', () => {
	const s = memoryStore();
	captureFirstTouch(s, '/login', '', 'https://threkir.com/', OWN);
	assert.equal(s.map.size, 0);
	captureFirstTouch(s, '/', '', 'https://bsky.app/', OWN);
	assert.equal(readFirstTouch(s)?.source, 'bluesky');
});

test('readFirstTouch revalidates what it finds and survives a refusing store', () => {
	const s = memoryStore();
	s.map.set(SIGNUP_SOURCE_KEY, JSON.stringify({ source: 'x', medium: 'BAD VALUE', campaign: 3, referrer_host: 'a b' }));
	assert.deepEqual(readFirstTouch(s), { source: 'x', medium: null, campaign: null, referrer_host: null });
	s.map.set(SIGNUP_SOURCE_KEY, JSON.stringify({ source: '<b>' }));
	assert.equal(readFirstTouch(s), null);
	s.map.set(SIGNUP_SOURCE_KEY, '{not json');
	assert.equal(readFirstTouch(s), null);
	const refusing: SignupSourceStore = {
		getItem: () => {
			throw new Error('denied');
		},
		setItem: () => {
			throw new Error('denied');
		},
	};
	assert.doesNotThrow(() => captureFirstTouch(refusing, '/', '', null, OWN));
	assert.equal(readFirstTouch(refusing), null);
	assert.equal(readFirstTouch(null), null);
});
