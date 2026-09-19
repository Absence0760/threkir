/**
 * The stated minimum-browser floor for `apps/web`, read from the one place it
 * is declared: the `browserslist` array in `apps/web/package.json`.
 *
 * Before this existed the tree had two floors and neither was a decision.
 * Vite's `build.target` defaults to `"baseline-widely-available"`, which in
 * Vite 8 expands to chrome111 / edge111 / firefox114 / safari16.4 / ios16.4
 * and is re-generated on every Vite major — a syntax floor that moves on a
 * dependency bump. And the source shipped `:has()` and container queries with
 * no fallback at all, which is a floor of Firefox 121, four releases above the
 * one the build was compiling for. Nothing reconciled them, and an API with a
 * hand-written fallback (`Intl.Segmenter`) had no floor to be measured against
 * either way (decisions § 1670).
 *
 * So the floor is declared, and everything that needs one derives from it:
 * `vite.config.ts` compiles to it, `src/lib/browser_baseline_guard.test.ts`
 * holds the prose in `conventions.md` to it and fails a feature detect for an
 * API it already guarantees.
 */

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PKG = resolve(HERE, '..', 'package.json');

/**
 * esbuild's engine name for each browserslist key that maps to one.
 *
 * The keys absent from here are Chromium and Gecko forks — they embed one of
 * these engines and esbuild has no separate target for them, so a row naming
 * one constrains which browsers the floor CLAIMS without adding a constraint
 * the compiler can act on. A key in neither table is refused rather than
 * ignored, so a new row cannot silently drop out of the build target.
 *
 * @type {Readonly<Record<string, string>>}
 */
const ESBUILD_ENGINE = Object.freeze({
	chrome: 'chrome',
	edge: 'edge',
	firefox: 'firefox',
	safari: 'safari',
	ios_saf: 'ios',
});

/** @type {ReadonlySet<string>} */
const FORK_OF_A_TARGETED_ENGINE = new Set([
	'and_chr',
	'and_ff',
	'android',
	'op_mob',
	'opera',
	'samsung',
]);

/** @typedef {{ browser: string, version: string }} FloorRow */

/**
 * Every row of the declared floor, in the order `package.json` states it.
 *
 * A row it cannot read is thrown on, naming the row: a floor parsed
 * approximately is a floor nobody stated.
 *
 * @returns {FloorRow[]}
 */
export function browserFloor() {
	const pkg = JSON.parse(readFileSync(PKG, 'utf-8'));
	const rows = pkg.browserslist;
	if (!Array.isArray(rows) || rows.length === 0) {
		throw new Error('apps/web/package.json declares no browserslist — see conventions.md § Web browser baseline');
	}
	return rows.map((row) => {
		const m = /^([a-z_]+) >= (\d+(?:\.\d+)?)$/.exec(String(row));
		if (!m) {
			throw new Error(
				`browserslist row ${JSON.stringify(row)} is not a floor. Every row is "<browser> >= <version>" so the ` +
					'build target and the guard can both read it; a query form would resolve against caniuse data that is ' +
					'not a declared dependency here.',
			);
		}
		const [, browser, version] = m;
		if (!(browser in ESBUILD_ENGINE) && !FORK_OF_A_TARGETED_ENGINE.has(browser)) {
			throw new Error(
				`browserslist row ${JSON.stringify(row)} names a browser this file has no rule for. Add it to ` +
					'ESBUILD_ENGINE (it has its own esbuild target) or to FORK_OF_A_TARGETED_ENGINE (it embeds one).',
			);
		}
		return { browser, version };
	});
}

/**
 * The floor as esbuild target strings, for `build.target`.
 *
 * @returns {string[]}
 */
export function esbuildTarget() {
	return browserFloor()
		.filter((r) => r.browser in ESBUILD_ENGINE)
		.map((r) => `${ESBUILD_ENGINE[r.browser]}${r.version}`);
}
