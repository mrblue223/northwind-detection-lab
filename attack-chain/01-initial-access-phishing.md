# Stage A: Initial access via simulated phishing

**ATT&CK:** T1566 Phishing, T1204 User Execution
**Target:** WS01, logged on as `lchen` (standard user, no elevated rights)

## Why the listener lives in Azure, not on local Kali

WS01 is reached via Twingate going outbound from your machine. A reverse
shell needs the opposite direction: WS01 connecting back to the attacker.
That connection won't reliably traverse Twingate's admin-access model. Fix:
run the actual listener on a small relay VM inside the `mgmt` subnet (same
subnet as the Twingate Connector) so WS01 -> listener traffic stays entirely
inside the VNet. Kali only operates that relay VM remotely, over the normal
admin Twingate path.

## Steps

1. **Stand up the relay VM** (small Linux B1s, `mgmt` subnet, no public IP -
   add it to `15-access` as an additional admin Resource if not already
   present).
2. **On the relay VM**, generate the payload with SET (Social-Engineer
   Toolkit):
   - Attack vector: PowerShell payload or a Meterpreter stager.
   - Listener: Metasploit `multi/handler` bound to the relay VM's private IP
     (`10.10.1.x`), not `0.0.0.0` on a public interface.
3. **Deliver the payload to WS01.** For v1, skip real email entirely:
   - RDP/WinRM to WS01 as `lchen` via the admin Twingate Resource.
   - Manually download/execute the payload from the relay VM's internal IP,
     standing in for "user clicks the link/attachment."
   - *(Stretch goal: stand up a throwaway Postfix instance pointed only at
     the lab and have the payload actually arrive via a local mail client,
     for a more literal simulation. Not required for v1 - diminishing
     realism gain for a lot of extra setup.)*
4. **Confirm the callback** lands on the relay VM's listener.
5. **Log the timestamp** of execution in `log.md` - this is the anchor point
   `detections/01-phishing-execution.kql` should catch, and everything in
   Stage B is timed relative to it.

## What "success" looks like

- Sysmon Event ID 1 on WS01 shows a suspicious child process spawned from
  the simulated delivery mechanism (e.g. PowerShell from a script/download
  context).
- `01-phishing-execution.kql` fires in Sentinel within a few minutes
  (`query_frequency = PT10M` in `40-sentinel/main.tf`).
- The relay VM's listener shows an active session from WS01's private IP.

Proceed to `02-post-exploitation.md` once this is confirmed.
