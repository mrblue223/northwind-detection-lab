# Validation notes

What's been checked before you run this, and what's still on you to verify
against live provider docs/accounts before a real `terraform apply`. Written
this way on purpose - a repo that claims to be fully verified without a real
`terraform init`/`plan` against live credentials would be overstating it.

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
