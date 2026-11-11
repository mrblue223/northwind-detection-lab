# Detection coverage

Fill this in after Phase 6 (validate/harden). This file, more than any
screenshot, is the artifact worth showing in an interview - it demonstrates
honest self-assessment, not just "I built a thing."

## Summary table

| Stage | ATT&CK ID | Detection rule | Fired? | Time to alert | False positives seen | Notes |
|---|---|---|---|---|---|---|
| A: Phishing execution | T1566/T1204 | `01-phishing-execution.kql` | | | | |
| B: C2 callback | T1071/T1105 | `02-c2-callback.kql` | | | | |
| B1: Credential dumping | T1003 | `03-credential-dumping.kql` | | | | |
| B2: Kerberoasting | T1558.003 | `04-kerberoasting.kql` | | | | |
| B3: Lateral movement | T1021 | `05-lateral-movement.kql` | | | | |
| B4: Persistence | T1136/T1053/T1543 | `06-persistence.kql` | | | | |
| B5: Data staging | T1074 | *(no rule written - documented gap)* | N/A | N/A | N/A | See below |
| B2b: Coercion (PetitPotam/PrinterBug) | T1187 | `08-coercion-pipe-access.kql` | | | | Approximation, not a guaranteed catch - see `attack-chain/02b-*.md` |
| B2b: NTLM relay of DC machine account | T1557.001 | `09-ntlm-relay-dc-machine-account.kql` | | | | |
| B2b: DCSync rights abuse | T1003.006 | `10-dcsync-rights-abuse.kql` | | | | Requires the SACL from `ad_domain`'s `add-replication-audit-sacl.ps1` to be applied first |
| C: Password spray | T1110.003 | *(stretch - not written in v1)* | N/A | N/A | N/A | See `attack-chain/03-*.md` |

## Vulnerability scanning (SCAN01 / Nessus)

Separate from the attack-chain detections above - run a scan, attach the
report, and note here what it found vs. what the attack chain actually
exploited:

- Scan date:
- Findings relevant to the attack chain (e.g., did Nessus flag the
  PetitPotam/PrinterBug exposure, or SMB signing being disabled?):
- Findings NOT related to the attack chain (the kind of "noise" a real
  vuln management program has to triage):
- Report location: `evidence/`

## Known gaps (be specific, this is the valuable part)

- **Data staging (T1074):** no rule exists in v1. [Explain why, and what a
  rule would need to look for - e.g. large file-copy volume off FS01 in a
  short window.]
- **Password spray:** left as a stretch exercise; Stage C's optional run
  has no detection rule attached.
- [Add anything else discovered during validation - evasion that worked,
  tools that misbehaved through Twingate, timing issues, etc.]

## False positive testing

Describe what "normal" activity you ran the rules against (e.g. regular
user logons, file browsing, legitimate IT admin work) and what, if
anything, triggered falsely.

## What I'd escalate first, and why

[Your answer - this is the kind of judgment call interviewers actually ask
about.]

## What I'd do differently next time

[Honest retro - architecture choices, tooling friction, anything you'd
change if rebuilding from scratch.]
