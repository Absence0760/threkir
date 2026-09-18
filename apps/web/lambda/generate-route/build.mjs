// Build the generate-route Lambda zip.
//
// Run from `apps/web/`:   node lambda/generate-route/build.mjs
//
// Output: apps/web/lambda/generate-route/dist/generate-route.zip
//
// esbuild bundles src/index.ts (and the pure $lib/routes/generate/ core it
// imports) into a single index.mjs. The core has no SDK / native deps — it
// only does fetch() to the GraphHopper engine — so the bundle is tiny and
// nothing is marked external.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const distDir = resolve(here, 'dist');

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
	external: [],
	// The release identifies the ARTIFACT, so it is baked in here rather than
	// read from the Lambda env at runtime. Terraform owns `environment`, so
	// CI writing APP_RELEASE there would be reverted by the next apply, and
	// tfvars cannot know the tag. release-web.yml passes APP_RELEASE on this
	// bundle step; a local build leaves it unset and Sentry tags the events
	// `dev`, which is the honest answer for a bundle built off a tag.
	define: {
		'process.env.APP_RELEASE': JSON.stringify(process.env.APP_RELEASE ?? 'dev'),
	},
	minify: true,
	sourcemap: 'linked',
	keepNames: true,
});

writeFileSync(
	resolve(distDir, 'package.json'),
	JSON.stringify({ type: 'module' }, null, 2) + '\n',
);

execSync('zip -qr generate-route.zip index.mjs index.mjs.map package.json', {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'generate-route.zip')}`);
