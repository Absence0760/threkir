import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

// Where supabase-js comes from, per module, and why it differs by one function.
//
// Every stack-using CI job's setup polls clip-public-track for a 405 to prove
// the edge runtime is really serving, so THAT worker has to boot without
// reaching registry.npmjs.org: when the fetch fails the worker never starts,
// the probe hangs to its timeout, and the job dies before one test runs.
// Two things on its graph would make the runtime fetch from npm at boot, both
// measured with `edge-runtime start --main-service` under
// `--add-host registry.npmjs.org:127.0.0.1`:
//   - esm.sh's default (denonext) build of supabase-js, which imports
//     `node:buffer` / `node:process` and makes the runtime resolve their types
//     from npm. `?target=deno` is the only variant that avoids it (`?no-dts`
//     does not, and no released edge-runtime image does either). § 699.
//   - any `npm:` specifier at all, which the runtime fetches outright. § 2341.
// A type-only import re-arms either one, so this walks the probe function's
// WHOLE local module graph rather than a hand-written list of the files that
// happen to import supabase-js today; a list went stale once already, when
// `rate_limit.ts` moved its client type behind `_shared/database.ts`.
//
// Every OTHER module loads supabase-js from npm. esm.sh rebuilds a package's
// graph itself and its CDN has served two builds of one versioned URL at once
// (`tslib@2.8.1`, which supabase-js pulls in; `get-intrinsic` under Stripe
// before it), which no `deno.lock` pin can match, so the Edge Function lane
// failed on whichever build a cold run was handed (§ 2257, § 2341). The npm
// specifier's version must also be the root package.json's devDependency,
// because `deno check` reads the declarations from the installed package and
// the runtime fetches the specifier: two strings naming one package.
const PROBE_ENTRY = 'clip-public-track/index.ts';

const FUNCTIONS_ROOT = new URL('../', import.meta.url);
const ROOT_PACKAGE_JSON = new URL('../../../../../package.json', import.meta.url);
const THIS_FILE = '_shared/offline_worker_boot_guard.test.ts';

const ESM_SH_SUPABASE_JS = /^https:\/\/esm\.sh\/@supabase\/supabase-js@([^?/]+)/;
const NPM_SUPABASE_JS = /^npm:@supabase\/supabase-js@([0-9][^/]*)$/;
const ANY_SUPABASE_JS = /@supabase\/supabase-js@/;

/// Every `from '…'` / bare `import '…'` specifier in one module's source.
function specifiersOf(src: string): string[] {
	return [
		...src.matchAll(/(?:^|\n)\s*(?:import|export)[\s\S]*?from\s*['"]([^'"]+)['"]/g),
		...src.matchAll(/(?:^|\n)\s*import\s*['"]([^'"]+)['"]/g),
	].map((m) => m[1]);
}

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

type Edge = { module: string; specifier: string };

/// The probe function's local module graph, and every non-relative specifier
/// a module on it names.
async function probeGraph(): Promise<{ modules: Set<string>; external: Edge[] }> {
	const visited = new Set<string>();
	const queue = [new URL(PROBE_ENTRY, FUNCTIONS_ROOT).href];
	const external: Edge[] = [];
	while (queue.length > 0) {
		const href = queue.pop()!;
		if (visited.has(href)) continue;
		visited.add(href);
		const src = await Deno.readTextFile(new URL(href));
		const rel = href.slice(FUNCTIONS_ROOT.href.length);
		for (const spec of specifiersOf(src)) {
			if (spec.startsWith('./') || spec.startsWith('../')) {
				queue.push(new URL(spec, href).href);
			} else {
				external.push({ module: rel, specifier: spec });
			}
		}
	}
	return { modules: new Set([...visited].map((h) => h.slice(FUNCTIONS_ROOT.href.length))), external };
}

Deno.test("the probe path's whole module graph imports supabase-js at ?target=deno", async () => {
	const { modules, external } = await probeGraph();
	assert(
		modules.size > 1,
		`the walk from ${PROBE_ENTRY} reached only itself — the specifier scan is not ` +
			'seeing this tree\'s relative imports, so it would pass over any graph',
	);
	const supabaseImports = external.filter(({ specifier }) => ANY_SUPABASE_JS.test(specifier));
	assert(
		supabaseImports.length > 0,
		`nothing on the probe path (${modules.size} modules from ${PROBE_ENTRY}) imports ` +
			'supabase-js any more. If that is deliberate, this guard now enforces ' +
			'nothing and should be retargeted at whatever the graph pulls in instead',
	);

	const wrong = supabaseImports.filter(({ specifier }) =>
		!(ESM_SH_SUPABASE_JS.test(specifier) && specifier.includes('target=deno'))
	);
	assertEquals(
		wrong,
		[],
		'these modules on the probe path import supabase-js other than from esm.sh at ' +
			'?target=deno, which re-arms the offline worker-boot failure every CI job\'s setup ' +
			`probe depends on (decisions § 699, § 2341): ${
				wrong.map((w) => `${w.module} -> ${w.specifier}`).join(', ')
			}`,
	);
});

Deno.test('nothing on the probe path imports from npm:, not even a type', async () => {
	const { modules, external } = await probeGraph();
	assert(
		modules.has('_shared/rate_limit.ts'),
		`the walk from ${PROBE_ENTRY} no longer reaches _shared/rate_limit.ts, the shared ` +
			'module this check exists for. If the probe function stopped rate-limiting, ' +
			'retarget this guard; a walk that misses it would pass over any npm: import.',
	);
	const npm = external.filter(({ specifier }) => specifier.startsWith('npm:'));
	assertEquals(
		npm,
		[],
		'these modules on the probe path import from npm:, which the edge runtime fetches ' +
			'from registry.npmjs.org before the worker may boot — a type-only import included ' +
			'— so every CI job\'s setup probe hangs when npm is unreachable (decisions § 2341). ' +
			'Take row types from _shared/database_types.ts, not _shared/database.ts: ' +
			npm.map((n) => `${n.module} -> ${n.specifier}`).join(', '),
	);
});

Deno.test('every module off the probe path loads supabase-js from npm, at the installed version', async () => {
	const { modules } = await probeGraph();
	const files = await tsFiles();
	const pkg = JSON.parse(await Deno.readTextFile(ROOT_PACKAGE_JSON));
	const installed: unknown = pkg.devDependencies?.['@supabase/supabase-js'];

	const npmVersions = new Set<string>();
	const offenders: string[] = [];
	for (const file of files) {
		if (file === THIS_FILE || modules.has(file)) continue;
		const src = await Deno.readTextFile(new URL(file, FUNCTIONS_ROOT));
		for (const spec of specifiersOf(src)) {
			if (!ANY_SUPABASE_JS.test(spec)) continue;
			const npm = spec.match(NPM_SUPABASE_JS);
			if (npm) npmVersions.add(npm[1]);
			else offenders.push(`${file} -> ${spec}`);
		}
	}
	assert(
		npmVersions.size > 0,
		'no module off the probe path imports `npm:@supabase/supabase-js@<version>`, so the ' +
			'scan below found nothing to check — it read nothing, or the imports moved.',
	);
	assertEquals(
		offenders,
		[],
		'These modules import supabase-js from somewhere other than npm. esm.sh\'s CDN has ' +
			'served two builds of one versioned URL at once (tslib@2.8.1 under supabase-js), ' +
			'which no deno.lock pin can match, so the Edge Function lane fails on whichever one ' +
			'a cold run is handed (decisions § 2257, § 2341). Only the probe path, ' +
			`${PROBE_ENTRY}'s graph, keeps esm.sh: ${offenders.join(', ')}`,
	);
	assertEquals(
		[...npmVersions],
		[installed],
		'the functions import npm:@supabase/supabase-js at a version the root package.json ' +
			'does not install, so `deno check` types the tier against a different release than ' +
			'it runs. Keep the specifier and the devDependency equal.',
	);
});

Deno.test('the probe path and the npm imports name the same supabase-js release', async () => {
	const { external } = await probeGraph();
	const pkg = JSON.parse(await Deno.readTextFile(ROOT_PACKAGE_JSON));
	const installed: unknown = pkg.devDependencies?.['@supabase/supabase-js'];
	const probeVersions = [
		...new Set(
			external
				.map(({ specifier }) => specifier.match(ESM_SH_SUPABASE_JS)?.[1])
				.filter((v): v is string => v !== undefined),
		),
	];
	assertEquals(
		probeVersions,
		[installed],
		`${PROBE_ENTRY}'s esm.sh supabase-js and the npm one every other function uses have ` +
			'drifted apart. They are two builds of one library on purpose, not two versions; ' +
			'bump them together.',
	);
});
