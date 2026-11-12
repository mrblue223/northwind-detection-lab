# Session status — 2026-11-12

Snapshot for picking the work back up. Written right after a deliberate full
teardown of `00-foundation` (a rebuild-story test, not cost-driven — this stack
is ~$0 either way).

## What is currently deployed in Azure

**Nothing.** `00-foundation` was fully destroyed (`terraform destroy`: 15
destroyed; the management lock was removed out-of-band first). Confirmed with
`az group list` — **no `rg-northwind-lab` and no `rg-northwind-tfstate`** remain.
No other stack (05/10/15/20/30/40) has ever been applied. The subscription is
back to empty for this project.

## Repository state (branch `main`)

All work is merged; **no open PRs**:

| PR | Title | State |
|----|-------|-------|
| #1 | Pin GitHub Actions to current release commit SHAs | merged |
| #2 | Add cloud governance hardening (locks, Defender free tier, activity log alerts) | merged |
| #3 | Add `storage_use_azuread` for keyless state backend; document bootstrap RBAC | merged |

`main` contains the full, CI-green `00-foundation` (foundation + governance +
hardening), the themed storage account name, and the bootstrap docs. CI (fmt,
TFLint, ansible-lint, Checkov, gitleaks, terraform-plan graceful-skip) passes.

## Names you'll need tomorrow (non-sensitive)

| Thing | Value |
|-------|-------|
| Project prefix | `northwind` (storage uses the short form `nwdental`) |
| Region | `eastus` |
| Lab resource group | `rg-northwind-lab` (teardown: safe-to-destroy) |
| State resource group | `rg-northwind-tfstate` (teardown: DO-NOT-DESTROY; gets the `CanNotDelete` lock) |
| State storage account | **`stnwdental1127`** (globally unique; change the numeric suffix if it ever collides) |
| State container / key | `tfstate` / `00-foundation.tfstate` |
| Key Vault | `kv-northwind-lab` |
| Management lock | `lock-northwind-tfstate-nodelete` |

## IDs that are deliberately NOT stored here (public repo — R7)

This repo is public, so the subscription id, tenant id, your principal's
objectId, and your email are **not** hardcoded. Fetch them at redeploy time:

- Subscription / tenant: `az account show -o json` (Terraform/az use the logged-in
  default subscription automatically — nothing to hardcode).
- Your objectId (for the RBAC grant below): `az ad signed-in-user show --query id -o tsv`
- Budget email: pass your own address via `-var`, as in the sequence below.

## Redeploy `00-foundation` from scratch (exact sequence)

This is a self-hosting backend (the state lives in the storage account this
stack creates), so the first apply is a bootstrap with the backend commented
out. Full background for every step is in `VALIDATION_NOTES.md`
("First-deploy bootstrap of 00-foundation").

```bash
cd terraform/00-foundation

# 1. Bootstrap: comment OUT the `backend "azurerm" { ... }` block in providers.tf
#    (local state), because the state storage account does not exist yet.

# 2. Init (local state) + first apply. Save the plan and apply it explicitly.
terraform init
terraform plan  -out=tfplan -var='budget_alert_emails=["YOUR_EMAIL_HERE"]'
terraform apply tfplan
#    This FAILS on the storage account with 403 KeyBasedAuthenticationNotPermitted,
#    because shared_access_key_enabled = false and the caller has no blob-data role.
#    (storage_use_azuread = true is already set on the provider — that half is done.)

# 3. One-time RBAC grant: Storage Blob Data Contributor, scoped to the account.
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
SUB=$(az account show --query id -o tsv)
az role assignment create \
  --assignee "$OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB/resourceGroups/rg-northwind-tfstate/providers/Microsoft.Storage/storageAccounts/stnwdental1127"
#    Wait ~1 min for RBAC to propagate.

# 4. Finish the apply. The storage account is created-but-tainted; the CanNotDelete
#    lock would block REPLACING it, so untaint (it's healthy) and apply in-place.
terraform untaint azurerm_storage_account.tfstate
terraform plan  -out=tfplan2 -var='budget_alert_emails=["YOUR_EMAIL_HERE"]'
terraform apply tfplan2        # 1 added (container) + 1 changed (blob soft-delete)

# 5. Migrate state into the backend: RESTORE (uncomment) the backend block, then:
terraform init -migrate-state -force-copy
#    Then delete the local terraform.tfstate / .tfstate.backup — the backup keeps
#    the generated domain-admin password in plaintext. Both are gitignored.
```

### Teardown again (if needed), cleanly

```bash
az lock delete --name lock-northwind-tfstate-nodelete --resource-group rg-northwind-tfstate
# comment OUT the backend block, then pull state local so destroy doesn't delete its own backend:
terraform init -migrate-state -force-copy
terraform plan -destroy -out=destroyplan -var='budget_alert_emails=["YOUR_EMAIL_HERE"]'
terraform apply destroyplan
rm -f terraform.tfstate terraform.tfstate.backup
az group list --query "[?contains(name,'northwind')].name" -o tsv   # expect: empty
# restore (uncomment) the backend block afterwards
```

## Known gotchas (see VALIDATION_NOTES.md for detail)

- Keyless state storage needs `storage_use_azuread = true` (done) **and** the
  caller holding **Storage Blob Data Contributor** on the account — Owner is not
  enough (management-plane only).
- The `CanNotDelete` lock blocks *replacing* a tainted-but-healthy storage
  account — `untaint`, don't replace.
- Never `terraform destroy` with the remote backend still active, or it deletes
  the storage account holding its own state and fails to persist final state —
  pull state local first.
