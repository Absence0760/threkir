import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { viteBin, viteCommand } from './vite-command';

const E2E_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const CONFIGS = readdirSync(E2E_ROOT).filter((f) => /^playwright(\.[\w-]+)?\.config\.ts$/.test(f));

/** A webServer command run through one of these escapes Playwright's teardown kill. */
const WRAPPER = /(^|[`\s;&|(])(pnpm|npm|npx|yarn|pnpx|bunx?)\s/;

test('viteBin resolves to vite’s own bin script', () => {
	const bin = viteBin();
	assert.ok(existsSync(bin), `${bin} does not exist`);
	assert.match(bin, /[/\\]vite[/\\]bin[/\\]vite\.js$/);
	assert.equal(viteCommand('dev --port 1'), `node ${JSON.stringify(bin)} dev --port 1`);
});

test('the lane configs are found', () => {
	assert.ok(CONFIGS.includes('playwright.config.ts'));
	assert.ok(CONFIGS.length >= 6, `only found ${CONFIGS.join(', ')}`);
});

for (const config of CONFIGS) {
	test(`${config}: no webServer command goes through a package-manager wrapper`, () => {
		const commands = [...readFileSync(join(E2E_ROOT, config), 'utf8').matchAll(/^\s*command:\s*(.+),\s*$/gm)].map(
			(m) => m[1]
		);
		assert.ok(commands.length > 0, `${config} has no webServer command`);
		for (const command of commands) {
			assert.doesNotMatch(
				command,
				WRAPPER,
				`${config}: ${command} — run the binary directly (viteCommand), or vite outlives the run (fixtures/vite-command.ts)`
			);
		}
	});
}
