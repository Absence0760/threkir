#!/usr/bin/env bash
# Usage: local_smtp_compat.sh <cli-version> <config.toml>
#
# config.toml names the Mailpit section `[local_smtp]`, the only name Supabase
# CLI 3.x loads (v3 refuses a config with `[inbucket]`). CLI v2.108.0 added
# `[local_smtp]`; anything older ignores it and publishes Mailpit on the CLI
# defaults 54324-54326, inside the runner's ephemeral port range (incidents 3
# and 5 in start_stack.sh) and away from the 24324/24325 the auth-email
# tests dial. ci.yml pins 2.84.2 on purpose (the EXECUTE-revoke guards are
# measured against its image), so for a CLI older than 2.108.0 this renames
# the section back to `[inbucket]` in the job's own checkout. Keys inside the
# section are the same under both names. A 2.108.0+ CLI is left alone.
set -euo pipefail

ver="${1:?cli version}"
config="${2:?config.toml path}"
FIRST_WITH_LOCAL_SMTP=2.108.0

oldest="$(printf '%s\n%s\n' "$ver" "$FIRST_WITH_LOCAL_SMTP" | sort -V | head -n1)"
if [ "$oldest" = "$FIRST_WITH_LOCAL_SMTP" ]; then
  echo "Supabase CLI ${ver} reads [local_smtp]; config.toml left as is."
  exit 0
fi

if ! grep -q '^\[local_smtp\]' "$config"; then
  echo "::error::Supabase CLI ${ver} needs [inbucket], but ${config} has no [local_smtp] section to rename."
  exit 1
fi
sed -i.bak 's/^\[local_smtp\]/[inbucket]/' "$config"
rm -f "${config}.bak"
echo "Supabase CLI ${ver} predates [local_smtp] (${FIRST_WITH_LOCAL_SMTP}); renamed it to [inbucket] in ${config} for this job."
