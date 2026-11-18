# Session status — 2026-11-17

Snapshot for picking the work back up. Tonight redeployed `00-foundation`,
documented a real CI/CD gap, rebranded the fictional company to a hospital, then
**fully tore everything back down** — full-teardown discipline, nothing left
running overnight.

## What is currently deployed in Azure

**Nothing.** `00-foundation` was deployed (16 resources) and then destroyed again
tonight (lock removed → state migrated local → `terraform destroy` → local state
cleaned → backend block restored). `az group list` shows **no `rg-northwind-lab`
and no `rg-northwind-tfstate`** — only `NetworkWatcherRG` remains, which Azure
auto-provisions per region (platform-managed, free, not ours). `az vm list`
returns **0**. Stacks 05/10/15/20/30/40 are not deployed.

## Tonight's work (2026-11-17)

1. **Redeployed `00-foundation` end-to-end** (16 resources) and re-verified the
   whole bootstrap: local-state apply → **Storage Blob Data Contributor** grant
   scoped to the storage account → `init -migrate-state` → local state cleanup.
   The RBAC-propagation lag reproduced again (migrate-state returned `403
   AuthorizationPermissionMismatch` on the first attempts, succeeded after
   ~1–2 min). The grant is **always required** before migrate-state, even though
   the apply itself succeeds without it.
2. **Documented the CI/CD Azure OIDC gap** (**PR #12**, merged). OIDC was never
   configured: the `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID`
   repo secrets don't exist, so `drift-detection.yml` was failing at `azure/login`
   on every scheduled run (~25s, never reaching `terraform plan`). We **paused the
   daily drift schedule** (now `workflow_dispatch`-only) so it stops emitting a
   known-false daily failure, added visible banners, captured the full setup scope
   in `TODO.md`, and started gitignoring `tfplan`/`*.tfplan`. `ci.yml`'s plan job
   already skipped gracefully, so it was never failing. **This is tracked for a
   dedicated session — not set up tonight.**
3. **Hospital rebrand** (**PR #13**, merged): the fictional company is now
   `Northwind General Hospital`, content/metadata only (job titles, README/PLAN
   titles, the AD `company` attribute, comments). **No resource names or the AD
   domain changed.**
4. **Full-subscription orphan check**: clean — no stray VMs, disks, snapshots,
   NICs, public IPs, or VNets anywhere.
5. **Full teardown** of `00-foundation` and confirmed the subscription is empty.

### Original goal for the night — NOT reached
The intended goal was telemetry flowing into Sentinel with all 10 detection rules
active. That was **not achieved** — only `00-foundation` was built (then torn
down). No network, compute, AD, telemetry, or Sentinel was deployed. Next session
has to build the whole chain before any attack-chain work.

## Next session — start FRESH from the beginning

Azure is empty, so this is a clean redeploy, **not** a resume of live infra:

1. **`00-foundation`** redeploy (runbook below).
2. **`10-network`**.
3. Then continue the original plan: `15-access` → `20-compute` →
   `ansible-playbook site.yml` → `40-sentinel`, to finally get telemetry +
   the 10 rules active, *then* run the attack chain.

## Repository state

`main` has PRs **#1–#13** merged; **no open PRs**. Working tree clean. CI (fmt,
TFLint, Checkov, gitleaks, ansible-lint, terraform-plan graceful-skip) is green.
The company is now **Northwind General Hospital** throughout the docs/data;
the only surviving `dental` strings are the storage account name `stnwdental1127`
(deployed-resource name, kept by design) and the English word "accidental(ly)".

## Known gaps tracked for later (see `TODO.md`)

- **Azure OIDC for CI** — Entra app registration, repo-scoped federated
  credential, and a **narrowly-scoped** role assignment (not subscription-wide),
  plus a `grc/risk-register.md` entry. Re-enable the drift schedule in that same
  PR. Deliberately deferred.
- Evidence-screenshot capture checklist (capture live during a real deploy /
  attack-chain run).

## Names you'll need next time (non-sensitive)

| Thing | Value |
|-------|-------|
| Fictional company | `Northwind General Hospital` |
| Project prefix | `northwind` (storage uses the short form `nwdental`) |
| Region | `eastus` |
| Lab resource group | `rg-northwind-lab` (safe-to-destroy) |
| State resource group | `rg-northwind-tfstate` (DO-NOT-DESTROY; gets the `CanNotDelete` lock) |
| State storage account | **`stnwdental1127`** (legacy `nwdental` token retained — it's the deployed account name; do not rename) |
| State container | `tfstate` (keys: `00-foundation.tfstate`, `10-network.tfstate`, `15-access.tfstate`, …) |
| Key Vault | `kv-northwind-lab` |
| Management lock | `lock-northwind-tfstate-nodelete` |
| AD domain | `northwind.local` |
| Connector VM size | **`Standard_F1als_v7`** (B-series is capacity-restricted in eastus) |
| Lab VM size (DC01/WS01/FS01 + SCAN01) | `Standard_B2s` — **check capacity before applying 20-compute** (see VALIDATION_NOTES.md); override with `-var vm_size=… -var scan01_vm_size=Standard_F2als_v7` if restricted |

## Secrets / IDs deliberately NOT stored here (public repo — R7)

Fetch/supply these at redeploy time; never hardcode them in this public repo:

- Subscription / tenant: `az account show -o json` (az/Terraform use the
  logged-in default subscription automatically).
- Your objectId (for the RBAC grant): `az ad signed-in-user show --query id -o tsv`
- Budget email: pass via `-var` (`budget_alert_emails`).
- **Twingate network slug**: your network's subdomain (Twingate console → the
  part before `.twingate.com`). Pass via `-var twingate_network_name=...`.
- **Twingate API token** (a SECRET): generate an **Admin** API key with
  connector-management rights (Twingate → Settings → API). Store it in Key Vault
  as `twingate-api-token` (never in a file/var/log) — `15-access` reads it from
  there. The KV is destroyed on teardown, so this must be re-stored on redeploy:
  ```bash
  TF=$(mktemp); printf '%s' 'PASTE_TOKEN' > "$TF"
  az keyvault secret set --vault-name kv-northwind-lab --name twingate-api-token --file "$TF" --output none
  rm -f "$TF"
  ```

## Redeploy runbook (order: 00-foundation → 10-network → 15-access → …)

### 1. `00-foundation` (self-hosting backend — bootstrap)

> **The Storage Blob Data Contributor grant is ALWAYS required on a fresh
> storage account, every time, before `migrate-state` will work.** A successful
> `terraform apply` does NOT mean you can skip it: the apply's container +
> blob-soft-delete steps are *management-plane* ops that Owner already covers, but
> `migrate-state` writes the state *blob* (a *data-plane* write) and needs the
> role. RBAC propagation lags ~1–5 min (retry on 403). Full background in
> `VALIDATION_NOTES.md`.

```bash
cd terraform/00-foundation
# a. Comment OUT the backend "azurerm" block in providers.tf (local state).
terraform init
terraform plan  -out=tfplan -var='budget_alert_emails=["YOUR_EMAIL"]'
terraform apply tfplan                       # succeeds: 16 to add
# b. ALWAYS grant blob-data access (even though apply succeeded):
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv); SUB=$(az account show --query id -o tsv)
az role assignment create --assignee "$OBJECT_ID" --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB/resourceGroups/rg-northwind-tfstate/providers/Microsoft.Storage/storageAccounts/stnwdental1127"
# c. Uncomment the backend block, then migrate (retry on 403 — RBAC lags 1-5 min):
terraform init -migrate-state -force-copy
rm -f terraform.tfstate terraform.tfstate.backup   # .backup holds the domain-admin secret
```

### 2. `10-network` (depends on 00-foundation state)

```bash
cd ../10-network
terraform init
terraform plan  -out=tfplan        # 8 to add (VNet, subnets, NSGs); no vars needed
terraform apply tfplan
```

### 3. `15-access` (depends on 00-foundation + 10-network state)

Prereq: the Twingate **Admin** API token is re-stored in Key Vault (see Secrets).

```bash
cd ../15-access
terraform init
terraform plan  -out=tfplan -var='twingate_network_name=YOUR_SLUG'
terraform apply tfplan             # 14 to add; connector_vm_size defaults to F1als_v7
# Then check the Twingate dashboard: the connector should show "Connected".
```

## Teardown runbook (order: 15-access → 10-network → 00-foundation)

```bash
# 15-access (needs the Twingate token still in KV + the slug var):
cd terraform/15-access
terraform plan -destroy -out=d -var='twingate_network_name=YOUR_SLUG'; terraform apply d
# 10-network:
cd ../10-network
terraform plan -destroy -out=d; terraform apply d
# 00-foundation (remove the lock, pull state local so destroy doesn't delete its own backend):
cd ../00-foundation
az lock delete --name lock-northwind-tfstate-nodelete --resource-group rg-northwind-tfstate
#   comment OUT the backend block, then:
terraform init -migrate-state -force-copy
terraform plan -destroy -out=d -var='budget_alert_emails=["YOUR_EMAIL"]'; terraform apply d
rm -f terraform.tfstate terraform.tfstate.backup
#   restore (uncomment) the backend block afterwards
az group list --query "[?contains(name,'northwind')].name" -o tsv   # expect: empty
```

## Known gotchas

- **Keyless state storage** needs `storage_use_azuread = true` (in code) **and**
  the caller holding **Storage Blob Data Contributor** on the account. Owner is
  management-plane only; a clean apply is NOT a signal the grant can be skipped —
  `migrate-state` (state-blob write) always needs it.
- **Never `terraform destroy` 00-foundation with the remote backend active** —
  it deletes the storage account holding its own state and fails to persist
  final state. Pull state local first (comment backend → `init -migrate-state`).
- **The `CanNotDelete` lock** blocks replacing a tainted-but-healthy storage
  account (`untaint`, don't replace) and blocks destroying the state RG (remove
  it first with `az lock delete`).
- **Twingate**: the API token must have connector-management rights; the provider
  models `protocols` as an attribute and `access_group` as a block.
- **`eastus` B-series capacity**: `Standard_B1s`/B2s have returned `409
  SkuNotAvailable`; the connector defaults to `Standard_F1als_v7`. Check capacity
  before applying 20-compute and override the lab VM size if needed.
- **Bash `grep`/`find` glitch**: in this environment the wrapped `grep`/`find`
  sometimes error with "claude native binary not installed" and return nothing.
  Use `git grep`, `command grep` / `/usr/bin/grep`, `python3`, or the Read tool.
