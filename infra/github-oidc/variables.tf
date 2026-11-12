variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "GitHub `<owner>/<repo>` slug allowed to assume the deploy roles. Documentation only since the subject moved to `github_subject_prefix`; kept so the stack still names the repo it trusts in human-readable form."
  type        = string
}

variable "github_subject_prefix" {
  description = <<-EOT
    The literal prefix GitHub puts in the OIDC token's `sub`, WITHOUT the
    trailing `:environment:<name>`.

    This is NOT derivable from `github_repo`. GitHub issues IMMUTABLE SUBJECT
    CLAIMS for this repo, so the subject carries numeric org and repo IDs
    (`repo:<owner>@<owner_id>/<repo>@<repo_id>`) rather than the slug. The IDs
    survive a rename, which is the whole point — and is exactly why the
    name-shaped policy stopped matching when the repo was renamed to threkir.

    Read the current value, never guess it:
      gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
