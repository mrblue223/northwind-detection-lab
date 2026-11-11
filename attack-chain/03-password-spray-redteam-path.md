# Stage C (optional/stretch): Password spray via the red-team path

Unlike Stages A/B, this runs directly from local Kali through the
toggleable red-team Twingate Resource and NSG rule - a contrast case
showing the "attacker never phished anyone, just has raw network access"
scenario, and how differently it looks in the logs versus Stage A/B.

## Steps

1. Flip both toggles on:
   - `terraform/10-network`: `enable_redteam_access = true`
   - `terraform/15-access`: `enable_redteam_resource = true`
   - `terraform apply` both stacks.
2. From local Kali, confirm reachability to DC01's corp IP (10.10.2.10)
   over the ports opened by the red-team NSG rule (53, 88, 135, 389, 445,
   3268, 3389, 5985, 5986).
3. Run a spray (e.g. `kerbrute passwordspray` or a Netexec-based spray)
   against the roster in `data/users.csv`, using a small common-password
   list - **not** the real `svc_backup` password, to avoid accidentally
   validating the weakness via a different path than intended.
4. Immediately after the test, flip both toggles back to `false` and
   re-apply. Don't leave the red-team path open longer than the test needs.

## No detection rule written for this in v1

This is intentional: write your own `08-password-spray.kql` as an exercise
(many failed 4625 events across many `TargetUserName` values from one
`IpAddress` in a short window is the standard pattern). Treat this stage as
the stretch goal it's labeled as in `PLAN.md`, and use it as evidence of
extending the project past the guided MVP.
