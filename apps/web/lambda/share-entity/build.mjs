// Build the share-entity Lambda zip.
//
// Run from `apps/web/`:   node lambda/share-entity/build.mjs
//
// Output: apps/web/lambda/share-entity/dist/share-entity.zip
//
// Strategy: esbuild bundles src/index.ts (and everything it imports
// transitively from #lib/*) into a single index.mjs. supabase-js is
// inlined. The /og/challenge card rasterises with @resvg/resvg-js, a
// NATIVE addon esbuild cannot inline, so the loader + its arm64 binary
// are kept external and copied into the zip's node_modules exactly as
// share-badge/build.mjs does (see its header for the arm64 install
// recipe). The SPA shell 200.html is read from apps/web/build/200.html
// (built by `npm run build`) and substituted in as __SPA_SHELL_HTML__.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync, rmSync, writeFileSync, existsSync, readFileSync, cpSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';

import { copyOgFonts, OG_FONT_DIR_NAME } from '../og_fonts_bundle.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..', '..');
const distDir = resolve(here, 'dist');
const spaShellPath = resolve(webRoot, 'build', '200.html');

const RESVG_LOADER = '@resvg/resvg-js';
const RESVG_ARM64 = '@resvg/resvg-js-linux-arm64-gnu';
const RESVG_EXTERNAL = [RESVG_LOADER, RESVG_ARM64];

if (!existsSync(spaShellPath)) {
	console.error(
		`[share-entity build] missing SPA shell at ${spaShellPath}. ` +
			`Run \`npm run build\` (from apps/web/) first so the 200.html shell exists.`,
	);
	process.exit(1);
}

const spaShellHtml = readFileSync(spaShellPath, 'utf-8');

if (existsSync(distDir)) rmSync(distDir, { recursive: true });
mkdirSync(distDir, { recursive: true });

await build({
	entryPoints: [resolve(here, 'src/index.ts')],
	bundle: true,
	platform: 'node',
	// Match the Lambda runtime (`runtime = "nodejs24.x"` in
	// infra/modules/web-stack/main.tf).
	target: 'node24',
	format: 'esm',
	outfile: resolve(distDir, 'index.mjs'),
	// Lambda's managed runtime only ships AWS SDK v3, which we don't use,
	// so supabase-js + #lib helpers get inlined; the native rasteriser is
	// copied into node_modules below.
	external: RESVG_EXTERNAL,
	// Some transitive deps (e.g. inside @supabase/realtime-js) still ship
	// CJS. Provide a `require` in the ESM bundle so they load.
	banner: {
		js: 'import { createRequire as __cr } from "module"; const require = __cr(import.meta.url);',
	},
	// The release identifies the ARTIFACT, so it is baked in here rather than
	// read from the Lambda env at runtime. Terraform owns `environment`, so
	// CI writing APP_RELEASE there would be reverted by the next apply, and
	// tfvars cannot know the tag. release-web.yml passes APP_RELEASE on this
	// bundle step; a local build leaves it unset and Sentry tags the events
	// `dev`, which is the honest answer for a bundle built off a tag.
	define: {
		'process.env.APP_RELEASE': JSON.stringify(process.env.APP_RELEASE ?? 'dev'),
		__SPA_SHELL_HTML__: JSON.stringify(spaShellHtml),
	},
	minify: true,
	sourcemap: 'linked',
	keepNames: true,
});

writeFileSync(
	resolve(distDir, 'package.json'),
	JSON.stringify({ type: 'module' }, null, 2) + '\n',
);

copyResvgPackages();
copyOgFonts(distDir);

execSync(`zip -qr share-entity.zip index.mjs index.mjs.map package.json node_modules ${OG_FONT_DIR_NAME}`, {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'share-entity.zip')}`);

// Same copy as share-badge/build.mjs: the loader require()s the arm64
// `.node` package by name at runtime, so both ship in the zip.
function copyResvgPackages() {
	const req = createRequire(resolve(webRoot, 'package.json'));
	let arm64PkgDir;
	try {
		arm64PkgDir = dirname(req.resolve(`${RESVG_ARM64}/package.json`));
	} catch {
		console.error(
			`[share-entity build] missing ${RESVG_ARM64}. The Lambda runs on arm64, so its ` +
				`native binary must ship in the zip. Recipe: release-web.yml's install step ` +
				`and apps/web/lambda/share-badge/README.md.`,
		);
		process.exit(1);
	}
	const loaderPkgDir = dirname(req.resolve(`${RESVG_LOADER}/package.json`));
	const nm = resolve(distDir, 'node_modules', '@resvg');
	mkdirSync(nm, { recursive: true });
	cpSync(loaderPkgDir, resolve(nm, 'resvg-js'), { recursive: true });
	cpSync(arm64PkgDir, resolve(nm, 'resvg-js-linux-arm64-gnu'), { recursive: true });
}
