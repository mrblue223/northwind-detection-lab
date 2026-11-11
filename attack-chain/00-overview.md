# Attack chain overview

A two-stage chain: a simulated phishing compromise of WS01 (stage A), followed
by post-exploitation that pivots from WS01's own legitimate network position
rather than from Kali directly (stage B). A separate, optional stage (C) runs
a password spray directly from Kali through the toggleable red-team Twingate
resource, as a contrast case.

| Stage | Step | ATT&CK ID | Detection file |
|---|---|---|---|
| A | Phishing payload delivered/executed on WS01 | T1566, T1204 | `01-phishing-execution.kql` |
| B | C2 callback from WS01 | T1071, T1105 | `02-c2-callback.kql` |
| B | Credential dumping (LSASS access) | T1003 | `03-credential-dumping.kql` |
| B | Kerberoasting the weak service account | T1558.003 | `04-kerberoasting.kql` |
| B | Lateral movement WS01 -> FS01 | T1021 | `05-lateral-movement.kql` |
| B | Persistence (group/service/task) | T1136, T1053, T1543 | `06-persistence.kql` |
| B | Data staging from FS01 share | T1074 | (not alerted in v1 - documented gap) |
| B2b | Coercion (PetitPotam/PrinterBug) of DC01 | T1187 | `08-coercion-pipe-access.kql` |
| B2b | NTLM relay of DC01's machine account | T1557.001 | `09-ntlm-relay-dc-machine-account.kql` |
| B2b | DCSync via granted replication rights | T1003.006 | `10-dcsync-rights-abuse.kql` |
| C (optional) | Password spray via red-team Resource | T1110.003 | (stretch goal) |

See `02b-coercion-ntlmrelay-dcsync.md` for why this replaced a classic
LLMNR/NBT-NS poisoning stage: Azure VNets block all multicast/broadcast
traffic, even within a single subnet, which is exactly what LLMNR and
NBT-NS depend on to reach a listener.

## Rules for running this safely

1. Never point SET or any payload at real email infrastructure or real
   people. Everything happens inside the isolated lab VNet.
2. Run the listener on the `mgmt`-subnet relay VM, not on local Kali, so the
   WS01 -> listener traffic never has to traverse Twingate (see
   `01-initial-access-phishing.md`).
3. Flip `enable_redteam_access` (10-network) and `enable_redteam_resource`
   (15-access) to `true` only for the duration of stage C, then back to
   `false` immediately after.
4. Do not run any admin/Ansible task during an active attack window - keep
   the telemetry timeline unambiguous (see `detections/07-admin-path-watchlist.md`).
5. Log every step with a timestamp in `log.md` (template below) as you go -
   reconstructing this after the fact is much harder.

See `log-template.md` for the format to copy into `log.md` during a real run.
