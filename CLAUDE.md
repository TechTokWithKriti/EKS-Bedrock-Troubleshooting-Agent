# Project instructions

Kubernetes troubleshooting agent on EKS with Bedrock. The original spec lives outside
this repo (`../Scope/BUILD_SPEC.md` and `../Scope/CloudSummitToronto_Demo_Spec.docx`)
and is intentionally not committed here — see the "Deviations from spec" section of
`README.md` for where and why this build diverges from it.

## Before every commit

1. **Review the staged diff for secrets and PII before committing.** Specifically check
   for: AWS access keys/session tokens, account IDs pasted into non-variable context,
   `.tfstate`/`.tfvars` content, kubeconfig contents, IAM role ARNs with real account
   IDs baked into committed files (outputs belong in `terraform output`, not in git),
   API keys, and any personal data (names, emails, IPs) that isn't already public in
   this conversation. If anything looks like a real credential or account-specific
   value that should have been templated instead, stop and fix it before committing —
   do not commit it "to fix later."
2. Run `git status` and `git diff --staged` and actually read the output; don't assume
   the diff matches intent.

## Commit messages

- Succinct. Say what changed and why in one or two lines — no filler, no restating the
  diff.
- Do not mention "Claude", "Anthropic", or AI authorship anywhere in the commit
  message (no `Co-Authored-By` trailer for this repo either).
- Commits happen in batches once a chunk of work is actually ready to review, not
  after every small edit.
