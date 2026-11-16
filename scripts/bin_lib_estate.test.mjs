// Unit tests for bin/lib/estate.sh — the estate slot's paths, and the sops
// creation-rule lookup the secrets scripts depend on.
//
// The lookup is the piece that has to be right without ever being exercised in
// CI for real: there is no estate clone, no KMS and no sops on a runner, and
// the scripts that call it only run for real on an operator's machine
// (scripts/bin_estate_scripts.test.mjs drives them with stubs). So its contract is
// pinned here against fixture configs: it picks the rule sops would pick (the
// first whose path_regex matches), it reads the YAML spellings a hand-edited
// config uses, and a rewrite changes one value and nothing else.
//
// Run: node --test scripts/bin_lib_estate.test.mjs
// CI:  the `infra-guards` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const LIB = join(dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'lib');
const PRELUDE = `set -euo pipefail; . "${LIB}/common.sh"; . "${LIB}/estate.sh"; `;

const ARN_PROD = 'arn:aws:kms:us-east-1:111111111111:key/aaaaaaaa-0000-0000-0000-000000000001';
const ARN_KEYSTORE = 'arn:aws:kms:us-east-1:111111111111:key/aaaaaaaa-0000-0000-0000-000000000002';
const ARN_NEW = 'arn:aws:kms:us-east-1:111111111111:key/bbbbbbbb-0000-0000-0000-000000000003';

// The estate config's own shape: a leading project with a placeholder, then
// this project's per-env rules and its keystore rule, with comments between.
const ESTATE = `# SOPS configuration for the shared private secrets repo.
creation_rules:
  - path_regex: ^flakey/.*\\.sops\\.yaml$
    kms: 'KMS_FLAKEY_ARN_PLACEHOLDER'
  # threkir — per-env keys, hence two rules
  - path_regex: ^threkir/prod\\.sops\\.yaml$
    kms: '${ARN_PROD}'
  - path_regex: ^threkir/preview\\.sops\\.yaml$
    kms: 'KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER'
  - path_regex: ^threkir/android-upload-keystore\\.sops\\.yaml$
    kms: '${ARN_KEYSTORE}'
`;

/** @param {string} config */
function estate(config) {
	const dir = mkdtempSync(join(tmpdir(), 'estate-lib-'));
	writeFileSync(join(dir, '.sops.yaml'), config);
	return dir;
}

/**
 * Run `body` with the lib sourced and the estate at `dir`; extra args are $1…
 * @param {string} dir @param {string} body @param {string[]} [args]
 */
function lib(dir, body, args = []) {
	const r = spawnSync('bash', ['-c', PRELUDE + body, 'bash', ...args], {
		encoding: 'utf8',
		env: { ...process.env, INFRA_SECRETS_DIR: dir },
	});
	return { status: r.status, out: r.stdout.trimEnd(), err: r.stderr };
}

/** @param {string} dir @param {string} rel */
const ruleKms = (dir, rel) => lib(dir, 'estate_rule_kms "$1"', [rel]);

/** @param {(dir: string) => void} fn @param {string} [config] */
function withEstate(fn, config = ESTATE) {
	const dir = estate(config);
	try {
		fn(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

test('each file resolves to the rule written for it', () => {
	withEstate((dir) => {
		assert.deepEqual(ruleKms(dir, 'threkir/prod.sops.yaml'), { status: 0, out: ARN_PROD, err: '' });
		assert.equal(ruleKms(dir, 'threkir/preview.sops.yaml').out, 'KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER');
		assert.equal(ruleKms(dir, 'threkir/android-upload-keystore.sops.yaml').out, ARN_KEYSTORE);
		assert.equal(ruleKms(dir, 'flakey/production.sops.yaml').out, 'KMS_FLAKEY_ARN_PLACEHOLDER');
	});
});

test('a path no rule governs fails with nothing printed — the renamed-slot case', () => {
	withEstate((dir) => {
		for (const rel of ['running/prod.sops.yaml', 'threkir/prod.sops.yaml.example', 'threkir/prodXsopsXyaml']) {
			assert.deepEqual(ruleKms(dir, rel), { status: 1, out: '', err: '' }, rel);
		}
	});
});

test('the first matching rule wins, as it does for sops', () => {
	const broadFirst = ESTATE.replace('creation_rules:\n', `creation_rules:\n  - path_regex: ^threkir/.*\\.sops\\.yaml$\n    kms: '${ARN_NEW}'\n`);
	withEstate((dir) => assert.equal(ruleKms(dir, 'threkir/prod.sops.yaml').out, ARN_NEW), broadFirst);

	const catchAllLast = `${ESTATE}  - kms: '${ARN_NEW}'\n`;
	withEstate((dir) => {
		assert.equal(ruleKms(dir, 'threkir/prod.sops.yaml').out, ARN_PROD);
		assert.equal(ruleKms(dir, 'running/prod.sops.yaml').out, ARN_NEW);
	}, catchAllLast);
});

test('the YAML spellings a hand-edited config uses are all read', () => {
	const config = `creation_rules:
- kms: "${ARN_PROD}"
  path_regex: "^threkir/prod\\\\.sops\\\\.yaml$"
-
  path_regex: ^threkir/preview\\.sops\\.yaml$   # per-env
  kms: ${ARN_NEW}   # wired 2026-09-14
`;
	withEstate((dir) => {
		assert.equal(ruleKms(dir, 'threkir/prod.sops.yaml').out, ARN_PROD);
		assert.equal(ruleKms(dir, 'threkir/preview.sops.yaml').out, ARN_NEW);
	}, config);
});

test('keys nested below a rule, and keys after the rules end, are not the rule\'s', () => {
	const config = `creation_rules:
  - path_regex: ^threkir/prod\\.sops\\.yaml$
    key_groups:
      - kms:
          - arn: ${ARN_NEW}
stores:
  - path_regex: ^threkir/preview\\.sops\\.yaml$
    kms: '${ARN_NEW}'
`;
	withEstate((dir) => {
		assert.deepEqual(ruleKms(dir, 'threkir/prod.sops.yaml'), { status: 0, out: '', err: '' });
		assert.equal(ruleKms(dir, 'threkir/preview.sops.yaml').status, 1);
		const before = readFileSync(join(dir, '.sops.yaml'), 'utf8');
		assert.notEqual(lib(dir, 'estate_set_rule_kms "$1" "$2"', ['threkir/prod.sops.yaml', ARN_PROD]).status, 0);
		assert.equal(readFileSync(join(dir, '.sops.yaml'), 'utf8'), before, 'a rule with no kms key must not be rewritten');
	}, config);
});

test('a rewrite changes that one rule\'s value and nothing else, and keeps the mode', () => {
	withEstate((dir) => {
		const file = join(dir, '.sops.yaml');
		chmodSync(file, 0o640);
		assert.equal(lib(dir, 'estate_set_rule_kms "$1" "$2"', ['threkir/preview.sops.yaml', ARN_NEW]).status, 0);
		const before = ESTATE.split('\n');
		const after = readFileSync(file, 'utf8').split('\n');
		const changed = before.flatMap((l, i) => (l === after[i] ? [] : [[l, after[i]]]));
		assert.deepEqual(changed, [["    kms: 'KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER'", `    kms: '${ARN_NEW}'`]]);
		assert.equal(after.length, before.length);
		assert.equal(statSync(file).mode & 0o777, 0o640);
		assert.equal(ruleKms(dir, 'threkir/preview.sops.yaml').out, ARN_NEW);
		assert.equal(ruleKms(dir, 'threkir/prod.sops.yaml').out, ARN_PROD);
	});
});

test('a rewrite of a key on the dash line keeps the dash', () => {
	withEstate((dir) => {
		assert.equal(lib(dir, 'estate_set_rule_kms "$1" "$2"', ['threkir/prod.sops.yaml', ARN_NEW]).status, 0);
		assert.equal(readFileSync(join(dir, '.sops.yaml'), 'utf8'), `creation_rules:\n  - kms: '${ARN_NEW}'\n    path_regex: ^threkir/prod\\.sops\\.yaml$\n`);
	}, `creation_rules:\n  - kms: 'KMS_X_ARN_PLACEHOLDER'\n    path_regex: ^threkir/prod\\.sops\\.yaml$\n`);
});

test('a rewrite for a path no rule governs fails and leaves the file alone', () => {
	withEstate((dir) => {
		assert.notEqual(lib(dir, 'estate_set_rule_kms "$1" "$2"', ['running/preview.sops.yaml', ARN_NEW]).status, 0);
		assert.equal(readFileSync(join(dir, '.sops.yaml'), 'utf8'), ESTATE);
	});
});

test('no config at all is a failed lookup, not an empty success', () => {
	const dir = mkdtempSync(join(tmpdir(), 'estate-lib-'));
	try {
		assert.equal(ruleKms(dir, 'threkir/prod.sops.yaml').status, 1);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('the slot paths derive from one resolved estate directory', () => {
	const root = mkdtempSync(join(tmpdir(), 'estate-lib-'));
	try {
		mkdirSync(join(root, 'sub'));
		mkdirSync(join(root, 'estate'));
		const r = spawnSync('bash', ['-c', `${PRELUDE}printf '%s\\n' "$INFRA_SECRETS_DIR" "$ESTATE_SLOT_DIR" "$SOPS_CONFIG" "$(estate_secrets_rel prod)" "$(estate_secrets_file preview)"`], {
			encoding: 'utf8',
			cwd: root,
			env: { ...process.env, INFRA_SECRETS_DIR: './sub/../estate' },
		});
		const abs = realpathSync(join(root, 'estate'));
		assert.deepEqual(r.stdout.trimEnd().split('\n'), [abs, `${abs}/threkir`, `${abs}/.sops.yaml`, 'threkir/prod.sops.yaml', `${abs}/threkir/preview.sops.yaml`]);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('is_kms_arn accepts a key ARN and nothing shaped like one', () => {
	withEstate((dir) => {
		assert.equal(lib(dir, 'is_kms_arn "$1"', [ARN_PROD]).status, 0);
		for (const v of ['KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER', 'arn:aws:kms:us-east-1:111111111111:alias/threkir-sops', `${ARN_PROD} `, '']) {
			assert.equal(lib(dir, 'is_kms_arn "$1"', [v]).status, 1, JSON.stringify(v));
		}
	});
});

// estate_tfvars_resolve: where an env root's Terraform variables come from once
// the estate's plaintext <env>.tfvars became <env>.tfvars.sops. Driven against
// a fixture env dir and a sops stub that "decrypts" to a marker line.

/**
 * Runs `body` with a fixture estate, an empty env dir and a sops stub on PATH.
 * @param {(ctx: { dir: string, envDir: string, run: (body: string) => ReturnType<typeof lib> }) => void} fn
 */
function withTfvarsFixture(fn) {
	withEstate((dir) => {
		mkdirSync(join(dir, 'threkir'));
		const envDir = join(dir, 'env');
		mkdirSync(envDir);
		const stubs = join(dir, 'stubs');
		mkdirSync(stubs);
		writeFileSync(join(stubs, 'sops'), '#!/usr/bin/env bash\n[[ -n "${STUB_SOPS_FAIL:-}" ]] && exit 128\nprintf \'apex_domain = "example.test"\\n\'\n');
		chmodSync(join(stubs, 'sops'), 0o755);
		fn({ dir, envDir, run: (body) => lib(dir, `PATH="${stubs}:$PATH"; ${body}`) });
	});
}

const SHOW = 'printf "args=%s\\n" "${ESTATE_TFVARS_ARGS[*]-}"; printf "tmp=%s\\n" "$ESTATE_TFVARS_TMPDIR"';

test('estate_tfvars_resolve decrypts the sops copy to a private temp file outside the env dir', () => {
	withTfvarsFixture(({ dir, envDir, run }) => {
		writeFileSync(join(dir, 'threkir', 'prod.tfvars.sops'), 'CIPHERTEXT\n');
		const r = run(`estate_tfvars_resolve prod "${envDir}"; f="\${ESTATE_TFVARS_ARGS[0]#-var-file=}"; ${SHOW}; stat -c 'file=%a dir=%a' "$f" "$ESTATE_TFVARS_TMPDIR" | paste -sd' '; cat "$f"; d="$ESTATE_TFVARS_TMPDIR"; estate_tfvars_cleanup; [[ ! -e "$d" ]] && echo removed`);
		assert.equal(r.status, 0, r.err);
		assert.match(r.out, /^args=-var-file=\S+\/prod\.tfvars$/m);
		assert.ok(!r.out.includes(`args=-var-file=${envDir}`), r.out);
		assert.match(r.out, /file=600 dir=700/);
		assert.match(r.out, /apex_domain = "example\.test"/);
		assert.match(r.out, /^removed$/m);
	});
});

test('estate_tfvars_resolve treats a plaintext terraform.tfvars as the override and decrypts nothing', () => {
	withTfvarsFixture(({ dir, envDir, run }) => {
		writeFileSync(join(dir, 'threkir', 'prod.tfvars.sops'), 'CIPHERTEXT\n');
		writeFileSync(join(envDir, 'terraform.tfvars'), 'apex_domain = "override.test"\n');
		const r = run(`estate_tfvars_resolve prod "${envDir}"; ${SHOW}`);
		assert.equal(r.status, 0, r.err);
		assert.match(r.out, /^args=$/m);
		assert.match(r.out, /^tmp=$/m);
	});
});

test('estate_tfvars_resolve stops on a stale symlink, and on one onto the ciphertext, naming the rm', () => {
	withTfvarsFixture(({ dir, envDir, run }) => {
		writeFileSync(join(dir, 'threkir', 'prod.tfvars.sops'), 'CIPHERTEXT\n');
		symlinkSync(join(dir, 'threkir', 'prod.tfvars'), join(envDir, 'terraform.tfvars'));
		let r = run(`estate_tfvars_resolve prod "${envDir}"`);
		assert.equal(r.status, 1);
		assert.match(r.err, /no longer exists/);
		assert.ok(r.err.includes(`rm '${envDir}/terraform.tfvars'`), r.err);
		rmSync(join(envDir, 'terraform.tfvars'));
		symlinkSync(join(dir, 'threkir', 'prod.tfvars.sops'), join(envDir, 'terraform.tfvars'));
		r = run(`estate_tfvars_resolve prod "${envDir}"`);
		assert.equal(r.status, 1);
		assert.match(r.err, /ciphertext/);
		assert.ok(r.err.includes(`rm '${envDir}/terraform.tfvars'`), r.err);
	});
});

test('estate_tfvars_resolve returns 1 with nothing to use, and leaves no temp dir when the decrypt fails', () => {
	withTfvarsFixture(({ dir, envDir, run }) => {
		let r = run(`estate_tfvars_resolve prod "${envDir}" || echo "rc=$?"; ${SHOW}`);
		assert.match(r.out, /^rc=1$/m);
		assert.match(r.out, /^args=$/m);
		writeFileSync(join(dir, 'threkir', 'prod.tfvars.sops'), 'CIPHERTEXT\n');
		r = run(`export STUB_SOPS_FAIL=1; trap 'printf "tmp=%s\\n" "$ESTATE_TFVARS_TMPDIR"' EXIT; estate_tfvars_resolve prod "${envDir}"`);
		assert.equal(r.status, 1);
		assert.match(r.err, /could not decrypt .*threkir\/prod\.tfvars\.sops/);
		assert.match(r.out, /^tmp=$/m);
	});
});
