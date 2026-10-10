// Script-level tests for the bin/ scripts that read the private estate secrets
// repo through bin/lib/estate.sh: sops-init.sh, key-rotate.sh, secret-set.sh
// and aws-preflight.sh.
//
// None of them can run for real in CI — no estate clone, no KMS, no AWS
// session — and that is how their estate handling went stale unnoticed: each
// kept resolving a slot that had been renamed, and the one that should have
// failed loudly, aws-preflight.sh's account pin, degraded to a warning. So they
// are driven here against a fixture estate with `aws`, `terraform`, `sops` and
// `gh` replaced by stubs on PATH. The sops stub records what it was asked to
// do, which is how the seed's `--filename-override` is pinned: sops picks a
// creation rule by the INPUT's name, and the seed from /dev/stdin matched none
// without it (decisions § 1615).
//
// deploy-env.sh is driven only for what it does around the env-stack apply:
// the live-alias snapshot before it and the sync after it, against a stub
// Lambda whose versions and aliases live in files (decisions § 1825).
//
// Not covered: sops's own rule matching and KMS (stubbed), Terraform itself
// (stubbed — every plan but the env stack's reports no changes) and
// disaster-recovery.sh (interactive).
//
// Run: node --test scripts/bin_estate_scripts.test.mjs  (needs bash, awk, jq, git)
// CI:  the `infra-guards` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const PIN = '111111111111';
const ARN_PROD = `arn:aws:kms:us-east-1:${PIN}:key/aaaaaaaa-0000-0000-0000-000000000001`;
const ARN_OLD = `arn:aws:kms:us-east-1:${PIN}:key/aaaaaaaa-0000-0000-0000-000000000002`;
const ARN_TF = `arn:aws:kms:us-east-1:${PIN}:key/bbbbbbbb-0000-0000-0000-000000000003`;
const PLACEHOLDER = 'KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER';

/**
 * The estate config's shape, with the preview rule's value and the slot the
 * rules name as the two things a case varies.
 * @param {string} preview @param {string} [slot]
 */
const config = (preview, slot = 'threkir') => `creation_rules:
  - path_regex: ^flakey/.*\\.sops\\.yaml$
    kms: 'KMS_FLAKEY_ARN_PLACEHOLDER'
  - path_regex: ^${slot}/prod\\.sops\\.yaml$
    kms: '${ARN_PROD}'
  - path_regex: ^${slot}/preview\\.sops\\.yaml$
    kms: '${preview}'
`;

/** @type {Record<string, string>} */
const STUBS = {
	aws: `#!/usr/bin/env bash
case "$*" in
  *"sts get-caller-identity --query Arn"*) echo "arn:aws:sts::$STUB_ACCOUNT:assumed-role/Stub/operator" ;;
  *"sts get-caller-identity --query Account"*) echo "$STUB_ACCOUNT" ;;
  *"sts get-caller-identity"*) echo '{}' ;;
  *"configure get region"*) echo us-east-1 ;;
  *"s3api head-bucket"*) exit 0 ;;
  *"get-bucket-versioning"*) echo Enabled ;;
  "lambda "*)
    fn=""; ver=""; prev=""
    for a in "$@"; do
      [[ "$prev" == --function-name ]] && fn="$a"
      [[ "$prev" == --function-version ]] && ver="$a"
      prev="$a"
    done
    case "$2" in
      list-versions-by-function) [[ -f "$STUB_LAMBDA/$fn.newest" ]] && seq 1 "$(cat "$STUB_LAMBDA/$fn.newest")" ;;
      get-alias) [[ -f "$STUB_LAMBDA/$fn.live" ]] || exit 254; cat "$STUB_LAMBDA/$fn.live" ;;
      update-alias)
        [[ -n "\${STUB_ALIAS_FAIL:-}" ]] && { echo "aws stub: update-alias denied" >&2; exit 254; }
        echo "$ver" > "$STUB_LAMBDA/$fn.live"
        printf 'update-alias %s %s\n' "$fn" "$ver" >> "$STUB_LOG" ;;
      *) echo "aws stub: unhandled: $*" >&2; exit 1 ;;
    esac ;;
  *) echo "aws stub: unhandled: $*" >&2; exit 1 ;;
esac
`,
	terraform: `#!/usr/bin/env bash
case "$*" in
  "output -raw kms_key_arn") echo "$STUB_ARN" ;;
  "version") echo "Terraform v1.15.0" ;;
  "init "*) exit 0 ;;
  "plan "*) case "$PWD" in */infra/envs/*) exit "\${STUB_ENV_PLAN:-2}" ;; *) exit 0 ;; esac ;;
  "apply "*)
    # An apply that changes a function's config publishes a version of it.
    printf 'apply %s\n' "\${PWD##*/infra/}" >> "$STUB_LOG"
    for f in "$STUB_LAMBDA"/*.newest; do [[ -f "$f" ]] && echo $(( $(cat "$f") + 1 )) > "$f"; done ;;
  *) echo "terraform stub: unhandled: $*" >&2; exit 1 ;;
esac
`,
	sops: `#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$STUB_LOG"
out=""; prev=""
for a in "$@"; do [[ "$prev" == --output ]] && out="$a"; prev="$a"; done
case " $* " in *" --encrypt "*) cat >/dev/null; printf 'ENC\\n' > "$out" ;; esac
exit 0
`,
	gh: '#!/usr/bin/env bash\nexit 0\n',
};

/** @param {string} s */
const re = (s) => new RegExp(s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));

/**
 * @typedef {{ status: number | null, out: string }} Run
 * @typedef {{
 *   estate: string,
 *   config: () => string,
 *   sopsCalls: () => string[],
 *   run: (script: string, args?: string[], opts?: { account?: string, input?: string, env?: NodeJS.ProcessEnv }) => Run,
 *   lambda: string,
 * }} Workspace
 */

/**
 * A fixture estate plus a stub PATH, removed after `fn`.
 * @param {{ preview?: string, slot?: string, slotDir?: boolean, files?: Record<string, string> }} shape
 * @param {(ws: Workspace) => void} fn
 */
function withWorkspace(shape, fn) {
	const root = mkdtempSync(join(tmpdir(), 'estate-scripts-'));
	try {
		const stubs = join(root, 'stubs');
		mkdirSync(stubs);
		for (const [name, body] of Object.entries(STUBS)) {
			writeFileSync(join(stubs, name), body);
			chmodSync(join(stubs, name), 0o755);
		}
		const dir = join(root, 'estate');
		mkdirSync(dir);
		writeFileSync(join(dir, '.sops.yaml'), config(shape.preview ?? PLACEHOLDER, shape.slot));
		if (shape.slotDir !== false) {
			mkdirSync(join(dir, 'threkir'));
			writeFileSync(join(dir, 'threkir', 'aws-account'), `${PIN}\n`);
		}
		for (const [rel, body] of Object.entries(shape.files ?? {})) writeFileSync(join(dir, rel), body);
		const log = join(root, 'sops.log');
		writeFileSync(log, '');
		const lambda = join(root, 'lambda');
		mkdirSync(lambda);
		const estate = realpathSync(dir);
		fn({
			estate,
			config: () => readFileSync(join(estate, '.sops.yaml'), 'utf8'),
			sopsCalls: () => readFileSync(log, 'utf8').split('\n').filter(Boolean),
			lambda,
			run: (script, args = [], opts = {}) => {
				/** @type {NodeJS.ProcessEnv} */
				const env = {
					...process.env,
					PATH: `${stubs}:${process.env.PATH}`,
					INFRA_SECRETS_DIR: estate,
					STUB_LOG: log,
					STUB_ARN: ARN_TF,
					STUB_ACCOUNT: opts.account ?? PIN,
					STUB_LAMBDA: lambda,
					...opts.env,
				};
				delete env.EXPECTED_AWS_ACCOUNT;
				const r = spawnSync('bash', [join(REPO_ROOT, 'bin', script), ...args], {
					encoding: 'utf8',
					env,
					input: opts.input ?? '',
				});
				return { status: r.status, out: `${r.stdout}${r.stderr}` };
			},
		});
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

test('sops-init.sh wires an unwired rule and seeds the file under the name sops matches', () => {
	withWorkspace({}, ({ estate, config: current, sopsCalls, run }) => {
		const r = run('sops-init.sh', ['preview']);
		assert.equal(r.status, 0, r.out);
		assert.equal(current(), config(ARN_TF));
		assert.ok(existsSync(join(estate, 'threkir', 'preview.sops.yaml')));
		const seed = sopsCalls().find((c) => c.includes('--encrypt'));
		assert.ok(seed, sopsCalls().join('\n'));
		assert.match(seed, re(`--config ${estate}/.sops.yaml `));
		assert.match(seed, re(`--filename-override ${estate}/threkir/preview.sops.yaml `));
		assert.match(r.out, /Both threkir\/ rules carry a KMS ARN/);
	});
});

test('sops-init.sh leaves a rule already carrying the key, and an existing file, alone', () => {
	withWorkspace({ preview: ARN_TF, files: { 'threkir/preview.sops.yaml': 'ENC\n' } }, ({ config: current, sopsCalls, run }) => {
		const r = run('sops-init.sh', ['preview']);
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, /threkir\/preview\.sops\.yaml rule already carries this ARN — skipping/);
		assert.match(r.out, /already exists — leaving it alone/);
		assert.equal(current(), config(ARN_TF));
		assert.deepEqual(sopsCalls(), []);
	});
});

test('sops-init.sh repoints a rule carrying a different key, and says to rotate', () => {
	withWorkspace({ preview: ARN_OLD, files: { 'threkir/preview.sops.yaml': 'ENC\n' } }, ({ config: current, run }) => {
		const r = run('sops-init.sh', ['preview']);
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, re(`carried a different key (${ARN_OLD}) — repointing it; run bin/key-rotate.sh preview afterwards`));
		assert.equal(current(), config(ARN_TF));
	});
});

test('sops-init.sh refuses rules that name another slot, before writing anything', () => {
	withWorkspace({ slot: 'running' }, ({ estate, config: current, sopsCalls, run }) => {
		const r = run('sops-init.sh', ['preview']);
		assert.equal(r.status, 1, r.out);
		assert.match(r.out, /No creation rule in \S+ governs threkir\/preview\.sops\.yaml/);
		assert.equal(current(), config(PLACEHOLDER, 'running'));
		assert.equal(existsSync(join(estate, 'threkir', 'preview.sops.yaml')), false);
		assert.deepEqual(sopsCalls(), []);
	});
});

test('key-rotate.sh re-encrypts under the key the governing rule names', () => {
	const metadata = `sops:\n    kms:\n        - arn: ${ARN_OLD}\n`;
	withWorkspace({ preview: ARN_TF, files: { 'threkir/preview.sops.yaml': metadata } }, ({ estate, sopsCalls, run }) => {
		const r = run('key-rotate.sh', ['preview']);
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, re(`Encrypted under: ${ARN_OLD}`));
		assert.match(r.out, re(`Target key in .sops.yaml: ${ARN_TF}`));
		const file = `${estate}/threkir/preview.sops.yaml`;
		assert.deepEqual(sopsCalls(), [`updatekeys --config ${estate}/.sops.yaml ${file}`, `-d ${file}`]);
	});
});

test('key-rotate.sh leaves a file already under the target key alone', () => {
	const metadata = `sops:\n    kms:\n        - arn: ${ARN_TF}\n`;
	withWorkspace({ preview: ARN_TF, files: { 'threkir/preview.sops.yaml': metadata } }, ({ sopsCalls, run }) => {
		const r = run('key-rotate.sh', ['preview']);
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, /Already encrypted under the target key — nothing to rotate/);
		assert.deepEqual(sopsCalls(), []);
	});
});

test('key-rotate.sh sends an unwired rule to sops-init.sh, and a missing rule to the slot', () => {
	withWorkspace({ files: { 'threkir/preview.sops.yaml': 'ENC\n' } }, ({ sopsCalls, run }) => {
		const r = run('key-rotate.sh', ['preview']);
		assert.equal(r.status, 1, r.out);
		// A file carrying no ARN used to end the script here in silence, under pipefail.
		assert.match(r.out, /Couldn't read current KMS ARN/);
		assert.match(r.out, re(`holds ${PLACEHOLDER}, not a KMS ARN — run bin/sops-init.sh preview first`));
		assert.deepEqual(sopsCalls(), []);
	});
	withWorkspace({ slot: 'running', files: { 'threkir/preview.sops.yaml': 'ENC\n' } }, ({ run }) => {
		const r = run('key-rotate.sh', ['preview']);
		assert.equal(r.status, 1, r.out);
		assert.match(r.out, /no creation rule in \S+ governs threkir\/preview\.sops\.yaml — check ESTATE_SLUG/);
	});
});

test('secret-set.sh writes into the slot file through the estate config', () => {
	withWorkspace({ preview: ARN_TF, files: { 'threkir/preview.sops.yaml': 'ENC\n' } }, ({ estate, sopsCalls, run }) => {
		const r = run('secret-set.sh', ['preview', 'STUB_KEY'], { input: 'stub-value\n' });
		assert.equal(r.status, 0, r.out);
		assert.deepEqual(sopsCalls(), [`--config ${estate}/.sops.yaml --set ["STUB_KEY"] "stub-value" ${estate}/threkir/preview.sops.yaml`]);
		assert.match(r.out, /git add threkir\/preview\.sops\.yaml && git commit -m 'threkir: rotate STUB_KEY'/);
	});
	withWorkspace({}, ({ run }) => {
		const r = run('secret-set.sh', ['preview', 'STUB_KEY'], { input: 'stub-value' });
		assert.equal(r.status, 1, r.out);
		assert.match(r.out, /threkir\/preview\.sops\.yaml missing — run bin\/sops-init\.sh preview first/);
	});
});

test('aws-preflight.sh passes on the pinned account with both rules wired', () => {
	withWorkspace({ preview: ARN_TF }, ({ run }) => {
		const r = run('aws-preflight.sh');
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, /Account matches the expected pin/);
		assert.match(r.out, /threkir\/prod\.sops\.yaml rule carries its KMS ARN/);
		assert.match(r.out, /threkir\/preview\.sops\.yaml rule carries its KMS ARN/);
	});
});

test('aws-preflight.sh only warns about a rule still holding its placeholder', () => {
	withWorkspace({}, ({ run }) => {
		const r = run('aws-preflight.sh');
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, re(`threkir/preview.sops.yaml rule still holds ${PLACEHOLDER}`));
	});
});

test('aws-preflight.sh hard-fails the wrong account, a missing slot and a missing rule', () => {
	withWorkspace({ preview: ARN_TF }, ({ run }) => {
		const r = run('aws-preflight.sh', [], { account: '222222222222' });
		assert.equal(r.status, 1, r.out);
		assert.match(r.out, re(`WRONG ACCOUNT: authenticated to 222222222222 but expected ${PIN}`));
	});
	withWorkspace({ preview: ARN_TF, slotDir: false }, ({ run }) => {
		const r = run('aws-preflight.sh');
		assert.equal(r.status, 1, r.out);
		assert.match(r.out, /No account pin set/);
		assert.match(r.out, /estate repo has no threkir\/ slot/);
	});
	withWorkspace({ slot: 'running' }, ({ run }) => {
		const r = run('aws-preflight.sh');
		assert.equal(r.status, 1, r.out);
		assert.match(r.out, /no creation rule in the estate \.sops\.yaml governs threkir\/prod\.sops\.yaml/);
		assert.match(r.out, /no creation rule in the estate \.sops\.yaml governs threkir\/preview\.sops\.yaml/);
	});
});

const SYNCED = ['coach', 'share-run', 'share-route', 'share-recap', 'share-badge', 'share-entity', 'generate-route', 'osrm-proxy'];

/**
 * Seeds the stub Lambda: every function at `live` = `newest` = 3, except the
 * ones `overrides` names as [live, newest].
 * @param {string} dir @param {Record<string, [number, number]>} [overrides]
 */
function seedLambdas(dir, overrides = {}) {
	for (const fn of SYNCED) {
		const [live, newest] = overrides[fn] ?? [3, 3];
		writeFileSync(join(dir, `threkir-web-preview-${fn}.live`), `${live}\n`);
		writeFileSync(join(dir, `threkir-web-preview-${fn}.newest`), `${newest}\n`);
	}
}

/** @param {string} dir @param {string} fn */
const liveOf = (dir, fn) => readFileSync(join(dir, `threkir-web-preview-${fn}.live`), 'utf8').trim();

test('deploy-env.sh repoints every live alias the env apply moved past, with no second prompt', () => {
	withWorkspace({}, ({ lambda, sopsCalls, run }) => {
		seedLambdas(lambda);
		// One "y" for the apply prompt and nothing more: a repoint prompt would
		// read EOF, decline, and leave the alias behind.
		const r = run('deploy-env.sh', ['preview', '--skip-preflight'], { input: 'y\n' });
		assert.equal(r.status, 0, r.out);
		assert.ok(sopsCalls().includes('apply envs/preview'), sopsCalls().join('\n'));
		for (const fn of SYNCED) assert.equal(liveOf(lambda, fn), '4', fn);
	});
});

test('deploy-env.sh holds an alias that was already behind before the apply', () => {
	withWorkspace({}, ({ lambda, sopsCalls, run }) => {
		seedLambdas(lambda, { coach: [5, 6] });
		const r = run('deploy-env.sh', ['preview', '--skip-preflight', '--auto-approve']);
		assert.equal(r.status, 0, r.out);
		assert.equal(liveOf(lambda, 'coach'), '5');
		assert.match(r.out, /live was already behind before the apply \(v5, newest v6\)/);
		assert.match(r.out, /1 alias\(es\) held behind/);
		assert.ok(!sopsCalls().some((c) => c.startsWith('update-alias threkir-web-preview-coach ')), sopsCalls().join('\n'));
		assert.equal(liveOf(lambda, 'share-run'), '4');
	});
});

test('deploy-env.sh --plan applies nothing and repoints nothing', () => {
	withWorkspace({}, ({ lambda, sopsCalls, run }) => {
		seedLambdas(lambda, { coach: [3, 4] });
		const r = run('deploy-env.sh', ['preview', '--skip-preflight', '--plan']);
		assert.equal(r.status, 0, r.out);
		assert.deepEqual(sopsCalls(), []);
		assert.equal(liveOf(lambda, 'coach'), '3');
	});
});

test('deploy-env.sh only reports drift when the env stack had nothing to apply', () => {
	withWorkspace({}, ({ lambda, sopsCalls, run }) => {
		seedLambdas(lambda, { coach: [3, 4] });
		const r = run('deploy-env.sh', ['preview', '--skip-preflight', '--auto-approve'], { env: { STUB_ENV_PLAN: '0' } });
		assert.equal(r.status, 0, r.out);
		assert.match(r.out, /report only/);
		assert.match(r.out, /live at v3, newest published is v4/);
		assert.deepEqual(sopsCalls(), []);
		assert.equal(liveOf(lambda, 'coach'), '3');
	});
});

test('deploy-env.sh fails loudly, naming the manual step, when the sync fails after the apply', () => {
	withWorkspace({}, ({ lambda, sopsCalls, run }) => {
		seedLambdas(lambda);
		const r = run('deploy-env.sh', ['preview', '--skip-preflight', '--auto-approve'], { env: { STUB_ALIAS_FAIL: '1' } });
		assert.equal(r.status, 1, r.out);
		assert.ok(sopsCalls().includes('apply envs/preview'), sopsCalls().join('\n'));
		assert.match(r.out, /envs\/preview WAS applied, but repointing the Lambda live aliases failed/);
		assert.match(r.out, /bin\/lambda-alias-sync\.sh preview\n/);
		assert.equal(liveOf(lambda, 'coach'), '3');
	});
});
