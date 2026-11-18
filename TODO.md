# TODO

Tracked, cross-cutting work items that don't belong to a single stack or role.

## Evidence screenshots (portfolio documentation)

**Capture evidence screenshots per `evidence/screenshots/README.md` during the
next real deployment / attack-chain run — don't wait until after teardown,
capture live as each milestone happens.** (The connector only shows "Connected"
while it's up; Sentinel incidents only exist during the attack run; a failing-CI
screenshot has to be grabbed before the fix merges.)

Per-category checklist (details + what each should show are in
`evidence/screenshots/README.md`):

- [ ] `00-architecture/` — built architecture diagram + repo structure capture
- [ ] `01-deployment/` — apply output with resource counts; a `0 to destroy` plan (idempotency)
- [ ] `02-twingate/` — Connectors tab "Connected" (Controller + Relay green); Resources tab
- [ ] `03-cicd/` — all-green checks on a real PR; **plus** a real failing check + its fix
- [ ] `04-attack-chain/` — one Sentinel detection firing per stage (alert + timestamp + raw log)
- [ ] `05-vuln-scanning/` — Nessus scan report pages from SCAN01 against `corp`
- [ ] `06-grc/` — risk register + control mapping rendered as clean tables

Sanitise before committing: no live secrets/tokens/keys, real subscription/tenant
IDs, or personal emails in any image.

## CI/CD Azure OIDC identity — never actually configured (needs a dedicated session)

`ci.yml`'s Terraform-plan job and `drift-detection.yml` have been **failing since
creation**: they call `azure/login` with `client-id`/`tenant-id`/`subscription-id`
from the `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` repo
secrets, and **those secrets don't exist**. Every scheduled drift run dies at the
`azure/login` step in ~25s (`Not all values are present. Ensure 'client-id' and
'tenant-id' are supplied`) and never reaches `terraform plan` — so drift detection
has never actually run. All real deploys so far have been local via `az` CLI.

Needs a **dedicated session** — this is a real security decision about what CI is
allowed to touch, not a quick fix:

- [ ] Entra **app registration** for GitHub Actions CI.
- [ ] **Federated credential** scoped to **this repo** (and ideally specific
      branches/environments), so no long-lived secret is ever stored.
- [ ] A **narrowly-scoped role assignment** — scoped to the lab resource
      group(s), **not** subscription-wide. Decide deliberately what plan/apply
      actually needs (and note that remote-state access needs
      `Storage Blob Data` on the state account specifically).
- [ ] Record the grant + its scope rationale in `grc/risk-register.md`.

**Do not rush this.** Handing CI broad rights is exactly the kind of thing this
lab is meant to model doing correctly.

## Minor doc cleanup (deferred — not worth a PR on their own)

Low-priority consistency fixes noted during the 2026-11-13 repo audit; roll them
into the next doc PR that touches these files:

- [ ] `Makefile` — `STACKS` omits `30-identity`; reconcile or add a comment
      explaining why (identity is applied separately).
- [ ] `README.md` — the `evidence/` line in "Repo layout" predates the
      `evidence/screenshots/` substructure; mention it.
- [ ] `coverage.md` — "Report location: `evidence/`" could point at
      `evidence/screenshots/04-attack-chain` + `05-vuln-scanning`.
