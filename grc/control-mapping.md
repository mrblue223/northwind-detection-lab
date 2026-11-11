# Control mapping (CIS Controls v8)

Maps concrete things built in this project to CIS Controls v8 Safeguards.
Picked CIS over NIST 800-53 for this doc because its Safeguard numbering
maps cleanly to specific technical actions, which is more useful for a
project like this than a broader compliance-program framework. Swap in
NIST 800-53 or ISO 27001 mappings if that's more relevant to a target
employer - the underlying work doesn't change, only the label.

| CIS Safeguard | Control | What satisfies it in this project |
|---|---|---|
| 1.1 | Establish and maintain an inventory of enterprise assets | `data/users.csv`, Terraform state as the single source of truth for every VM/subnet/resource |
| 3.3 | Configure data access control lists | Twingate per-resource access policies (admin vs. red-team groups); NSGs scoped per subnet |
| 4.1 | Establish and maintain a secure configuration process | All infra defined in Terraform, reviewed via PR, scanned by Checkov/TFLint before merge |
| 4.4 | Implement and manage a firewall on servers | NSGs on both subnets, default-deny with explicit, commented exceptions |
| 5.1 | Establish and maintain an inventory of accounts | `data/users.csv` roster, mirrored into both AD (Ansible) and Entra ID (Terraform) |
| 5.4 | Restrict administrator privileges to dedicated admin accounts | Twingate `admins` group is separate from `redteam` group; domain admin credentials isolated in Key Vault, never in a playbook or repo file |
| 6.1 | Establish an access granting process | Twingate Resources defined declaratively per host/protocol in `15-access/main.tf` - access is a Terraform diff, not a manual console click |
| 6.2 | Establish an access revoking process | `make down` destroys the compute stack entirely; red-team toggles default to `false` and are reverted after each test (see `risk-register.md` R3) |
| 8.2 | Collect audit logs | Windows Security Event auditing (`audit_policy` role), Sysmon, Entra sign-in/audit logs, all shipped to Log Analytics |
| 8.5 | Collect detailed audit logs | PowerShell Script Block Logging, command-line auditing enabled in `audit_policy` |
| 8.11 | Conduct audit log reviews | `coverage.md` process: replay attacks, review what fired, document gaps |
| 10.1 | Deploy and maintain anti-malware software | Out of scope for v1 - documented gap, not claimed |
| 12.2 | Establish and maintain a secure network architecture | `mgmt`/`corp` subnet segmentation, Twingate ZTNA replacing flat network access |
| 12.6 | Use of secure network management and communication protocols | WinRM over HTTPS (5986), no plaintext RDP exposed to anything but the ZTNA path |
| 16.1 | Establish and maintain a secure application development process | CI pipeline: `terraform fmt`, TFLint, Checkov, gitleaks, ansible-lint, required before merge |
| 16.11 | Leverage vetted modules or services for application security | Built-in Azure Policy definitions used instead of hand-rolled equivalents (`05-policy`) |
| 17.1 | Designate personnel to manage incident handling | `incident-response-runbook.md` (solo-operator version) |
| 18.1 | Establish and maintain a penetration testing program | The attack-chain itself (`attack-chain/`), run against your own environment |
| 7.1 | Establish and maintain a vulnerability management process | SCAN01 running Nessus Essentials, scoped to `corp` via a dedicated, permanent (non-toggled) NSG rule - see `terraform/10-network` and `ansible/roles/nessus` |
| 7.5 | Perform automated vulnerability scans of internal enterprise assets | SCAN01 scan results exported to `evidence/` as part of the Phase 6 validation pass |

## Honest gaps against this framework

Still absent, deliberately: anti-malware (10.x), formal data classification
(3.x beyond ACLs), and business continuity/disaster recovery (11.x) - none
of these fit a single-operator lab meaningfully, and claiming coverage
would be dishonest. List what you'd add for each if this were scaled to a
real small business, as a short note under each gap. Vulnerability
management (7.x) moved from "gap" to "covered" once SCAN01/Nessus was
added - note the before/after in your own writeup as evidence of
iterating on a documented limitation rather than just listing it once and
moving on.
