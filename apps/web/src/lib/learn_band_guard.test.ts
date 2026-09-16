import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

// `PublicHeader` is transparent white-on-dark chrome with no variant: it draws
// its wordmark, links and Sign In pill in white and paints no ground of its
// own. That is only legible over a dark ramp, and the `solid` variant that
// used to cover the alternative is gone — deleted once every /learn route
// gained a band and nothing rendered it any more.
//
// So the premise has to be held somewhere. A new public page that mounts the
// header (directly, or by way of LearnPage) and forgets the ramp behind it
// renders white text on a cream page: invisible, and invisible in a way no
// type-checker or contrast guard can see, because the two live in different
// files. This asserts the pairing at the source.

const HERE = dirname(fileURLToPath(import.meta.url));
const ROUTES = join(HERE, '..', 'routes');

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) svelteFiles(full, out);
		else if (entry.endsWith('.svelte')) out.push(full);
	}
	return out;
}

/// A page supplies its own dark ground either with the landing hero's ramp or
/// with a `.learn-band`. Both are full-bleed and both sit at the top of the
/// page, which is the only place the absolutely-positioned bar can land.
const DARK_GROUND = /class="(?:[^"]*\s)?(?:learn-band|hero)(?:\s[^"]*)?"|class="hero"/;

test('every route that mounts the public header paints a dark ground for it', () => {
	const offenders: string[] = [];
	for (const file of svelteFiles(ROUTES)) {
		const source = readFileSync(file, 'utf-8');
		const mountsHeader = /<PublicHeader\b/.test(source);
		const mountsLearnPage = /<LearnPage\b/.test(source);
		if (!mountsHeader && !mountsLearnPage) continue;
		if (!DARK_GROUND.test(source)) {
			offenders.push(relative(ROUTES, file).split('\\').join('/'));
		}
	}
	assert.deepEqual(
		offenders,
		[],
		'PublicHeader is white-on-dark with no variant, so a page that mounts it must ' +
			'open on a dark ramp — the landing hero or a .learn-band. These mount the ' +
			`header over nothing:\n  ${offenders.join('\n  ')}`,
	);
});

test('the scan reaches the routes and can see a real mount', () => {
	// Both halves fail silently: a walk that finds nothing and a matcher that
	// stops matching both report an empty offender list, which is what a clean
	// tree reports too.
	const files = svelteFiles(ROUTES);
	assert.ok(files.length > 20, `the walk reached only ${files.length} route files`);
	const hub = readFileSync(join(ROUTES, 'learn', '+page.svelte'), 'utf-8');
	assert.match(hub, /<LearnPage\b/, 'the hub no longer mounts LearnPage');
	assert.ok(DARK_GROUND.test(hub), 'the dark-ground matcher no longer sees the hub band');
	assert.ok(
		!DARK_GROUND.test('<main class="content"><p>no ramp here</p></main>'),
		'the matcher fires on markup carrying no ramp at all',
	);
});
