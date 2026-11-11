# Risk register

Every deliberate weakness and toggleable attack path in this lab, treated as
a real risk register entry would treat them. Likelihood/impact are rated
for *this lab's own security*, not as a generic statement about the
technique in production environments.

| ID | Risk | Likelihood | Impact | Compensating control | Residual risk |
|---|---|---|---|---|---|
| R1 | Kerberoastable service account (`svc_backup`) compromised | High (deliberate) | Medium - scoped to lab AD | Detection rule `04-kerberoasting.kql`; account confined to a lab-only forest with no production trust | Accepted - this is the intended attack surface |
| R2 | `GRP-IT` nested into Domain Admins (over-privileged group) | High (deliberate) | High - full domain compromise if exploited | Detection rule `06-persistence.kql` on group membership changes; lab-only blast radius | Accepted - intended attack surface |
| R3 | Red-team Twingate Resource / NSG rule left enabled after testing | Low (requires forgetting to toggle off) | High - opens `mgmt`->`corp` broadly | Both toggles (`enable_redteam_access`, `enable_redteam_resource`) default to `false`; drift-detection workflow catches a stack left in the "on" state since that's a diff from the committed default | Medium - depends on remembering to flip back AND on actually running `terraform apply` after flipping |
| R4 | Twingate Connector VM compromised (sole network entry point) | Low | High - would expose all admin paths | Connector runs on a minimal, patched Ubuntu LTS image on the smallest SKU (smaller attack surface by design); no inbound rules to it at all | Medium - a connector compromise is a real single point of failure for ZTNA designs generally, lab or production |
| R5 | Secrets committed to the public GitHub repo | Low (CI gated) | Critical - credential/token leakage | `gitleaks` required check in CI; `.gitignore` excludes `.tfvars`, state files, and `attack-chain/log.md`; Key Vault holds all generated secrets, never the repo | Low, but not zero - see `defense-in-depth.md` for why CI can't guarantee this |
| R6 | Terraform state exposure (contains some sensitive values) | Low | High - state can contain secrets in plaintext | State lives in a separate resource group (`rg-northwind-tfstate`) with its own lifecycle, never destroyed alongside the lab, access scoped to the same principal that can reach Key Vault | Medium - remote state in Azure Storage is standard practice but is not itself encrypted-at-rest-by-default beyond platform defaults; consider a Customer-Managed Key as a stretch goal |
| R7 | Public repo reveals lab architecture to a motivated attacker | Medium (it's public, by design) | Low - no real data, no production trust, IPs are private/lab-only | Nothing in the repo is reachable from the internet regardless of what's known about it (no public IPs, ZTNA-gated) | Low |
| R8 | SMB signing / LDAP channel binding not enforced, enabling the PetitPotam/PrinterBug -> NTLM relay -> DCSync chain | High (deliberate) | Critical - full domain compromise via DCSync | Detection rules `08`/`09`/`10`; confined to the lab's single-DC, no-production-trust forest | Accepted - intended attack surface, see `attack-chain/02b-coercion-ntlmrelay-dcsync.md` |
| R9 | SCAN01 (Nessus host) has standing network reach into `corp` | Low-Medium | Medium-High - a compromised scanner has broad visibility and, if credentialed scans are configured, stored domain credentials | Access gated by its own narrow Twingate Resource (SSH only); NSG rule scoped to SCAN01's single IP and specific ports, not the whole mgmt subnet; scan credentials (if used) live in Key Vault only, never in Ansible or the repo | Medium - a vulnerability-scanning host is inherently a high-value target in any real environment, lab or not; this is worth discussing explicitly as a realistic trade-off, not a solved problem |
| R10 | NSG rule ordering mistake (`Allow-VNet-Inbound` originally scoped to the `VirtualNetwork` tag) would have silently allowed all mgmt->corp traffic regardless of the red-team/scanner toggles | N/A - caught in review, not deployed | Would have been Critical - defeats the entire segmentation story | Fixed before first deploy: the base corp-internal rule is now scoped to the corp subnet prefix specifically, not the `VirtualNetwork` service tag (see `terraform/10-network/main.tf`) | None - documented here specifically because this class of mistake (an overly broad base rule silently outranking more specific, more carefully-reasoned-about rules) is a realistic and common way NSG-based segmentation fails in production, not just in a lab |

## How to use this table

Update it whenever you add a new deliberate weakness, a new toggle, or a new
always-on component. The point of a risk register isn't to reach zero risk -
it's to make every accepted risk a *decision*, not an oversight.
