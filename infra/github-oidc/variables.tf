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

variable "github_extra_subject_prefixes" {
  description = <<-EOT
    Additional OIDC `sub` prefixes the deploy roles trust alongside
    `github_subject_prefix`, same shape and same exact match (StringEquals).

    Exists for the move of this repo into a GitHub organization
    (jaredhoward-dev/project-mgmt#14): a repo transferred after 2026-07-15 issues
    `repo:<org>@<org_id>/<repo>@<repo_id>`, so before the transfer the roles
    must trust both the current and the post-transfer prefix. Empty outside a
    migration. Read each value, never guess it:
      gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for p in var.github_extra_subject_prefixes :
      can(regex("^repo:[^/@:]+(@[0-9]+)?/[^/@:]+(@[0-9]+)?$", p))
    ])
    error_message = "Each github_extra_subject_prefixes entry must be repo:<owner>[@<owner_id>]/<repo>[@<repo_id>], with no trailing :environment:<name>."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
