# Cost notes

Target: free trial credits first, then **≤ $20/month** steady state.

## What's built so far and its cost shape

- **00-foundation**: resource group, budget alert (Action Group + Consumption
  Budget at $15/80%/100%), Key Vault, tfstate storage account, plus the
  governance layer below. All of this is effectively free (Key Vault standard
  tier + tiny storage account = a few cents/month).
- **00-foundation governance layer** (management lock, Defender for Cloud free
  tier, Activity Log alerts) — **$0**, confirmed against the resource types used
  here:
  - **Management lock** (`CanNotDelete` on the state RG): resource locks are a
    free Azure Resource Manager feature.
  - **Microsoft Defender for Cloud — Free tier**: the foundational CSPM (secure
    score + security recommendations) is free. This is a real distinction: the
    *paid* Defender plans (Servers/Storage/Key Vault) bill per resource —
    Defender for Servers Plan 2 is ~$15/VM/month, which would be ~$60/month
    across the four lab VMs. We deliberately stay on Free (see risk-register.md
    R16); do **not** flip `tier` to `"Standard"` without re-reading the budget.
  - **Activity Log alerts** (`azurerm_monitor_activity_log_alert`): Azure Monitor
    **activity log** alert rules are free. Note this is specifically activity-log
    alerts — Monitor *metric* alerts and *log-search* alerts DO bill per rule, so
    don't swap these for those without checking. Action-group email
    notifications are also free at this volume.

  Re-check these against current Azure pricing before relying on the numbers —
  Microsoft changes free-tier terms (rule 4 below).
- **10-network**: VNet, subnets, NSGs. Free — no charge for VNets/NSGs
  themselves, only for data processed, which is negligible at lab scale.

## What will cost money (upcoming stacks)

| Item | Stack | Cost shape | Control |
|---|---|---|---|
| Twingate Connector VM | 15-access | small, always-on | Use `Standard_B1s`, Linux, smallest OS disk |
| SCAN01 (Nessus) | 20-compute | can be deallocated between scan sessions | Treat like DC01/WS01/FS01 - `make down` covers it since it's in the same stack; only run it when actually scanning |
| DC01 / WS01 / FS01 | 20-compute | compute only while allocated | `make down` after every session - this destroys the compute stack entirely, not just stops the VMs |
| Managed OS disks for DC01/WS01/FS01 | 20-compute | **bills even when VM is deallocated** | Use Standard SSD, not Premium; keep disk size at the Windows default (127GB) only if needed, otherwise shrink |
| Log Analytics ingestion | 40-sentinel | free up to 10GB/day for 31 days once Sentinel is enabled | Don't enable Sentinel until Phase 3 is otherwise ready; set a daily cap afterward |
| Entra ID P1/P2 (optional) | - | trial covers sign-in log export | Only activate during the window you need it |

## Rules of thumb for this project

1. **`make down` is not optional.** The whole cost model assumes DC01/WS01/FS01
   do not exist between sessions. Rebuilding them via Ansible takes time but
   costs nothing while off.
2. The Twingate Connector VM is the one thing that's cheaper to leave running
   than to tear down and rebuild each time (it has to re-register and you'd
   be re-touching Key Vault tokens). Keep it on the smallest SKU and treat
   its small constant cost as the price of the ZTNA story.
3. Disks left behind by a half-destroyed stack are the most common silent
   cost leak. After `make down`, check the resource group in the portal (or
   `az disk list -g rg-northwind-lab -o table`) to confirm no orphaned disks
   remain before closing out a session.
4. Re-check current Azure and Twingate pricing/trial terms before relying on
   any specific number above — they change.
