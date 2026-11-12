// A person's avatar is one component, and every site hands it the image.
//
// `Avatar.svelte` already renders `avatar_url` with the initial as fallback,
// but `url` is optional, so a site that passes only `name` compiles, renders a
// tidy initial, and shows no photo for anyone who uploaded one. That is how the
// club Members row, its join requests and posts, the event board and roster,
// the coaching roster and the DM inbox all came to ignore a field their own
// queries already selected — and the sidebar account button, which drew its
// own initial and never reached the component at all. Nothing in the tree could
// see the difference, because the fallback is the success path's twin.
//
// So the rule is derived over the whole tree rather than listed by surface:
// every <Avatar> passes `url`, and no markup outside the component draws an
// initial by hand. A site that genuinely has no image to pass is named below
// with its reason, and the companion assertion fails when it starts passing
// one, so the list cannot keep a site that no longer earns it.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripSvelteComments } from './core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..');
const COMPONENT = 'lib/components/Avatar.svelte';

/**
 * <Avatar> sites that draw a CLUB, not a person, keyed by file and the `name`
 * expression they pass. A club's logo is its own column and its own upload
 * path, so it is not this guard's business — but a club entry is still held to
 * having no `url`, so it leaves the list the day that path reaches it.
 */
const CLUB_SITES: { file: string; name: string; reason: string }[] = [
	{
		file: 'lib/components/StravaClubsSection.svelte',
		name: 'club.name',
		reason: 'a Strava club, which carries no stored image',
	},
];

/**
 * Markup that draws a person's initial itself. The /u hero renders the stored
 * URL without safeImageSrc's https allow-list, and the avatar-upload e2e reads
 * the freshly uploaded object off it because the local stack serves Storage
 * over http — moving it onto <Avatar> would blank that assertion, so it stays
 * until the spec observes the upload some other way.
 */
const HAND_DRAWN: Record<string, string> = {
	'routes/u/[id]/+page.svelte': 'the profile hero; avatar-upload.spec.ts reads the http upload off it',
};

const HAND_DRAWN_INITIAL = /\binitial\(|display_name\?\.\[0\]/;

function svelteFiles(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) out.push(...svelteFiles(full));
		else if (entry.endsWith('.svelte')) out.push(full);
	}
	return out;
}

const FILES = svelteFiles(SRC).map((full) => ({
	rel: relative(SRC, full).split('\\').join('/'),
	source: stripSvelteComments(readFileSync(full, 'utf-8')),
}));

interface AvatarTag {
	file: string;
	attrs: string;
	name: string | null;
}

function avatarTags(): AvatarTag[] {
	const tags: AvatarTag[] = [];
	for (const { rel, source } of FILES) {
		const opens = source.match(/<Avatar\b/g)?.length ?? 0;
		const closed = [...source.matchAll(/<Avatar\b([\s\S]*?)\/>/g)];
		assert.equal(
			closed.length,
			opens,
			`${rel}: an <Avatar> that is not self-closing cannot be read by this guard`,
		);
		for (const m of closed) {
			const attrs = m[1];
			tags.push({ file: rel, attrs, name: attrs.match(/\bname=\{([^}]*)\}/)?.[1]?.trim() ?? null });
		}
	}
	return tags;
}

const isClubSite = (t: AvatarTag) =>
	CLUB_SITES.some((c) => c.file === t.file && c.name === t.name);

test('every person <Avatar> passes the avatar url', () => {
	const tags = avatarTags();
	assert.ok(tags.length > 20, `found only ${tags.length} <Avatar> sites; the scan is broken`);
	const missing = tags
		.filter((t) => !/\burl=\{/.test(t.attrs) && !isClubSite(t))
		.map((t) => `${t.file} (name={${t.name}})`);
	assert.deepEqual(
		missing,
		[],
		`these <Avatar> sites pass no url, so an uploaded photo never shows:\n  ${missing.join('\n  ')}`,
	);
});

test('every club exemption still names a site with no url', () => {
	const tags = avatarTags();
	for (const c of CLUB_SITES) {
		const sites = tags.filter((t) => t.file === c.file && t.name === c.name);
		assert.ok(sites.length > 0, `${c.file}: no <Avatar name={${c.name}}> left; drop the exemption`);
		for (const t of sites) {
			assert.doesNotMatch(
				t.attrs,
				/\burl=\{/,
				`${c.file}: the club site now passes a url; drop the exemption (${c.reason})`,
			);
		}
	}
});

test('no markup outside Avatar.svelte draws a person initial by hand', () => {
	const offenders = FILES.filter(({ rel }) => rel !== COMPONENT && !(rel in HAND_DRAWN))
		.filter(({ source }) => HAND_DRAWN_INITIAL.test(source))
		.map(({ rel }) => rel);
	assert.deepEqual(
		offenders,
		[],
		`render <Avatar url={…} name={…}> instead of a hand-rolled initial:\n  ${offenders.join('\n  ')}`,
	);
});

test('every hand-drawn exemption still draws its own initial', () => {
	for (const [rel, reason] of Object.entries(HAND_DRAWN)) {
		const file = FILES.find((f) => f.rel === rel);
		assert.ok(file, `${rel} is gone; drop the exemption`);
		assert.match(
			file.source,
			HAND_DRAWN_INITIAL,
			`${rel} no longer draws an initial by hand; drop the exemption (${reason})`,
		);
	}
});
