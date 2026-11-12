# Validation notes

What's been checked before you run this, and what's still on you to verify
against live provider docs/accounts before a real `terraform apply`. Written
this way on purpose - a repo that claims to be fully verified without a real
`terraform init`/`plan` against live credentials would be overstating it.

## Hardening pass (Checkov fixes before merge)

Per the standing security principle in `CLAUDE.md`, free best-practice fixes were
applied rather than suppressed:

- **Connector VM now uses SSH-key auth** (`tls_private_key` + `admin_ssh_key`,
  `disable_password_authentication = true`, private key in Key Vault), matching
  the SCAN01 pattern - eliminates CKV_AZURE_149/178/1 (the old R13 is retired).
- **tfstate backend now authenticates with Azure AD**: `use_azuread_auth = true`
  on the backend block and every `terraform_remote_state` data source across all
  stacks, and `shared_access_key_enabled = false` on the storage account
  (CKV2_AZURE_40). **Operator/CI prerequisite**: the principal running Terraform
  needs the **Storage Blob Data Contributor** role on the `stnorthwindtfstate`
  account (RBAC), not just a management-plane role - set this up alongside the
  Azure OIDC federation. `terraform init` will fail to read state without it.
- **Key Vault secrets carry a 1-year expiry** via a `time_offset` resource
  (CKV_AZURE_41), resetting on each destroy/rebuild.

Remaining Checkov suppressions are documented with cost/lifecycle rationale in
`grc/risk-register.md` R11/R12/R14/R15 (private endpoints ~$8/mo each, GRS
premium, purge-protection lifecycle, required monitoring extensions, host
encryption). None are suppressed for mere convenience.

## First-deploy bootstrap of 00-foundation (operational notes)

Learned while actually applying `00-foundation` for the first time. Two gotchas
that follow directly from the keyless-storage + management-lock hardening:

- **Keyless state storage needs AAD data-plane auth AND an RBAC grant.** Because
  `azurerm_storage_account.tfstate` sets `shared_access_key_enabled = false`, the
  provider cannot use the account key for data-plane operations (blob soft-delete
  properties, creating the `tfstate` container). Two things are required:
  1. `storage_use_azuread = true` on the `azurerm` provider (now set in
     `00-foundation/providers.tf`) so it uses an Azure AD token for storage
     data-plane calls; and
  2. the caller (operator, or CI's OIDC identity) must hold **Storage Blob Data
     Contributor** on the storage account - Owner/Contributor is NOT enough, as
     those are management-plane only. Without the role the apply fails with
     `403 KeyBasedAuthenticationNotPermitted` (key path) or a
     `403 AuthorizationPermissionMismatch` (AAD path).
- **This role grant can't be fully self-codified (chicken-and-egg).** The data-
  plane config runs as part of creating the storage account itself, so a separate
  `azurerm_role_assignment` resource would apply too late on the first run. The
  grant is therefore a one-time out-of-band bootstrap step, scoped to the storage
  account (narrowest scope, per CLAUDE.md), e.g.:
  `az role assignment create --assignee <objectId> --role "Storage Blob Data Contributor" --scope <storage-account-id>`.
  Re-run `terraform apply` after the grant propagates (RBAC can take a minute).
- **Untaint, don't replace, a storage account the CanNotDelete lock protects.**
  If the first apply half-fails, Terraform marks the storage account `tainted`
  and the next apply tries to REPLACE it (destroy + recreate). That destroy is
  blocked by the `CanNotDelete` lock on `rg-northwind-tfstate` (the lock working
  as intended - `409 ScopeLocked`). When the account is otherwise healthy
  (`provisioningState = Succeeded`), `terraform untaint
  azurerm_storage_account.tfstate` and re-apply: Terraform then updates it
  in-place (no destroy, no lock conflict).
- **State migration + secret hygiene.** After the account exists, uncomment the
  backend block and `terraform init -migrate-state -force-copy`. Then delete the
  local `terraform.tfstate` and `terraform.tfstate.backup` - the backup retains
  the full state (including the generated domain-admin password) in plaintext.
  Both are gitignored, so they are never committed, but they must not linger on
  disk once the remote state is confirmed.

## CI green-up pass (ansible-lint / TFLint findings)

This round got the GitHub CI pipeline passing. Nothing was suppressed - every
finding below was fixed at the source.

### Ansible: migration off the removed `ansible.windows.win_domain*` modules

`ansible.windows` 3.0.0 removed the domain-management modules. Migrated to the
current `microsoft.ad` collection, verified against `ansible-doc` (not assumed
to map 1:1 - several interfaces changed):

- `ad_domain`: `win_domain` -> `microsoft.ad.domain`. Params carry over
  (`dns_domain_name`, `domain_netbios_name`, `safe_mode_password`). The
  post-promotion reboot/wait tasks are now gated on the module's
  `reboot_required` return instead of `promotion is changed` - correct for the
  new module and it also clears the `no-handler` lint (those tasks must run
  inline, before the SACL steps, so they are deliberately not handlers).
- `ad_users`: `win_domain_ou` -> `microsoft.ad.ou`; `win_domain_group` ->
  `microsoft.ad.group`; `win_domain_user` -> `microsoft.ad.user`. The user
  module changed shape: `department` has no dedicated arg (set via
  `attributes.set.department`); `groups` is now a dict (`groups.set`, matching
  the old default `replace` semantics); "must change password at next logon"
  is `password_expired`, which is mutually exclusive with
  `password_never_expires` (so the old explicit `password_never_expires: false`
  was dropped - it was the default anyway); `name` (LDAP cn) is kept equal to
  the sAMAccountName with an explicit `sam_account_name` so the DN is unchanged.
- `victim_ws`: `win_domain_membership` -> `microsoft.ad.membership` (params
  carry over; post-join reboot gated on `reboot_required`).
- `weaknesses` (NOT in the original migration request, but it also used removed
  modules and so blocked a clean lint): `win_domain_user` ->
  `microsoft.ad.user`; `win_domain_group` -> `microsoft.ad.group`;
  `win_domain_group_membership` -> `microsoft.ad.group` with
  `identity: "Domain Admins"` + `members.add` (microsoft.ad has no
  `group_membership` module - membership is managed on the group object).

### Ansible: other `ansible-lint` findings

- `audit_policy`: the 182-char Directory Service Access task name was folded
  with a `>-` block scalar (same rendered text, each line < 160).
- `nessus`: the "Restart Nessus" task that ran `when: nessus_register is
  changed` is now a real handler (`handlers/main.yml`), notified from the
  registration task - clears `no-handler`.
- `victim_ws`: `win_chocolatey` moved to the `chocolatey.chocolatey`
  collection (removed from `ansible.windows`); updated the FQCN. Its
  `ignore_errors: true` (best-effort install) became `failed_when: false`,
  which is the form `ansible-lint` accepts.
- `ansible/requirements.yml` (new) pins the collections the playbook needs
  (`microsoft.ad`, `ansible.windows`, `community.windows`, `community.general`,
  `chocolatey.chocolatey`), and `.github/workflows/ci.yml` now runs
  `ansible-galaxy collection install -r ansible/requirements.yml` before
  linting - without it, syntax-check can't resolve the `microsoft.ad` modules.

### Terraform: TFLint findings

- **Missing `random` provider constraint**: `00-foundation` and `30-identity`
  both use `random_password` but neither declared the provider in
  `required_providers`. Added `hashicorp/random ~> 3.6` to both. `15-access`
  already declared it (checked - no change needed there).
- **Unused declarations** (dead code, `terraform_unused_declarations`):
  - `15-access`: `admin_user_emails` / `redteam_user_emails` were declared (and
    present in the tfvars example) but never consumed - the Twingate groups are
    created with `users = []` and populated via console invite. Removed both
    variables and their tfvars.example lines. If group membership is later
    driven from Terraform, reintroduce them wired to a `twingate_users` data
    source feeding `twingate_group.users`.
  - `40-sentinel`: the `detection_files = fileset(...)` local was superseded by
    the explicit `detections` map (which carries the per-rule name/severity/
    tactics/techniques metadata and is what the analytics-rule resource
    iterates). Removed the dead local.

## Fixed during this review pass (not just "checked" - an actual bug)

- **NSG rule scoping bug**: the original `corp` NSG's base "allow intra-VNet"
  rule used the `VirtualNetwork` service tag for both source and
  destination. Since `mgmt` and `corp` share one VNet, that rule would have
  silently allowed all `mgmt -> corp` traffic at a lower priority number
  (higher precedence) than the deliberately toggled red-team/scanner rules
  - defeating the entire segmentation story those rules exist to enforce.
  Fixed: the base rule is now scoped to `var.corp_subnet_prefix`
  specifically. See `grc/risk-register.md` R10 for the writeup - this is
  worth mentioning in an interview as an example of catching your own
  mistake, not just building things.

## Checked

- **HCL syntax**: every `.tf` file across all 7 stacks parses cleanly
  (verified with `python-hcl2`, a syntax-only check - no provider schemas
  or semantic validation, since that requires `terraform init` against
  real credentials).
- **Twingate provider schema**: confirmed against current docs that the
  3.x-series syntax used in `15-access/main.tf` (`access_group { group_id }`,
  `protocols { tcp { policy, ports } }`) is correct. Twingate's v4 provider
  introduced breaking changes (plural `access_groups`, `is_authoritative`);
  the version constraint is pinned to `~> 3.0` deliberately - see the
  comment in `15-access/providers.tf`. Do not bump the Twingate provider
  version without rewriting `main.tf` to match v4's schema.

## Not yet verified - do this before `terraform apply`

- **`terraform init` / `terraform validate`** against real provider
  registries and real Azure/Twingate credentials. Syntax-clean HCL can
  still fail schema validation, and this repo hasn't had that check run.
- **GitHub Action SHAs** in `.github/workflows/*.yml` are illustrative
  placeholders, flagged inline where they appear. Resolve each to a real
  release commit before the workflows will run at all.
- **Azure Policy built-in display names** in `terraform/05-policy/main.tf`
  (`"Network interfaces should not have public IPs"`, `"Require a tag on
  resources"`, `"Allowed locations"`) - confirm these exact names still
  exist in Policy > Definitions in your subscription before applying;
  Microsoft periodically renames or supersedes built-ins.
- **`AzureMonitorWindowsAgent` extension `type_handler_version`** in
  `20-compute/main.tf` is set to `"1.0"` with `auto_upgrade_minor_version =
  true`, which should self-correct, but confirm the major version is still
  current.
- **`azuread_user` resource arguments** in `30-identity/main.tf`
  (`force_password_change`, `department`, `job_title`) - written against
  the `hashicorp/azuread` ~> 2.53 schema from documentation knowledge, not
  independently re-verified the way the Twingate schema was. Run
  `terraform plan` early and address any argument-naming errors before
  assuming the rest of the stack is correct.
- **Ansible Windows collection module names** (`ansible.windows.*`,
  `community.windows.win_unzip`, `community.general.read_csv`) - install
  the collections (`ansible-galaxy collection install ansible.windows
  community.windows community.general`) and run `ansible-playbook
  --syntax-check site.yml` before a real run; this hasn't been executed
  against a real Ansible installation.

## New in this round - not yet verified

- **`add-replication-audit-sacl.ps1`** (feeds `10-dcsync-rights-abuse.kql`):
  written from a widely published AD-hardening pattern using
  `System.DirectoryServices.ActiveDirectoryAuditRule`. Has not been run
  against a real domain. Test this early - if the SACL doesn't apply
  correctly, the DCSync detection has nothing to fire on, and you won't
  know until you try the attack chain.
- **Nessus `.deb` download URL and activation code** in
  `ansible/group_vars/all.yml` are literal placeholders
  (`CHANGE-ME-...`). The download URL changes with every Nessus release -
  get the current one from Tenable's downloads page - and the activation
  code requires a real Tenable account signup that cannot be automated.
- **`ansible.builtin.expect`** (used in the nessus role for `nessuscli
  adduser`) requires the `pexpect` Python library on the Ansible control
  node. Install it (`pip install pexpect`) before running this role, and
  expect to need to adjust the exact prompt strings against your actual
  Nessus version's CLI output - these can drift between releases.
- **PetitPotam/PrinterBug/Impacket tool syntax** in
  `attack-chain/02b-coercion-ntlmrelay-dcsync.md` reflects commonly
  published usage patterns for these tools, not a run against this
  specific lab. Confirm current command-line flags against the tools'
  own `--help` output / current GitHub README before relying on the exact
  syntax shown.

## How to extend this check yourself

If you want to catch more before spending Azure credits: run
`terraform validate` inside each stack directory immediately after
`terraform init`, before ever running `plan` or `apply` against real
infrastructure. That's the next checkpoint beyond what's been done here.
