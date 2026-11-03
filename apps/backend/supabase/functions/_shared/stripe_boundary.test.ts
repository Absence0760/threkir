// The Stripe SDK enters the Edge Function tier through `_shared/stripe.ts`
// alone, as `npm:stripe@<version>`.
//
// Three properties, each one a guard nothing else provides:
//
//   - no module imports Stripe from esm.sh. esm.sh rebuilds stripe's graph
//     itself and its CDN has served two builds of one versioned module at
//     once, which no `deno.lock` pin can match (decisions § 2257). An esm.sh
//     import brings that back.
//   - no module but the boundary names a Stripe specifier, so the
//     compile-time assertion inside `stripe.ts` (which the `deno check` lane
//     runs, and which is the only thing that notices the declarations
//     collapsing to `any`, decisions § 765) covers every Stripe call.
//   - the specifier's version matches the root package.json's `stripe`
//     devDependency. `deno check` reads the declarations from the installed
//     package and the runtime fetches the specifier, so two strings name one
//     package and a mismatch types the tier against a version it does not run.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const FUNCTIONS_ROOT = new URL('../', import.meta.url);
const BOUNDARY = '_shared/stripe.ts';
const ROOT_PACKAGE_JSON = new URL('../../../../../package.json', import.meta.url);

const ESM_SH_STRIPE = /['"](https:\/\/esm\.sh\/stripe@[^'"]+)['"]/g;
const ANY_STRIPE_SPECIFIER = /['"]((?:npm:|https:\/\/esm\.sh\/)stripe@[^'"]+)['"]/g;
const NPM_STRIPE_VERSION = /['"]npm:stripe@([0-9][^/'"]*)['"]/;

async function tsFiles(dir = FUNCTIONS_ROOT, prefix = ''): Promise<string[]> {
	const out: string[] = [];
	for await (const entry of Deno.readDir(dir)) {
		const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
		if (entry.isDirectory) {
			out.push(...(await tsFiles(new URL(`${entry.name}/`, dir), rel)));
		} else if (entry.name.endsWith('.ts')) {
			out.push(rel);
		}
	}
	return out.sort();
}

const read = (file: string) => Deno.readTextFile(new URL(file, FUNCTIONS_ROOT));

Deno.test('no module imports Stripe from esm.sh', async () => {
	// An empty offender list is also what a scan reading nothing returns, so
	// first prove this scan sees the tree's real Stripe import.
	const files = await tsFiles();
	assert(
		files.includes(BOUNDARY) && NPM_STRIPE_VERSION.test(await read(BOUNDARY)),
		`the scan cannot see ${BOUNDARY}'s \`npm:stripe@<version>\` import, so a clean result ` +
			'below would mean it read nothing, not that no module imports from esm.sh.',
	);
	const offenders: string[] = [];
	for (const file of files) {
		if (file === '_shared/stripe_boundary.test.ts') continue;
		for (const [, url] of (await read(file)).matchAll(ESM_SH_STRIPE)) {
			offenders.push(`${file} -> ${url}`);
		}
	}
	assertEquals(
		offenders,
		[],
		'These modules import Stripe from esm.sh, whose CDN has served two builds of one ' +
			'versioned module at once — no deno.lock pin can match both, so the Edge Function ' +
			`lane fails on whichever one a cold run is handed. Import from ${BOUNDARY}: ${
				offenders.join(', ')
			}`,
	);
});

Deno.test('only the shared boundary module names a Stripe specifier', async () => {
	const files = await tsFiles();
	assert(
		files.includes(BOUNDARY),
		`${BOUNDARY} is gone. If the boundary moved, move this guard with it — deleting it ` +
			'leaves nothing watching for a function that imports Stripe directly.',
	);
	assert(
		NPM_STRIPE_VERSION.test(await read(BOUNDARY)),
		`${BOUNDARY} no longer imports \`npm:stripe@<version>\`, so the pattern this guard ` +
			'hunts matches nothing anywhere and it would report a clean tree either way.',
	);
	const offenders: string[] = [];
	for (const file of files) {
		if (file === BOUNDARY || file === '_shared/stripe_boundary.test.ts') continue;
		for (const [, spec] of (await read(file)).matchAll(ANY_STRIPE_SPECIFIER)) {
			offenders.push(`${file} -> ${spec}`);
		}
	}
	assertEquals(
		offenders,
		[],
		`These modules import the Stripe SDK without going through ${BOUNDARY}, which carries ` +
			'the assertion that proves its declarations bound: ' + offenders.join(', '),
	);
});

Deno.test('at least one function still goes through the boundary', async () => {
	const importers = [];
	for (const file of await tsFiles()) {
		if (file === BOUNDARY) continue;
		if (/from\s*'[^']*_shared\/stripe\.ts'/.test(await read(file))) importers.push(file);
	}
	assert(
		importers.length > 0,
		`nothing imports ${BOUNDARY} any more, so the guards above enforce nothing. If the ` +
			'Stripe functions are gone, delete this file and the boundary with them; if they ' +
			'moved, retarget it.',
	);
});

Deno.test('the runtime specifier and the installed declarations name the same Stripe version', async () => {
	const runtimeVersion = (await read(BOUNDARY)).match(NPM_STRIPE_VERSION)?.[1];
	const pkg = JSON.parse(await Deno.readTextFile(ROOT_PACKAGE_JSON));
	const installedVersion: unknown = pkg.devDependencies?.stripe;
	assert(runtimeVersion, `${BOUNDARY} no longer imports \`npm:stripe@<version>\`.`);
	assertEquals(
		installedVersion,
		runtimeVersion,
		`the tier runs stripe@${runtimeVersion} but the root package.json installs ` +
			`stripe@${installedVersion} for \`deno check\` to read the declarations from. Pin both ` +
			'to the same exact version: the params and responses the compiler checks would ' +
			"otherwise be a different version's.",
	);
});

Deno.test('the boundary carries the assertion that proves the declarations bound', async () => {
	const src = await read(BOUNDARY);
	assert(
		/@ts-expect-error[^\n]*\n\s*type StripeDeclarationsBind = MustBeNumber<Stripe\.Account\['id'\]>/
			.test(src),
		`${BOUNDARY} has lost the \`@ts-expect-error\` assertion that proves the declarations ` +
			'bound. It is the only thing that fails when they collapse back to `any`: a ' +
			'positive assertion cannot, because `any` satisfies every constraint.',
	);
});
