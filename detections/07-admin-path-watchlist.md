# Admin-path watchlist

Because you administer the lab through the same Twingate Connector that
carries no other traffic, admin sessions all appear to originate from the
Connector's private IP (`10.10.1.10` per `15-access` defaults). Left
unaddressed, this pollutes every detection above with your own activity.

## Setup

In Sentinel: **Watchlists > + New > Northwind-KnownAdminPath**, with a single
row:

| SearchKey      | Value         | Description                          |
|-----------------|---------------|---------------------------------------|
| connector_ip    | 10.10.1.10    | Twingate connector - known admin path |

## Usage in queries

Join or filter against the watchlist instead of hardcoding the IP, so the
exclusion is auditable and lives in one place:

```kql
let AdminPaths = (_GetWatchlist("Northwind-KnownAdminPath") | project connector_ip);
SecurityEvent
| where EventID == 4624
| where IpAddress !in (AdminPaths)
```

## Operational rule for the lab

Never run Ansible, RDP, or any admin task during an active attack-chain
window (Phase 4). This keeps the timeline unambiguous without relying on
the exclusion at all, and the exclusion becomes a secondary safety net
rather than the thing doing the real work. Document any admin activity
that does happen during a test run in `attack-chain/log.md` so it can be
explained in `coverage.md`.
