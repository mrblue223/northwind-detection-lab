# Incident response runbook (lab scope, solo operator)

This is deliberately small - a single-person lab doesn't need a full IR
program, but having *something* written down, and following it when a
Sentinel incident fires for real (not as part of a planned attack-chain
run), is itself worth demonstrating.

## Trigger

Any Sentinel incident that fires **outside** a documented attack-chain
window (see `attack-chain/log.md` for what's "expected"). An unexpected
incident means either: a detection rule has a false positive worth tuning,
or something actually happened that you didn't initiate.

## Steps

1. **Don't panic-destroy the environment.** Deallocating compute loses the
   evidence you need to figure out what happened. Investigate first.
2. **Check `attack-chain/log.md` and the admin-path watchlist
   (`detections/07-admin-path-watchlist.md`).** Rule out that this is your
   own activity first - the most common "incident" in a lab is forgetting
   you left the red-team toggle on (see risk register R3) or running
   Ansible during a test window.
3. **Pull the raw logs for the firing rule** in Sentinel (Logs, scoped to
   the incident's time window) and export to `evidence/` for the record.
4. **Check the toggle states** (`enable_redteam_access`,
   `enable_redteam_resource`) against what's committed in `main`. If either
   is `true` in the live environment but `false` in code, that's drift -
   see whether the scheduled drift-detection workflow already opened an
   issue for it.
5. **Check the Twingate admin console** for any session you don't
   recognize, and for the Connector's health/last-seen status.
6. **If something genuinely unexpected occurred:**
   - Revoke the suspect Twingate session/token immediately (console or
     `twingate_connector_tokens` rotation via Terraform).
   - Rotate the domain admin password in Key Vault and re-apply.
   - Snapshot the current state (export logs, note timestamps) before
     doing anything destructive.
   - Only then run `make down` if you need to cut access while you
     investigate further.
7. **Write it up**, even briefly, in `coverage.md` or a dated note under
   `evidence/`. A real incident that happened outside a planned test is
   more interesting material for an interview than another clean
   attack-chain replay - don't discard it.

## What this runbook doesn't cover

Multi-person escalation paths, legal/regulatory notification, and chain of
custody for evidence - all out of scope for a personal lab. If this were
scaled to represent a real small business, those would need to be added
explicitly, not assumed.
