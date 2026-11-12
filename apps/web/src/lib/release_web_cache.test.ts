// Which Cache-Control each deployed path gets, read off the release's
// `aws s3 sync` filters the way the CLI applies them. A string check on the
// workflow cannot answer that: whether a path is excluded depends on every
// filter after it, and `_app/env.js` sat on the year-long immutable cache
// while each listed exception passed its own string guard (decisions § 2006).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const workflow = readFileSync(resolve('../../.github/workflows/release-web.yml'), 'utf-8');

interface Sync {
	cacheControl: string;
	filters: { kind: 'include' | 'exclude'; glob: string }[];
}

function syncs(): Sync[] {
	const out: Sync[] = [];
	for (const m of workflow.matchAll(/aws s3 sync apps\/web\/build\/ ((?:[^\n]*\\\n)*[^\n]*)/g)) {
		const cacheControl = m[1].match(/--cache-control "([^"]+)"/)?.[1];
		assert.ok(cacheControl, `an aws s3 sync without --cache-control: ${m[0]}`);
		const filters = [...m[1].matchAll(/--(include|exclude) "([^"]+)"/g)].map(([, kind, glob]) => ({
			kind: kind as 'include' | 'exclude',
			glob,
		}));
		out.push({ cacheControl, filters });
	}
	return out;
}

// The CLI's filter semantics: every path starts included, each filter that
// matches overrides the one before, and `*` crosses `/`.
function included(path: string, filters: Sync['filters']): boolean {
	let keep = true;
	for (const { kind, glob } of filters) {
		const re = new RegExp(`^${glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')}$`);
		if (re.test(path)) keep = kind === 'include';
	}
	return keep;
}

function cacheFor(path: string): string[] {
	return syncs()
		.filter((s) => included(path, s.filters))
		.map((s) => s.cacheControl);
}

const IMMUTABLE = 'public,max-age=31536000,immutable';
const SHORT = 'public,max-age=60,must-revalidate';

test('the release has exactly the two syncs this guard reads', () => {
	assert.deepEqual(
		syncs().map((s) => s.cacheControl),
		[IMMUTABLE, SHORT],
	);
});

test('a content-hashed asset is uploaded once, on the immutable cache', () => {
	for (const path of ['_app/immutable/chunks/DhnCDH-N.js', '_app/immutable/assets/0.aOAsb_yj.css']) {
		assert.deepEqual(cacheFor(path), [IMMUTABLE], path);
	}
});

test('every unhashed path is uploaded once, on the short cache', () => {
	for (const path of [
		// The runtime PUBLIC_* flags: pinned, they hid the Coach after it was on.
		'_app/env.js',
		// Kit's new-deploy check.
		'_app/version.json',
		'index.html',
		'200.html',
		'coach.html',
		// The native storefronts read it to decide whether Pro is sellable (decisions § 466).
		'app-capabilities.json',
		// Android App Links (decisions § 1923) and a dated contact.
		'.well-known/assetlinks.json',
		'.well-known/security.txt',
		'robots.txt',
		'sitemap.xml',
		'manifest.webmanifest',
		'sw.js',
		'favicon.png',
	]) {
		assert.deepEqual(cacheFor(path), [SHORT], path);
	}
});

test('apple-app-site-association is left to its own cp', () => {
	assert.deepEqual(cacheFor('.well-known/apple-app-site-association'), []);
});

test('both syncs prune what the build no longer has', () => {
	for (const m of workflow.matchAll(/aws s3 sync apps\/web\/build\/ ((?:[^\n]*\\\n)*[^\n]*)/g)) {
		assert.match(m[1], /--delete/, m[0]);
	}
});
