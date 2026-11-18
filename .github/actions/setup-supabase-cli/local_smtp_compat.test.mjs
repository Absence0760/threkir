import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const SCRIPT = fileURLToPath(new URL('./local_smtp_compat.sh', import.meta.url));
const CONFIG = fileURLToPath(new URL('../../../apps/backend/supabase/config.toml', import.meta.url));
const CI = fileURLToPath(new URL('../../workflows/ci.yml', import.meta.url));

function run(/** @type {string} */ version, /** @type {string} */ text) {
	const dir = mkdtempSync(join(tmpdir(), 'local-smtp-'));
	const config = join(dir, 'config.toml');
	writeFileSync(config, text);
	const r = spawnSync('bash', [SCRIPT, version, config], { encoding: 'utf8' });
	return { status: r.status, out: r.stdout + r.stderr, config: readFileSync(config, 'utf8') };
}

const SAMPLE = '[api]\nport = 24321\n\n[local_smtp]\nport = 24324\nsmtp_port = 24325\n';

test('the committed config uses [local_smtp], the only name CLI 3.x loads', () => {
	const text = readFileSync(CONFIG, 'utf8');
	assert.match(text, /^\[local_smtp\]$/m);
	assert.doesNotMatch(text, /^\[inbucket\]/m);
});

test('a CLI older than 2.108.0 gets the section renamed to [inbucket], keys untouched', () => {
	for (const v of ['2.84.2', '2.107.9', '1.200.3']) {
		const r = run(v, SAMPLE);
		assert.equal(r.status, 0, r.out);
		assert.equal(r.config, SAMPLE.replace('[local_smtp]', '[inbucket]'));
	}
});

test('a CLI at or past 2.108.0 leaves the config alone', () => {
	for (const v of ['2.108.0', '2.109.1', '2.119.0', '3.0.0']) {
		const r = run(v, SAMPLE);
		assert.equal(r.status, 0, r.out);
		assert.equal(r.config, SAMPLE);
	}
});

test('an old CLI with no [local_smtp] to rename fails rather than start on default ports', () => {
	const r = run('2.84.2', '[api]\nport = 24321\n');
	assert.equal(r.status, 1);
	assert.match(r.out, /no \[local_smtp\] section/);
});

test('the pin this shim exists for is still below 2.108.0', () => {
	// When every ci.yml pin reaches 2.108.0 the shim is dead code: delete it
	// and its step in action.yml rather than leave it guarding nothing.
	const pins = [...readFileSync(CI, 'utf8').matchAll(/^\s+version: (\d+\.\d+\.\d+)\s*$/gm)].map((m) => m[1]);
	assert.ok(pins.length > 0);
	const old = pins.filter((v) => run(v, SAMPLE).config !== SAMPLE);
	assert.ok(old.length > 0, 'every ci.yml CLI pin reads [local_smtp]; retire local_smtp_compat.sh');
});
