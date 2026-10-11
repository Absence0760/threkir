#!/usr/bin/env bash
#
# deploy-env.sh — orchestrated apply of every Terraform stack needed for
# an env (preview | prod), in the right order, idempotently.
#
# This is the engine behind `bin/deploy-preview.sh` and `bin/deploy-prod.sh`
# (thin wrappers that pass the env). Invoke those, or call this directly:
#   bin/deploy-env.sh preview
#   bin/deploy-env.sh prod --plan
#
# Stack order (each depends on the previous one's state):
#   1. infra/bootstrap         (state bucket — once per account, shared)
#   2. infra/dns               (Route 53 + ACM cert — once per apex, shared)
#   3. infra/github-oidc       (deploy roles — once per account, shared)
#   4. infra/envs/<env>        (the actual web stack for this env)
#
# The three shared stacks are idempotent — on a prod deploy after preview
# they show no changes and are skipped. For each stack: terraform init →
# plan → prompt → apply. Skips a stack if `terraform plan` shows no changes.
#
# After an apply of infra/envs/<env> this also repoints the web Lambdas'
# CI-owned `live` aliases (bin/lambda-alias-sync.sh), because the apply
# publishes new versions the Function URLs never serve until the alias
# moves (issue #590 defect 2; again 2026-10-10). Only aliases that were
# current before the apply are advanced — one already behind may be a
# rollback, and is held with a warning. --plan never touches them.
#
# Flags (after the env arg):
#   --plan          plan only, never apply (read-only)
#   --auto-approve  apply without prompting (CI-style)
#   --skip-preflight  skip aws-preflight.sh (don't unless you know why)

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/lib/estate.sh"

if [[ $# -lt 1 ]]; then
	fatal "Usage: bin/deploy-env.sh <preview|prod> [--plan|--auto-approve|--skip-preflight]"
fi
ENV_NAME="$1"
shift
case "$ENV_NAME" in
	preview | prod) ;;
	*) fatal "Unknown env: $ENV_NAME (expected preview or prod)" ;;
esac

PLAN_ONLY=0
AUTO_APPROVE=0
SKIP_PREFLIGHT=0

for arg in "$@"; do
	case "$arg" in
		--plan) PLAN_ONLY=1 ;;
		--auto-approve) AUTO_APPROVE=1 ;;
		--skip-preflight) SKIP_PREFLIGHT=1 ;;
		*) fatal "Unknown flag: $arg" ;;
	esac
done

ENV_STACK="infra/envs/$ENV_NAME"

preflight_log=""
alias_snapshot=""
ENV_STACK_APPLIED=0

# Single EXIT trap that cleans up everything we may have created:
#   - the preflight log tmpfile
#   - any per-stack .tfplan files (a mid-chain `terraform apply` failure
#     under set -e leaves these behind; harmless but clutter)
cleanup_on_exit() {
	[[ -n "$preflight_log" && -f "$preflight_log" ]] && rm -f "$preflight_log"
	[[ -n "$alias_snapshot" && -f "$alias_snapshot" ]] && rm -f "$alias_snapshot"
	for stack_dir in infra/bootstrap infra/dns infra/github-oidc "$ENV_STACK"; do
		rm -f "$REPO_ROOT/$stack_dir/.tfplan"
	done
}
trap cleanup_on_exit EXIT

if [[ $SKIP_PREFLIGHT -eq 0 ]]; then
	step "Preflight"
	# Capture output in a tmpfile so a hard-fail can be re-displayed
	# without re-running the AWS API calls.
	preflight_log="$(mktemp)"
	if "$REPO_ROOT/bin/aws-preflight.sh" >"$preflight_log" 2>&1; then
		ok "Preflight passed"
		# Surface the identity + target account even on SUCCESS — the operator
		# must SEE which account they're about to apply to (the box carries
		# mgmt/threkir/disag/jaredhoward profiles). Audit bin-scripts High.
		grep -E 'Account:|Authenticated as|expected pin|No account pin' "$preflight_log" | sed 's/^/      /' || true
	else
		warn "Preflight surfaced issues:"
		cat "$preflight_log" >&2
		fatal "Preflight failed; fix issues above before applying."
	fi
fi

apply_stack() {
	# usage: apply_stack <label> <dir> [-- extra terraform args...]
	# After the optional `--` separator, every remaining arg is passed
	# verbatim to `terraform plan`. The array form preserves quoting
	# even when a value contains spaces.
	local label="$1" dir="$2"
	shift 2
	local -a extra_args=()
	# Defaults the unset case to '' so we don't rely on bash's [[ ]]
	# short-circuit semantics under `set -u` — safer across versions.
	if [[ "${1:-}" == "--" ]]; then
		shift
		extra_args=("$@")
	fi

	step "$label  ($dir)"
	pushd "$REPO_ROOT/$dir" >/dev/null

	# Always init: it's idempotent and fast when nothing changed, and the
	# old "skip if .terraform exists" guard wedged on any leftover partial
	# init (e.g. a `terraform init -backend=false` run for validate) or
	# backend config change. -reconfigure re-syncs backend config without
	# state migration — safe here because every stack's backend is static.
	log "terraform init"
	terraform init -input=false -reconfigure >/dev/null

	# Generate a plan to a file so we apply exactly what we previewed.
	# -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes. Capture the
	# code explicitly (`|| plan_rc=$?` keeps `set -e` from aborting) and branch:
	# an ERRORED plan (1) must be fatal, never fall through to apply a stale
	# .tfplan (e.g. one left by a SIGKILL'd run) under --auto-approve. Audit
	# bin-scripts Medium.
	local plan_file=".tfplan"
	local plan_rc=0
	terraform plan -input=false -detailed-exitcode -out="$plan_file" ${extra_args[@]+"${extra_args[@]}"} || plan_rc=$?
	case "$plan_rc" in
		0)
			ok "$label has no pending changes — skipping apply"
			rm -f "$plan_file"
			popd >/dev/null
			return 0
			;;
		2) : ;; # changes pending — fall through to the apply gate below
		*)
			rm -f "$plan_file"
			popd >/dev/null
			fatal "$label: terraform plan failed (exit $plan_rc) — not applying"
			;;
	esac

	if [[ $PLAN_ONLY -eq 1 ]]; then
		ok "Plan saved to $dir/$plan_file (--plan, not applying)"
		popd >/dev/null
		return 0
	fi

	local proceed=0
	if [[ $AUTO_APPROVE -eq 1 ]]; then
		proceed=1
	else
		if confirm "Apply $label?"; then
			proceed=1
		fi
	fi

	if [[ $proceed -eq 1 ]]; then
		if [[ "$dir" == "$ENV_STACK" ]]; then
			# Taken after the prompt so it is as close to the apply as it can
			# be. A failed read is fatal here, while nothing has changed yet,
			# rather than after the apply, when the sync could not tell a
			# rollback from the apply's own versions.
			alias_snapshot="$(mktemp)"
			"$REPO_ROOT/bin/lambda-alias-sync.sh" "$ENV_NAME" --snapshot "$alias_snapshot" ||
				fatal "$label: could not read the Lambda live aliases before applying — nothing applied"
		fi
		terraform apply -input=false "$plan_file"
		ok "$label applied"
		[[ "$dir" == "$ENV_STACK" ]] && ENV_STACK_APPLIED=1
	else
		warn "$label not applied — stopping the chain so later stacks don't run on stale state"
		popd >/dev/null
		exit 0
	fi

	rm -f "$plan_file"
	popd >/dev/null
}

# Bootstrap takes a -var; the rest read from terraform.tfvars or
# remote state. Args after `--` are passed verbatim to `terraform plan`.
apply_stack "Stack 1/4: bootstrap (state bucket)" "infra/bootstrap" -- -var "state_bucket_name=threkir-tfstate"
apply_stack "Stack 2/4: dns (Route 53 + ACM)" "infra/dns"
apply_stack "Stack 3/4: github-oidc (deploy roles)" "infra/github-oidc"
apply_stack "Stack 4/4: envs/$ENV_NAME (S3 + CloudFront + Lambda + KMS)" "$ENV_STACK"

step "Post-apply"
if [[ $ENV_STACK_APPLIED -eq 1 ]]; then
	# --auto-approve regardless of how this run was invoked: the operator has
	# just approved the apply, the repoint is what makes it take effect, and
	# --after-apply limits it to aliases the apply itself moved past. A second
	# prompt here is a second chance to recreate the incident.
	step "Lambda live aliases"
	if ! "$REPO_ROOT/bin/lambda-alias-sync.sh" "$ENV_NAME" --after-apply "$alias_snapshot" --auto-approve; then
		err "envs/$ENV_NAME WAS applied, but repointing the Lambda live aliases failed —"
		err "the applied Lambda config is not serving yet. Finish it by hand:"
		dim "  bin/lambda-alias-sync.sh $ENV_NAME"
		exit 1
	fi
elif [[ $PLAN_ONLY -eq 0 ]]; then
	# Nothing published by this run, but an earlier apply made outside this
	# script may still have left an alias behind; report it, change nothing.
	step "Lambda live aliases (report only — envs/$ENV_NAME not applied this run)"
	"$REPO_ROOT/bin/lambda-alias-sync.sh" "$ENV_NAME" --dry-run ||
		warn "could not read the live aliases; check them with: bin/lambda-alias-sync.sh $ENV_NAME --dry-run"
fi
if [[ $PLAN_ONLY -eq 0 ]]; then
	# Detect whether the coach secret is already wired. If the env's
	# secrets file exists in the estate repo, the operator has already
	# done phase 2 and this was just a re-apply — point them at the
	# health check. Otherwise walk them through wiring the secret.
	secrets_file="$(estate_secrets_file "$ENV_NAME")"
	if [[ -f "$secrets_file" ]]; then
		ok "Secrets file present ($secrets_file) — the Lambda has the coach key."
		log "Verify the env is healthy (coach should answer 401, not 503):"
		dim "  bin/preview-status.sh $ENV_NAME"
	else
		warn "No coach secret wired yet — the Lambda is up but /api/coach returns 503."
		log "Phase 2 — wire the secret (it lives in the PRIVATE ../infra-secrets repo, never here):"
		if [[ ! -d "$INFRA_SECRETS_DIR" ]]; then
			dim "  git clone git@github.com:Absence0760/infra-secrets.git ../infra-secrets   # clone the estate repo first"
		fi
		dim "  bin/sops-init.sh $ENV_NAME                                   # wire KMS ARN + seed $ESTATE_SLUG/$ENV_NAME.sops.yaml"
		dim "  echo -n \"sk-ant-…\" | bin/secret-set.sh $ENV_NAME ANTHROPIC_API_KEY   # real key via stdin"
		dim "  (cd $INFRA_SECRETS_DIR && git add $ESTATE_SLUG/$ENV_NAME.sops.yaml .sops.yaml && git commit -m '$ESTATE_SLUG: $ENV_NAME secrets')  # commit in the PRIVATE repo"
		dim "  bin/deploy-$ENV_NAME.sh                                       # re-run: idempotent, wires the secret into the Lambda"
		dim "  bin/preview-status.sh $ENV_NAME                              # confirm coach now answers 401, not 503"
	fi
fi
ok "Done"
