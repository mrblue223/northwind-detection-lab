# CLAUDE.md — Northwind Detection Lab

Operating rules for Claude Code in this repo. These are hard constraints, not
suggestions. When a rule conflicts with a request, stop and surface the conflict
instead of silently working around it.

## 1. Never touch real Azure without an explicit go-ahead

Never run terraform plan/apply against real Azure, and never run any `az` CLI
command that creates, modifies, or deletes a real Azure resource, role
assignment, or policy - including but not limited to `az group create`, `az vm
create`, `az role assignment create`, `az ad app`/`sp create`, `az keyvault`,
`az resource delete` - without me first explicitly saying "deploy to azure" or
"run apply" or naming the specific az command I want run. Read-only az commands
(`az account show`, `az group list`, `az role assignment list`, etc.) are always
fine without asking, since they can't change anything. When in doubt about
whether a command is read-only or mutating, treat it as mutating and ask first.

- This also covers `make up` / `make plan-all` / `make init` / `make down` /
  `make destroy` and `terraform init` against the remote backend - all gated the
  same way.
- Local, credential-free work is always fine: `terraform fmt`, `terraform
  validate` (offline), reading state-free HCL, TFLint, ansible-lint, gitleaks.

## 2. Validate before every commit

Before creating any commit, for **every stack and role touched by the change**,
run:

- `terraform fmt -recursive` (format the tree)
- `tflint --chdir=<stack>` on each Terraform stack touched
- `ansible-lint ansible/` when any Ansible file changed

Fix the **real** findings. Do not blanket-suppress a rule (`skip_list`,
`# noqa`, `-ignore-rule`) to make a check go green. If a finding genuinely must
be suppressed (false positive, deliberate lab weakness), document the specific
rule, the file, and the reason in `VALIDATION_NOTES.md` in the same commit.

**Commit Terraform lock files.** Every stack's `.terraform.lock.hcl` is committed
to version control (it pins exact provider versions for reproducible `init`
across machines and CI). The lock files are generated naturally as each stack is
`init`-ed; commit each one the first time it appears, and commit the updated lock
whenever a provider version constraint changes. Only `.terraform/` (the provider
cache) is gitignored, never the lock file.

## 3. Ansible AD modules: use `microsoft.ad`, not the removed `win_domain*`

The `ansible.windows.win_domain*` modules (`win_domain`, `win_domain_controller`,
`win_domain_membership`, `win_domain_user`, `win_domain_group`,
`win_domain_group_membership`, `win_domain_ou`) have been **removed** from the
`ansible.windows` collection. Any new or edited AD task must use the current
`microsoft.ad` collection equivalents (e.g. `microsoft.ad.domain`,
`microsoft.ad.domain_controller`, `microsoft.ad.membership`, `microsoft.ad.user`,
`microsoft.ad.group`, `microsoft.ad.ou`).

> Note: all roles (`ad_domain`, `ad_users`, `victim_ws`, `weaknesses`) have been
> migrated to `microsoft.ad`. Keep it that way — never add a new
> `ansible.windows.win_domain*` call. Note also that `win_chocolatey` lives in
> the `chocolatey.chocolatey` collection, and any new collection dependency must
> be added to `ansible/requirements.yml` (CI installs from it before linting).

## 4. Branch + PR workflow — never push to main

- Always work on a feature branch (`git switch -c <name>` off `main`).
- Open changes as a pull request with `gh pr create`.
- **Never** `git push` directly to `main`, and never commit directly on `main`.

## 5. Scan for secrets before every commit

Run `gitleaks detect --source . --verbose` before every commit and resolve any
findings (rotate/remove the secret, or add a justified, scoped allowlist entry)
before committing.

## Security posture (standing principle)

This lab follows security best practices everywhere EXCEPT for a small,
deliberate set of internal AD weaknesses that exist specifically to support the
documented attack chain (phishing → internal AD exploitation). Those are
exactly: R1 (Kerberoastable service account), R2 (over-privileged GRP-IT nested
into Domain Admins), and R8 (SMB/LDAP relay surface enabling
PetitPotam/PrinterBug → NTLM relay → DCSync).

For everything else, the rule is: fix to best practice when the fix is FREE or
near-free (a config flag, a different auth method, a smaller disk size — no new
billable resources). Where a genuine best-practice fix would add real recurring
cost (e.g. Private Endpoints + Private DNS Zones for Key Vault/storage, premium
SKUs, additional always-on resources), do NOT silently suppress it — instead,
accept it explicitly with a risk-register entry that states the specific monthly
cost trade-off and references the project's $20/month budget ceiling (see
COST_NOTES.md). This is a legitimate, realistic business justification for the
pentest report later ("accepted given a defined budget constraint"), not a sign
of sloppy work — but it must be stated, never hidden behind a generic
`#checkov:skip` with no real reasoning.

## Cloud security best practices (standing principle)

All Azure resources must follow least-privilege and defense-in-depth by default:
scope RBAC role assignments to the narrowest resource/resource-group possible,
never to the subscription, unless there is a specific, documented reason (note
it inline if so). Prefer managed identities / OIDC federated credentials over any
long-lived credential or key wherever Azure supports it for that resource type.
Any new secret, key, or credential must go into Key Vault, never into a file,
environment variable committed to the repo, or printed in chat/logs. Any new
network-facing resource defaults to no public inbound access unless the task
explicitly requires it (and if it does, require it to be justified and recorded
in `grc/risk-register.md`, per the existing project pattern). This applies
retroactively: if you notice an existing resource that violates this during
future work, flag it to me rather than silently leaving it or silently fixing it.

---

Enforcement: a `PreToolUse` hook in `.claude/settings.json` blocks `git commit`
(exit code 2) unless `terraform fmt -check`, `tflint`, and `ansible-lint` all
pass. The hook is a backstop, not a substitute for running the full rule-2 /
rule-5 checks yourself.
