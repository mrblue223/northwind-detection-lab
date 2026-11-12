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

> **The Storage Blob Data Contributor grant (step 3) is ALWAYS required on a
> fresh storage account — every time, before `migrate-state` will work.** This
> has now been confirmed on two separate deploys; it is unconditional, not a
> "do this if you hit an error" step.
>
> **A successful `terraform apply` does NOT mean you can skip the grant.** The
> apply creates the container and blob soft-delete through the Azure *management*
> plane, which your **Owner** role already covers — so the apply succeeds with no
> blob-data role at all. But `terraform init -migrate-state` writes the actual
> state *blob*, which is a true *data-plane* write and needs **Storage Blob Data
> Contributor** (shared keys are disabled). A clean apply is the exact misleading
> signal that tempts you to jump straight to migrate-state without the grant —
> don't. Do the grant every time.

```bash
cd terraform/00-foundation

# 1. Bootstrap: comment OUT the `backend "azurerm" { ... }` block in providers.tf
#    (local state), because the state storage account does not exist yet.

# 2. Init (local state) + apply. Save the plan and apply it explicitly.
#    With storage_use_azuread = true already in the code, this SUCCEEDS cleanly:
#    16 to add, 0 change, 0 destroy. (The 403 / tainted-account behaviour only
#    happened on the very first deploy, before the storage_use_azuread fix.)
terraform init
terraform plan  -out=tfplan -var='budget_alert_emails=["YOUR_EMAIL_HERE"]'
terraform apply tfplan

# 3. ALWAYS-REQUIRED grant before migrate-state (see the note above): Storage
#    Blob Data Contributor, scoped to the account. Do this every time on a fresh
#    account, EVEN THOUGH the apply above succeeded.
OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
SUB=$(az account show --query id -o tsv)
az role assignment create \
  --assignee "$OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB/resourceGroups/rg-northwind-tfstate/providers/Microsoft.Storage/storageAccounts/stnwdental1127"

# 4. Migrate state into the backend: RESTORE (uncomment) the backend block, then:
terraform init -migrate-state -force-copy
#    Data-plane RBAC propagation lags ~1-5 min, so this can 403 with
#    AuthorizationPermissionMismatch on the first try even though the role is
#    assigned. It leaves state unmodified on failure — just retry until it works.
#    Then delete the local state (the .backup keeps the domain-admin password in
#    plaintext; both are gitignored):
rm -f terraform.tfstate terraform.tfstate.backup
```

> Contingency (not the happy path): if an apply ever *partially* fails and leaves
> the storage account `tainted`, the `CanNotDelete` lock blocks REPLACING it —
> `terraform untaint azurerm_storage_account.tfstate` and re-apply in-place
> instead of letting Terraform destroy/recreate it.

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
  enough (it covers management-plane ops only). The `terraform apply` succeeds
  *without* the data role (container + blob props are management-plane), but
  `migrate-state` writes the state blob (data-plane) and **always** needs the
  role — a clean apply is not a signal that the grant can be skipped. Grant it
  on every fresh account.
- The `CanNotDelete` lock blocks *replacing* a tainted-but-healthy storage
  account — `untaint`, don't replace.
- Never `terraform destroy` with the remote backend still active, or it deletes
  the storage account holding its own state and fails to persist final state —
  pull state local first.
