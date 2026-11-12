import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * The shell command a Playwright lane's `webServer` uses to run vite.
 *
 * It runs vite's own bin under `node`, never through `pnpm exec`, `pnpm run`
 * or `npx`. Playwright starts `webServer.command` as the leader of a new
 * process group and stops it with `kill(-pgid, SIGKILL)`, then waits for the
 * child's stdio to close before the run may exit. pnpm 12 (the native
 * `pnpm-native` binary) starts the command it wraps in a process group of its
 * own, so that kill takes the shell and pnpm and misses vite: vite is
 * reparented to init, keeps the stdio sockets open, and `playwright test`
 * prints its results and then waits forever. Under `heavy`, which holds the
 * machine-wide lock for the life of the command, that stalled every other job
 * on the workstation (decisions § 2476). CI's pnpm 10 keeps the child in the
 * group, which is why only local runs hung.
 *
 * The path is resolved from vite's own package.json rather than
 * `node_modules/.bin/vite`, which only a pnpm install puts under apps/web.
 */
const WEB_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

export function viteBin(): string {
	const require = createRequire(join(WEB_DIR, 'package.json'));
	const pkgPath = require.resolve('vite/package.json');
	const { bin } = require(pkgPath) as { bin: string | Record<string, string> };
	const rel = typeof bin === 'string' ? bin : bin.vite;
	return join(dirname(pkgPath), rel);
}

export function viteCommand(args: string): string {
	return `node ${JSON.stringify(viteBin())} ${args}`;
}
