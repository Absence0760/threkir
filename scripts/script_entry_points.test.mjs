// A script's "am I the entry point?" test must compare paths, not a URL built
// by hand. `import.meta.url === \`file://${process.argv[1]}\`` misses whenever
// the path needs URL-encoding (a space, a `%`, a non-ASCII byte) or reaches the
// file through a symlink, and the script then exits 0 having done nothing: a
// CI step that runs a guard that way passes vacuously. The form that holds is
// `realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const HAND_BUILT_URL = /import\.meta\.url\s*===\s*`file:\/\/\$\{process\.argv\[1\]\}`|`file:\/\/\$\{process\.argv\[1\]\}`\s*===\s*import\.meta\.url/;

test('no tracked script decides it is the entry point by building a file:// URL by hand', () => {
	const files = execFileSync('git', ['ls-files', '-z', '--', '*.mjs', '*.js', '*.ts'], { cwd: REPO_ROOT, encoding: 'utf8' })
		.split('\0')
		.filter(Boolean)
		.filter((f) => f !== 'scripts/script_entry_points.test.mjs');
	const offenders = files.filter((f) => HAND_BUILT_URL.test(readFileSync(join(REPO_ROOT, f), 'utf8')));
	assert.deepEqual(offenders, [], 'use realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)');
});

test('a script reached through a path that needs URL-encoding and a symlink still runs', () => {
	const dir = mkdtempSync(join(tmpdir(), 'entry point %20 é-'));
	try {
		const link = join(dir, 'link to sync.mjs');
		symlinkSync(join(REPO_ROOT, 'scripts', 'official', 'sync.mjs'), link);
		const r = spawnSync(process.execPath, [link, '--dry-run'], { encoding: 'utf8' });
		assert.equal(r.status, 0, r.stderr);
		assert.match(r.stdout, /\S/, 'the dry run printed nothing: the entry-point check did not fire');
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
