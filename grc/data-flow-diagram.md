# Trust-boundary data-flow diagram

Data flows and the trust-boundary crossings for the lab, each annotated with what
authenticates it. **Legitimate** access flows are solid; the **simulated attack
chain** is overlaid as a distinct dashed-red flow so the compromise path is
visually separate from normal operations. This is the figure to drop into the
methodology / architecture section of a pentest report.

```mermaid
flowchart LR
    subgraph EXT["Untrusted / external"]
      op["Operator"]:::actor
      ci["GitHub Actions / Terraform"]:::actor
      atk["Attacker<br/>(phishing)"]:::attacker
    end

    subgraph ZT["Twingate ZTNA boundary"]
      conn["Twingate Connector<br/>mgmt subnet"]:::infra
    end

    subgraph CORP["corp subnet · AD trust boundary"]
      ws["WS01<br/>(phishing target)"]:::infra
      dc["DC01<br/>(domain controller)"]:::infra
      fs["FS01"]:::infra
    end

    subgraph MP["Azure management plane"]
      arm["ARM / resource providers"]:::infra
    end

    subgraph DP["tfstate storage · data plane"]
      blob[("00-foundation.tfstate<br/>stnwdental1127")]:::store
    end

    %% ---- legitimate flows (auth-labelled boundary crossings) ----
    op ==>|"ZTNA device+identity policy"| conn
    conn ==>|"RDP / WinRM + domain creds"| ws
    conn ==>|"RDP / WinRM + domain creds"| dc
    ci ==>|"OIDC federated credential (no stored secret)"| arm
    arm -->|"provisions"| CORP
    ci ==>|"AAD token · Storage Blob Data Contributor"| blob

    %% ---- simulated attack chain (distinct flow type) ----
    atk -.->|"T1566 phishing payload"| ws
    ws -.->|"T1187 coercion · PetitPotam/PrinterBug"| dc
    dc -.->|"T1557 NTLM relay of DC machine account"| ws
    ws -.->|"T1003.006 DCSync replication rights"| dc

    classDef actor fill:#e7f0ff,stroke:#1c4ed8;
    classDef attacker fill:#ffe3e3,stroke:#e03131;
    classDef infra fill:#f8f9fa,stroke:#495057;
    classDef store fill:#fff1e0,stroke:#d9480f;

    linkStyle 0,1,2 stroke:#2f9e44,stroke-width:2px;
    linkStyle 3,4,5 stroke:#1c4ed8,stroke-width:2px;
    linkStyle 6,7,8,9 stroke:#e03131,stroke-width:2px,stroke-dasharray:6 4;
```

## Boundary crossings and what authenticates each

| Crossing | Flow | Authenticated by |
|---|---|---|
| External → ZTNA | operator → Twingate Connector | Twingate ZTNA policy (device posture + IdP identity); the connector itself has **no inbound ports** |
| ZTNA → corp (AD) | connector → DC01 / WS01 / FS01 | RDP / WinRM with domain credentials (operator is in the Twingate `admins` group) |
| External → Azure management plane | GitHub Actions → ARM | **OIDC federated credential** — short-lived, no stored secret in the repo |
| Management plane → infra | ARM → resources in corp/mgmt | Azure RBAC on the deploying principal |
| Terraform → state (data plane) | CI / operator → tfstate storage | **AAD token** + `Storage Blob Data Contributor` (shared-key auth disabled) |
| Attack chain (illegitimate) | phishing → WS01 → DC01 → relay → DCSync | **nothing legitimate** — this is the simulated compromise the `detections/` rules exist to catch; see `attack-chain/` and `coverage.md` |

## Notes

- The attack chain crosses the **corp AD trust boundary internally** (WS01 → DC01)
  — it never crosses the ZTNA or management-plane boundaries. The ZTNA perimeter
  is assumed already passed (a compromised endpoint session), which is exactly
  what the toggleable red-team path in `15-access` / `10-network` models.
- Every legitimate boundary crossing uses a short-lived or policy-gated credential
  (ZTNA session, OIDC, AAD token) — there are **no long-lived secrets or stored
  cloud credentials** in the repo. Generated secrets live only in Key Vault.
- Keep this diagram in sync with the Terraform; the architecture view in the
  root `README.md` is the resource-level companion to this flow-level view.
