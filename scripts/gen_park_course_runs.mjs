#!/usr/bin/env node
// Writes the park-course run net's generated artefact (issue #1342 step 5c):
//
//   fixtures/park_course_runs.json
//       synthetic runs over the six Pocahontas courses and what the matcher
//       gives each, from apps/web/src/lib/parks/course_run_fixture.ts. Read by
//       the web, Dart and Edge Function tests.
//
// The generator module is TypeScript that imports the web matcher, so it is
// bundled with apps/web's esbuild in memory, as gen_edge_segment_matcher.mjs
// bundles the matcher. apps/web/src/lib/parks/course_run_fixture.test.ts
// rebuilds the output and fails the web unit suite when it is stale.
//
//   node scripts/gen_park_course_runs.mjs           rewrite it
//   node scripts/gen_park_course_runs.mjs --check   exit 1 if it is stale

import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const FIXTURE = join(REPO_ROOT, 'fixtures', 'park_course_runs.json');
const GENERATOR = join(REPO_ROOT, 'apps', 'web', 'src', 'lib', 'parks', 'course_run_fixture.ts');

/** @param {string} path a path from the repo root */
export function readRepo(path) {
	return readFileSync(join(REPO_ROOT, path), 'utf8');
}

/**
 * @typedef {{ time_seconds: number, started_offset_ms: number, matched_by: string }} Effort
 * @typedef {{ lat: number, lng: number, bearing_deg: number, half_width_m: number, source: string }} Line
 * @typedef {{
 *   courses: { slug: string, start_gate: Line, end_gate: Line }[],
 *   cases: { key: string, course: string, matched: Record<string, Effort>,
 *            extent: { min_lat: number, min_lng: number, max_lat: number, max_lng: number } }[],
 * }} Fixture
 */

/** @returns {Promise<{ buildCourseRunFixture(read: (p: string) => string): Fixture, formatFixture(v: unknown): string }>} */
async function loadGenerator() {
	const require = createRequire(join(REPO_ROOT, 'apps', 'web', 'package.json'));
	/** @type {{ build(o: Record<string, unknown>): Promise<{ outputFiles: { text: string }[] }> }} */
	const esbuild = require('esbuild');
	const result = await esbuild.build({
		entryPoints: [GENERATOR],
		bundle: true,
		format: 'esm',
		platform: 'neutral',
		target: 'es2022',
		write: false,
		legalComments: 'none',
		charset: 'utf8',
		tsconfigRaw: {},
		absWorkingDir: REPO_ROOT,
	});
	const url = `data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`;
	return import(url);
}

/** @returns {Promise<{ fixture: string }>} the file's full contents */
export async function buildOutputs() {
	const gen = await loadGenerator();
	const fixture = gen.buildCourseRunFixture(readRepo);
	return {
		fixture: `${gen.formatFixture(fixture)}\n`,
	};
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	const next = await buildOutputs();
	const stale = [
		[FIXTURE, next.fixture],
	].filter(([path, text]) => {
		try {
			return readFileSync(path, 'utf8') !== text;
		} catch {
			return true;
		}
	});
	if (process.argv.includes('--check')) {
		if (stale.length > 0) {
			for (const [path] of stale) console.error(`${path} is stale.`);
			console.error('Run: pnpm gen:park-course-runs (node scripts/gen_park_course_runs.mjs) and commit it.');
			process.exit(1);
		}
		console.log('park course runs are current');
	} else {
		for (const [path, text] of stale) {
			writeFileSync(path, text);
			console.log(`wrote ${path}`);
		}
		if (stale.length === 0) console.log('park course runs are current');
	}
}
