# Session status — 2026-11-13

Snapshot for picking the work back up. Tonight deployed `10-network` and
`15-access` on top of `00-foundation`, **verified the Twingate connector shows
Connected end-to-end**, then tore all three stacks back down (a build/deploy/
connect/destroy rebuild test — these stacks are ~$0 bar the connector VM, which
was up only briefly).

## What is currently deployed in Azure

**Nothing.** All three stacks were destroyed in dependency order
(`15-access` → `10-network` → `00-foundation`): 14 + 8 + 15 resources destroyed.
`az group list` confirms **no `rg-northwind-lab` and no `rg-northwind-tfstate`**
remain. The subscription is back to empty for this project. Stacks 05/20/30/40
have never been applied.

## Tonight's verified progress

- **`10-network` builds and deploys cleanly** (VNet `vnet-northwind-lab`
  10.10.0.0/16, `snet-mgmt` 10.10.1.0/24, `snet-corp` 10.10.2.0/24, NSGs + the
  scanner→corp rule; red-team NSG rule correctly off by default). 8 resources.
- **`15-access` builds, deploys, and the connector CONNECTS end-to-end** —
  verified in the Twingate dashboard (Controller + Relay green). This proves the
  whole path: Terraform → Azure VM → cloud-init → Docker → Twingate connector
  registration.
- Two **real schema bugs** in `15-access` were found and fixed (see **PR #6**):
  1. `twingate_group` used `users = []`, which the `~> 3.0` provider rejects
     (`Unsupported argument`). The attribute is `user_ids`; the groups are meant
     to be console-populated, so `users` was removed and `is_authoritative =
     false` added.
  2. `twingate_resource` used `protocols { ... }` **block** syntax; the provider
     models `protocols` as a nested **attribute**, so all 5 resources were
     converted to `protocols = { tcp = {...}, udp = {...} }`. (`access_group`
     stays a block — verified directly against the schema.)
- **Twingate API token needs connector-creation rights.** A general read/write
  token failed `twingate_connector_tokens` with *"No permission for this
  operation"*. The token used for the stack must be able to create/manage
  connectors (an Admin-level API key), not just read/write resources.
- **`Standard_B1s` is capacity-restricted in `eastus`** right now — the whole
  B-series returned `409 SkuNotAvailable / Capacity Restrictions` at VM-create
  time. The `connector_vm_size` default was changed to **`Standard_F1als_v7`**
  (1 vCPU / 2 GB, available) in **PR #6**. This is an availability issue that can
  recur, so it's a code default, not just a note.

## Repository state

`main` has PRs **#1–#5** merged. **PR #6** (open) carries tonight's three
`15-access` fixes (twingate_group `user_ids`/`is_authoritative`, protocols
block→attribute, and the `connector_vm_size` default). This status update + the
new stack lock files ride on the same PR #6 branch. CI (fmt, TFLint,
ansible-lint, Checkov, gitleaks, terraform-plan graceful-skip) is green.

## Names you'll need next time (non-sensitive)

| Thing | Value |
|-------|-------|
| Project prefix | `northwind` (storage uses the short form `nwdental`) |
| Region | `eastus` |
| Lab resource group | `rg-northwind-lab` (safe-to-destroy) |
| State resource group | `rg-northwind-tfstate` (DO-NOT-DESTROY; gets the `CanNotDelete` lock) |
| State storage account | **`stnwdental1127`** |
| State container | `tfstate` (keys: `00-foundation.tfstate`, `10-network.tfstate`, `15-access.tfstate`) |
| Key Vault | `kv-northwind-lab` |
| Management lock | `lock-northwind-tfstate-nodelete` |
| Connector VM size | **`Standard_F1als_v7`** (default; B-series is capacity-restricted in eastus) |

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
  there. Store securely without echoing it:
  ```bash
  TF=$(mktemp); printf '%s' 'PASTE_TOKEN' > "$TF"
  az keyvault secret set --vault-name kv-northwind-lab --name twingate-api-token --file "$TF" --output none
  rm -f "$TF"
  ```

## Redeploy all three stacks (order: 00-foundation → 10-network → 15-access)

### 1. `00-foundation` (self-hosting backend — bootstrap)

> **The Storage Blob Data Contributor grant is ALWAYS required on a fresh
> storage account, every time, before `migrate-state` will work** — confirmed on
> three deploys now. **A successful `terraform apply` does NOT mean you can skip
> it**: the apply's container + blob-soft-delete steps are *management-plane* ops
> that Owner already covers, but `migrate-state` writes the state *blob* (a
> *data-plane* write) and needs the role. Full background in `VALIDATION_NOTES.md`.

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

Prereq: the Twingate **Admin** API token is in Key Vault (see Secrets section).

```bash
cd ../15-access
terraform init
terraform plan  -out=tfplan -var='twingate_network_name=YOUR_SLUG'
terraform apply tfplan             # 14 to add; connector_vm_size defaults to F1als_v7
# Then check the Twingate dashboard: the connector should show "Connected"
# within ~1-3 min (VM boot → cloud-init → Docker → connector registration).
```

## Teardown all three (order: 15-access → 10-network → 00-foundation)

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
  final state. Pull state local first.
- **The `CanNotDelete` lock** blocks replacing a tainted-but-healthy storage
  account (`untaint`, don't replace) and blocks destroying the state RG (remove
  it first with `az lock delete`).
- **Twingate**: the API token must have connector-management rights, not just
  read/write. The provider models `protocols` as an attribute and `access_group`
  as a block — don't assume block-vs-attribute by pattern; verify against the
  schema.
- **`eastus` B-series capacity**: `Standard_B1s` was unavailable (`409
  SkuNotAvailable`); the connector defaults to `Standard_F1als_v7`. If that ever
  fails too, `az vm list-skus -l eastus` to find an available small SKU.
