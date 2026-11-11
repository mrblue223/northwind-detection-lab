# Attack run log

Copy this into `log.md` (gitignored by default - sanitize before committing
a real copy) and fill in during each run.

## Run metadata
- Date/time started (UTC):
- Run type: Stage A/B full chain | Stage C password spray | other
- Operator:

## Timeline

| Timestamp (UTC) | Stage | Host | Action | ATT&CK ID | Notes |
|---|---|---|---|---|---|
| | A | WS01 | Payload delivered/executed | T1566/T1204 | |
| | B1 | WS01 | LSASS dump | T1003 | |
| | B2 | WS01->DC01 | Kerberoast request | T1558.003 | |
| | B3 | WS01->FS01 | Lateral movement | T1021 | |
| | B4 | FS01/WS01 | Persistence | T1136/T1053/T1543 | |
| | B5 | FS01->WS01 | Data staging | T1074 | |

## Admin activity during this run (should be none - see detections/07)

| Timestamp (UTC) | Action | Reason |
|---|---|---|
| | | |

## Post-run checklist
- [ ] All timestamps recorded above
- [ ] Raw logs exported for each stage (Sentinel: Logs > export to CSV/JSON into `evidence/`)
- [ ] Sentinel incidents screenshot captured per firing rule
- [ ] Red-team toggles (if Stage C) flipped back to `false` and re-applied
