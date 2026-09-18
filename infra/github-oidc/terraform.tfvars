github_repo = "Absence0760/threkir"

# The OIDC `sub` prefix GitHub actually issues. Immutable subject claims are
# on for this repo, so it carries numeric IDs rather than the slug above and
# does NOT change when the repo is renamed. Read it with:
#   gh api repos/Absence0760/threkir/actions/oidc/customization/sub --jq .sub_claim_prefix
github_subject_prefix = "repo:Absence0760@21693150/threkir@1202414286"
