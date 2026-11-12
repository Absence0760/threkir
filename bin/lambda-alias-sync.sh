#!/usr/bin/env bash
#
# lambda-alias-sync.sh — repoint each web Lambda's `live` alias to its
# newest published version.
#
# Why this exists: the `live` aliases are CI-owned (Terraform holds
# `ignore_changes = [function_version]`; release-web.yml repoints them
# on every code deploy), but an env-only `terraform apply` — a secret
# rotation, a new engine URL — publishes a fresh version and leaves the
# alias behind. The Function URLs target the alias, so the rotated env
# never reaches the serving path: the alias keeps serving the old
# version's frozen env snapshot (issue #590 defect 2 — the 2026-07-21
# key swap published v12 while `live` kept serving v11's disabled key;
# again 2026-10-10, when coach served v33 with no secret bag after v34).
#
# bin/deploy-env.sh (so deploy-preview / deploy-prod) runs this itself
# around the infra/envs/<env> apply: `--snapshot` before it, `--after-apply`
# after it. Run it by hand only after an apply made outside deploy-env
# (a bare `terraform apply`), or when deploy-env reports it could not.
#
# --after-apply advances only the aliases that were current BEFORE the
# apply. An alias already behind then is a rollback (apps/web/deployment.md
# § Rollback: `live` pinned to an older version because the newest code is
# bad) or an earlier unsynced apply, and the two look identical from here.
# Every version an apply publishes snapshots $LATEST, i.e. the newest code,
# so advancing a rolled-back alias would re-serve the code it was rolled
# back from. Those are held with a warning; a plain run advances them.
#
# Usage:
#   bin/lambda-alias-sync.sh                    # preview, prompt per repoint
#   bin/lambda-alias-sync.sh prod
#   bin/lambda-alias-sync.sh prod --dry-run     # report drift, change nothing
#   bin/lambda-alias-sync.sh prod --auto-approve
#   bin/lambda-alias-sync.sh prod --snapshot F  # record live/newest per function, change nothing
#   bin/lambda-alias-sync.sh prod --after-apply F --auto-approve
#                                               # repoint only aliases F recorded as current

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ENV_NAME="${1:-preview}"
case "$ENV_NAME" in
	preview|prod) ;;
	*) fatal "Unknown env: $ENV_NAME (expected preview or prod)" ;;
esac
shift || true

DRY_RUN=0
AUTO=0
SNAPSHOT_OUT=""
SNAPSHOT_IN=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run)      DRY_RUN=1; shift ;;
		--auto-approve) AUTO=1; shift ;;
		--snapshot)     SNAPSHOT_OUT="${2:?--snapshot needs a file}"; shift 2 ;;
		--after-apply)  SNAPSHOT_IN="${2:?--after-apply needs a file}"; shift 2 ;;
		*)              fatal "Unknown flag: $1" ;;
	esac
done
if [[ -n "$SNAPSHOT_OUT" && -n "$SNAPSHOT_IN" ]]; then
	fatal "--snapshot and --after-apply are separate runs, one either side of the apply"
fi
if [[ -n "$SNAPSHOT_IN" && ! -f "$SNAPSHOT_IN" ]]; then
	fatal "--after-apply: no snapshot at $SNAPSHOT_IN"
fi
# A snapshot is a read; it never repoints anything.
[[ -n "$SNAPSHOT_OUT" ]] && DRY_RUN=1 && : >"$SNAPSHOT_OUT"

need_cmd aws
need_aws_auth

# Kept in lockstep with the `aws_lambda_alias` set in
# infra/modules/web-stack/main.tf and the per-function deploy steps in
# .github/workflows/release-web.yml by scripts/check_lambda_alias_sync.mjs,
# which parses all three and fails CI on disagreement in either direction.
# Terraform is the source of truth; add the Lambda there first.
FUNCTIONS=(coach share-run share-route share-recap share-badge share-entity generate-route osrm-proxy)

DRIFTED=0
SKIPPED=0
HELD=0
for fn in "${FUNCTIONS[@]}"; do
	NAME="threkir-web-${ENV_NAME}-${fn}"
	step "$NAME"

	NEWEST=$(aws lambda list-versions-by-function \
		--function-name "$NAME" \
		--query 'Versions[?Version!=`$LATEST`].[Version]' \
		--output text | sort -n | tail -1)
	if [[ -z "$NEWEST" || "$NEWEST" == "None" ]]; then
		warn "no published versions — skipping (function not deployed yet?)"
		[[ -n "$SNAPSHOT_OUT" ]] && printf '%s - -\n' "$fn" >>"$SNAPSHOT_OUT"
		SKIPPED=$((SKIPPED + 1))
		continue
	fi

	# `|| true` because a bare command substitution carries its own exit
	# status into the assignment, and `set -e` then kills the whole sweep —
	# so one function whose `live` alias does not exist yet (deployed, but
	# no terraform apply) would silently take every function after it in the
	# array down with it, with nothing in the output saying so. The
	# published-versions branch above already treats "not ready" as a skip;
	# these two disagreeing about it is what made the failure invisible.
	CURRENT=$(aws lambda get-alias \
		--function-name "$NAME" \
		--name live \
		--query FunctionVersion \
		--output text 2>/dev/null || true)
	if [[ -z "$CURRENT" || "$CURRENT" == "None" ]]; then
		warn "no live alias — skipping (terraform apply not run for this function?)"
		[[ -n "$SNAPSHOT_OUT" ]] && printf '%s - %s\n' "$fn" "$NEWEST" >>"$SNAPSHOT_OUT"
		SKIPPED=$((SKIPPED + 1))
		continue
	fi
	[[ -n "$SNAPSHOT_OUT" ]] && printf '%s %s %s\n' "$fn" "$CURRENT" "$NEWEST" >>"$SNAPSHOT_OUT"

	if [[ "$CURRENT" == "$NEWEST" ]]; then
		ok "live already at v$CURRENT"
		continue
	fi

	if [[ -n "$SNAPSHOT_IN" ]]; then
		# A function the snapshot never saw deployed (or created by this very
		# apply) has no rollback to protect, so only a recorded behind-alias
		# is held.
		WAS_LIVE="" WAS_NEWEST=""
		read -r _ WAS_LIVE WAS_NEWEST < <(awk -v f="$fn" '$1 == f' "$SNAPSHOT_IN") || true
		if [[ -n "${WAS_LIVE:-}" && "$WAS_LIVE" != "-" && "$WAS_LIVE" != "$WAS_NEWEST" ]]; then
			warn "live was already behind before the apply (v$WAS_LIVE, newest v$WAS_NEWEST) — a rollback or an earlier unsynced apply; holding at v$CURRENT (newest now v$NEWEST)"
			HELD=$((HELD + 1))
			continue
		fi
	fi

	DRIFTED=1
	warn "live at v$CURRENT, newest published is v$NEWEST"
	if [[ $DRY_RUN -eq 1 ]]; then
		continue
	fi
	if [[ $AUTO -ne 1 ]] && ! confirm "Repoint ${NAME}:live v$CURRENT -> v$NEWEST?"; then
		log "skipped"
		continue
	fi
	aws lambda update-alias \
		--function-name "$NAME" \
		--name live \
		--function-version "$NEWEST" >/dev/null
	ok "live -> v$NEWEST"
done

if [[ $DRIFTED -eq 0 && $SKIPPED -eq 0 && $HELD -eq 0 ]]; then
	step "All ${#FUNCTIONS[@]} aliases already current for $ENV_NAME"
elif [[ $DRIFTED -eq 0 ]]; then
	step "$((${#FUNCTIONS[@]} - SKIPPED - HELD)) alias(es) current for $ENV_NAME, $SKIPPED skipped, $HELD held"
elif [[ -n "$SNAPSHOT_OUT" ]]; then
	step "Snapshot written — drift reported above, nothing changed"
elif [[ $DRY_RUN -eq 1 ]]; then
	step "Dry run — drift reported above, nothing changed"
fi
if [[ $HELD -gt 0 ]]; then
	warn "$HELD alias(es) held behind (see above). If that is not a deliberate rollback, advance them with: bin/lambda-alias-sync.sh $ENV_NAME"
fi
if [[ $SKIPPED -gt 0 ]]; then
	# Named explicitly: a skipped function is one this run did NOT verify, and
	# a sweep that checked 6 of 8 must not read like a clean sweep.
	warn "$SKIPPED function(s) skipped — not verified this run"
fi
