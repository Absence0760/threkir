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
/// page, which is where the bar sits transparent before anything scrolls.
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

// Once the page scrolls, the bar stays on screen over whatever content passes
// under it, so it paints its own glass and the ramp above no longer vouches for
// its inks. The worst ground that glass can sit on is white, the lightest
// surface any theme puts on a page, so every ink the bar draws — its own and
// the motion toggle's — is measured over the glass composited on white. The
// alpha and the inks are read from the source, so lightening either fails here.

const HEADER = join(HERE, 'components', 'PublicHeader.svelte');
const TOGGLE = join(HERE, 'components', 'marketing', 'MotionToggle.svelte');

type Rgb = [number, number, number];

function luminance([r, g, b]: Rgb): number {
	const lin = (c: number) => {
		const v = c / 255;
		return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
	};
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function over(fg: Rgb, alpha: number, bg: Rgb): Rgb {
	return fg.map((c, i) => c * alpha + bg[i] * (1 - alpha)) as Rgb;
}

function ratio(a: Rgb, b: Rgb): number {
	const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
	return (hi + 0.05) / (lo + 0.05);
}

function inks(source: string): Array<[Rgb, number, string]> {
	const found: Array<[Rgb, number, string]> = [];
	for (const m of source.matchAll(/(?<![-\w])color:\s*rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/g)) {
		found.push([[+m[1], +m[2], +m[3]], +m[4], m[0]]);
	}
	for (const m of source.matchAll(/(?<![-\w])color:\s*#([0-9a-fA-F]{6})\b/g)) {
		const hex = m[1];
		found.push([[0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16)) as Rgb, 1, m[0]]);
	}
	return found;
}

test('every ink on the scrolled header glass clears AA over the lightest ground', () => {
	const header = readFileSync(HEADER, 'utf-8');
	const block = /\.landing-nav--scrolled\s*\{([^}]*)\}/.exec(header);
	assert.ok(block, 'PublicHeader has no .landing-nav--scrolled rule');
	const glass = /background:\s*rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/.exec(block[1]);
	assert.ok(glass, 'the scrolled header must paint an rgba() glass the guard can read');

	const white: Rgb = [255, 255, 255];
	const ground = over([+glass[1], +glass[2], +glass[3]], +glass[4], white);
	const all = [...inks(header), ...inks(readFileSync(TOGGLE, 'utf-8'))];
	assert.ok(all.length >= 5, `expected the bar's inks, parsed ${all.length}`);

	for (const [rgb, alpha, source] of all) {
		const ink = over(rgb, alpha, ground);
		const r = ratio(ink, ground);
		assert.ok(
			r >= 4.5,
			`\`${source}\` reads ${r.toFixed(3)}:1 on the header glass over white; the bar ` +
				`stays on screen over content, so its glass has to carry AA on its own`,
		);
	}
});
