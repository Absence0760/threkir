github_repo = "jaredhoward-dev/threkir"

# The OIDC `sub` prefix GitHub actually issues. Immutable subject claims are
# on for this repo, so it carries numeric IDs rather than the slug above and
# does NOT change when the repo is renamed. Read it with:
#   gh api repos/jaredhoward-dev/threkir/actions/oidc/customization/sub --jq .sub_claim_prefix
# Since the move into the jaredhoward-dev org (project-mgmt#14) this is the
# only subject the roles trust; github_extra_subject_prefixes is back to its
# default of [].
github_subject_prefix = "repo:jaredhoward-dev@357177875/threkir@1202414286"
