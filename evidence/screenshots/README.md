# Evidence screenshots

Portfolio documentation images, organised by theme. Each subdirectory is tracked
with a `.gitkeep` so the structure exists before the images do. **Capture
evidence live, as each milestone happens during a real deployment / attack-chain
run — not after teardown** (see `TODO.md` at the repo root).

Sanitise before committing: no live secrets, tokens, private keys, real
subscription/tenant IDs, or personal email addresses in any image. Crop or
redact as needed.

## What belongs in each subdirectory

### `00-architecture/`
- A **built architecture diagram** (build it separately as a real diagram — this
  is *not* a screenshot) showing the `mgmt`/`corp` subnets, the Twingate
  Connector, SCAN01, DC01/WS01/FS01, and the access paths between them.
- A capture of the **repo folder structure** (e.g. the `terraform/` + `ansible/`
  + `grc/` layout).

### `01-deployment/`
- A `terraform apply` output showing **resource counts** (e.g.
  `16 added, 0 changed, 0 destroyed`).
- A **clean `terraform plan` showing `0 to destroy`** on a redeploy, proving
  idempotency (no drift).

### `02-twingate/`
- The **Connectors** tab showing **"Connected"** status — Controller **and**
  Relay both green.
- The **Resources** tab showing all the admin resources
  (dc01/ws01/scan01/fs01-admin).

### `03-cicd/`
- The GitHub Actions tab with **all checks green on a real PR**.
- **AND** one screenshot of a **real failing check plus its fix** — e.g. the
  `ansible-lint` `win_domain` deprecation failure, then the green re-run.
  Deliberately show a caught-and-fixed problem, not only successes.

### `04-attack-chain/`
- **One screenshot per detection rule firing in Sentinel**: the alert, its
  timestamp, and the underlying raw log. Captured **during the actual
  attack-chain run** (Phase 4/6), one per stage.

### `05-vuln-scanning/`
- **Nessus scan report** pages from SCAN01, once it actually runs a scan against
  the `corp` subnet.

### `06-grc/`
- The **risk register** and **control mapping** rendered as clean tables (the
  rendered view — not raw-markdown screenshots).

## Naming

Within each subdirectory, prefix files with a two-digit order and a short slug,
e.g. `02-twingate/01-connectors-connected.png`,
`04-attack-chain/03-kerberoasting-incident.png`.
