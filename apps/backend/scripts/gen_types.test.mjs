// Run: node --test scripts/gen_types.test.mjs   (from apps/backend)

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { pinnedCliVersion, stripCliNoise } from './gen_types.mjs';

const CI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '.github', 'workflows', 'ci.yml');

test('pinnedCliVersion reads the one version every setup-supabase-cli step names', () => {
	const yml = `
      - uses: ./.github/actions/setup-supabase-cli
        id: supabase_cli
        with:
          version: 2.84.2
      - uses: ./.github/actions/setup-supabase-cli
        with:
          version: '2.84.2'
`;
	assert.equal(pinnedCliVersion(yml), '2.84.2');
});

test('pinnedCliVersion refuses no pin and two pins', () => {
	assert.throws(() => pinnedCliVersion('jobs: {}'), /no CLI versions/);
	const two = `
      - uses: ./.github/actions/setup-supabase-cli
        with:
          version: 2.84.2
      - uses: ./.github/actions/setup-supabase-cli
        with:
          version: 3.2.0
`;
	assert.throws(() => pinnedCliVersion(two), /several CLI versions \(2\.84\.2, 3\.2\.0\)/);
});

test('the real ci.yml names exactly one Supabase CLI pin', () => {
	assert.match(pinnedCliVersion(fs.readFileSync(CI, 'utf8')), /^\d+\.\d+\.\d+$/);
});

test('stripCliNoise drops the connection line and error records, keeps the types', () => {
	assert.equal(
		stripCliNoise('Connecting to db 5432\nexport type Json = string\n{"_tag":"Error","x":1}\n'),
		'export type Json = string\n',
	);
});
