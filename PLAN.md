# Northwind Dental — Detection Engineering Lab: Final Project Plan

A 25-user fake company built entirely as code in Azure (AD + Entra ID),
reached only through Twingate ZTNA, attacked via a simulated phishing chain,
monitored in Microsoft Sentinel — every rule, config, and gap documented and
rebuildable with `make up` / `make down`.

This is the same plan as the hosted project doc; kept here so the repo is
self-contained.

## Architecture

**Two planes:**
- **Management plane:** you -> Twingate client -> Connector -> admin access
  to DC01/WS01/FS01 for building, Ansible, and checking results.
- **Attack plane:** phishing (Stage A) compromises WS01, which already has
  legitimate network access; post-exploitation (Stage B) pivots from that
  foothold. An optional Stage C runs a direct attack from Kali through a
  toggleable red-team Twingate Resource + NSG rule.

**Subnets:** `mgmt` (Connector, SCAN01 vulnerability scanner), `corp`
(DC01, WS01, FS01). No public IPs anywhere. SCAN01 gets a narrow,
permanent NSG rule into `corp` (separate from the toggleable red-team
path) since scanning is an ongoing operational function, not an attack
simulation.

**Stage B2b** (new): PetitPotam/PrinterBug coercion of DC01, relayed via
NTLM to DC01's own LDAP service, granting DCSync rights - replaces a
classic LLMNR/NBT-NS poisoning stage, which doesn't work in Azure (VNets
block all multicast/broadcast traffic, even within one subnet). See
`attack-chain/02b-coercion-ntlmrelay-dcsync.md`.

## Repo structure

See `README.md` for the full tree.

## Phases

0. **Foundations** — budget alert, remote state, Key Vault, Twingate account. *(done)*
1. **Network + Twingate access** — VNet/subnets/NSGs, Connector, admin +
   red-team Resources, tool-compatibility checkpoint. *(done)*
2. **The company** — DC01/WS01/FS01, AD promotion, 25 users, deliberate
   weaknesses, WS01 as the phishing victim workstation. *(done)*
3. **Telemetry + Sentinel** — Sysmon, audit policy, AMA, Log Analytics,
   Sentinel enabled last to preserve the free-trial window. *(done)*
4. **Attack chain** — Stage A (phishing), Stage B (post-exploitation from
   WS01), Stage C (optional spray via red-team path). *(documented, ready to run)*
5. **Detections as code** — one KQL rule per stage, deployed via Terraform. *(done)*
6. **Validate + harden** — replay, measure detection rate/time-to-alert,
   test false positives, fill in `coverage.md`. *(your turn)*
7. **Publish** — sanitize, README polish, demo recording. *(your turn)*

## Budget

Target: free trial credits, then ≤ $20/month. See `COST_NOTES.md` for the
full breakdown. Core rule: `make down` after every session.

## Risks

See `COST_NOTES.md` and the comments in each Terraform stack for specific
mitigations (DC promotion timing, Twingate tool compatibility, trial
expiry, admin-traffic noise in telemetry, secret leakage on publish).
