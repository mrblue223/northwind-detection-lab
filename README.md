# Northwind Dental — Detection Engineering Lab

A 25-user fake company built as code in Azure (AD + Entra ID), reached only through
Twingate ZTNA, attacked via a simulated phishing chain, and monitored in Microsoft
Sentinel. Fully destroyable and rebuildable with `make up` / `make down`.

See `PLAN.md` for the full phased project plan.

## Cost strategy (target: free trial credits, then ≤ $20/month)

The only things that should ever run 24/7 are:
- The Twingate Connector VM (smallest size available)
- The managed OS disks for DC01/WS01/FS01 (disks bill even when the VM is deallocated)

Everything else — DC01, WS01, FS01 compute — gets **fully deallocated** between
work sessions via `make down`, not just stopped in the OS. Stopped-but-allocated
VMs still bill for compute; deallocated VMs do not.

Sentinel is enabled *last* (Phase 3), after the lab is fully built, so the 31-day
free trial (ingestion + Sentinel charges waived up to 10GB/day) covers the
attack/detection phases instead of being wasted during setup.

A budget alert is created in this very first stack, before any other resource
exists, set at $15 to leave headroom under the $20 ceiling.

## Repo layout

```
terraform/
  00-foundation/   # budget alert, remote state, Key Vault
  05-policy/       # Azure Policy as code (no public IP, require tags, allowed locations)
  10-network/      # VNet, mgmt/corp subnets, NSGs (no public inbound anywhere)
  15-access/       # Twingate connector + resources (admin + toggleable red-team)
  20-compute/      # DC01, WS01, FS01 + auto-shutdown schedules
  30-identity/     # Entra users/groups
  40-sentinel/     # workspace, Sentinel, detections as code
ansible/           # domain promotion, users, telemetry, weaknesses, Nessus on SCAN01
.github/workflows/ # CI (fmt/lint/scan), manual OIDC apply, scheduled drift detection
grc/               # risk register, control mapping, defense-in-depth, IR runbook
data/users.csv     # fake employee roster
attack-chain/      # attack log + ATT&CK mapping
detections/        # one file per detection rule
evidence/          # sanitized screenshots/logs
coverage.md        # what was detected, missed, and why
```

## Architecture

Reflects what the Terraform actually defines (`00-foundation`, `10-network`,
`15-access`, `20-compute`, `40-sentinel`). All inbound access is through Twingate
ZTNA — **there are no public IPs and no internet-facing endpoints anywhere.**

```mermaid
flowchart TB
    operator["Operator laptop<br/>Twingate client"]:::ext
    gha["GitHub Actions<br/>OIDC · no stored creds"]:::ext

    subgraph AZURE["Azure subscription · no public inbound anywhere"]
      direction TB
      nopub["No public IPs / no internet-facing endpoints —<br/>every inbound path is Twingate ZTNA or the Azure control plane"]:::note

      subgraph RGSTATE["rg-northwind-tfstate · locked (CanNotDelete)"]
        tfstate[("stnwdental1127<br/>tfstate storage · keyless / AAD")]:::store
      end

      subgraph RGLAB["rg-northwind-lab · safe-to-destroy"]
        direction TB
        kv["kv-northwind-lab<br/>SSH keys · domain-admin pw"]:::vault
        law["law-northwind-lab<br/>Log Analytics / Sentinel"]:::mon

        subgraph VNET["vnet-northwind-lab · 10.10.0.0/16"]
          direction TB
          subgraph MGMT["snet-mgmt · 10.10.1.0/24 · nsg-mgmt"]
            conn["Twingate Connector<br/>vm-tg-connector · .10 · SSH-key"]:::infra
            scan["SCAN01 · Nessus<br/>.11"]:::infra
          end
          subgraph CORP["snet-corp · 10.10.2.0/24 · nsg-corp (deny internet; corp-internal only)"]
            dc01["DC01 · .10"]:::infra
            ws01["WS01 · .11"]:::infra
            fs01["FS01 · .12"]:::infra
          end
        end
      end
    end

    subgraph LEGEND["Access-path legend"]
      direction LR
      lg1["admin — solid green"]:::lgadmin
      lg2["red-team — dashed red, OFF by default"]:::lgred
      lg3["SCAN01 to corp — permanent, narrow (orange)"]:::lgscan
      lg4["CI/CD OIDC to Azure — blue"]:::lgci
    end

    operator -->|"Twingate ZTNA policy"| conn
    conn ==>|"RDP / WinRM"| dc01
    conn ==>|"RDP / WinRM"| ws01
    conn ==>|"SMB / RDP / WinRM"| fs01
    scan -->|"scan ports · /32-scoped, permanent"| CORP
    conn -.->|"red-team CIDR · OFF by default"| CORP
    gha ==>|"OIDC federated credential → ARM"| AZURE
    gha -->|"Terraform state · AAD token"| tfstate
    conn --> law
    scan --> law
    dc01 --> law
    ws01 --> law
    fs01 --> law

    classDef ext fill:#e7f0ff,stroke:#1c4ed8;
    classDef store fill:#fff1e0,stroke:#d9480f;
    classDef vault fill:#f3e8ff,stroke:#6741d9;
    classDef mon fill:#e6fcf5,stroke:#0ca678;
    classDef infra fill:#f8f9fa,stroke:#495057;
    classDef note fill:#fff9db,stroke:#f08c00;
    classDef lgadmin fill:#ebfbee,stroke:#2f9e44;
    classDef lgred fill:#fff5f5,stroke:#e03131;
    classDef lgscan fill:#fff4e6,stroke:#e8590c;
    classDef lgci fill:#edf2ff,stroke:#1c4ed8;

    linkStyle 0,1,2,3 stroke:#2f9e44,stroke-width:2px;
    linkStyle 4 stroke:#e8590c,stroke-width:2px;
    linkStyle 5 stroke:#e03131,stroke-width:2px,stroke-dasharray:6 4;
    linkStyle 6,7 stroke:#1c4ed8,stroke-width:2px;
    linkStyle 8,9,10,11,12 stroke:#adb5bd,stroke-width:1px,stroke-dasharray:2 3;
```

Telemetry (grey dotted) is the Azure Monitor Agent on every VM shipping to the
Log Analytics workspace / Sentinel. The red-team path and its NSG counterpart in
`10-network` both default to **off** (`enable_redteam_resource` /
`enable_redteam_access`). A full data-flow / trust-boundary view (including the
attack chain) is in [`grc/data-flow-diagram.md`](grc/data-flow-diagram.md).

## CI/CD and GRC

- **CI** (`.github/workflows/ci.yml`): `terraform fmt`, TFLint, Checkov,
  gitleaks, and ansible-lint run on every PR. Nothing merges to `main` with
  a known misconfiguration pattern or a leaked secret.
- **Apply** (`terraform-apply.yml`): manual trigger only, authenticated via
  Azure OIDC (no stored cloud credentials in the repo), gated behind a
  GitHub Environment approval.
- **Drift detection** (`drift-detection.yml`): scheduled `terraform plan`
  against live Azure, opens an issue if reality has diverged from what's
  committed - catches changes CI never sees, like a manual portal edit.
- **`grc/`**: a risk register for every deliberate weakness and toggle, a
  CIS Controls v8 mapping, and - importantly - `defense-in-depth.md`,
  which documents what this pipeline *can't* catch (business-logic flaws,
  supply-chain risk, zero-days) and why the Sentinel detection layer exists
  as the other half of the story, not a redundant one.

## Usage

```
make init      # terraform init on all stacks
make up        # apply foundation -> network -> access -> compute
make down      # deallocate compute, leave foundation/state/KV intact
make destroy   # tear down everything including state (rarely used)
```
