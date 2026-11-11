# Defense in depth: what CI/CD catches, and what it structurally can't

A clean CI/CD pipeline with Checkov, TFLint, and gitleaks passing on every
PR is good hygiene, but it is not the same thing as a secure system. This
project is built to make that distinction visible rather than paper over
it - the gap between "pipeline is green" and "system is safe" is exactly
why Sentinel and the detection layer exist alongside the preventive layer.

## What the preventive layer (CI/CD, Policy-as-code, least privilege) covers

- **Known misconfiguration patterns.** Checkov and TFLint catch things like
  a storage account without TLS enforcement, an NSG rule open to
  `0.0.0.0/0`, or a resource missing encryption settings - patterns that
  show up in published rule sets because they're common and well understood.
- **Drift from committed intent.** Policy-as-code (`05-policy`) and the
  drift-detection workflow enforce and verify that live infrastructure
  matches what's reviewed in a PR, closing the gap between "the README says
  no public IPs" and "nothing can actually get a public IP."
- **Secret leakage via committed code.** Gitleaks catches an API key or
  password accidentally typed into a file that gets committed.
- **Excess privilege as a static property.** Twingate's per-resource
  access model and the admin/red-team group separation limit blast radius
  *by construction*, independent of whether any specific attack is detected.

## What none of that catches

- **Business-logic weaknesses that pass every scanner.** `svc_backup`
  (the deliberately Kerberoastable account) has a properly encrypted disk,
  a compliant NSG, and a clean Checkov scan. Nothing about it looks wrong
  to a static tool - the weakness is in how the account is *used*, not in
  any resource's configuration.
- **Supply chain risk in things the pipeline trusts by default.** The
  Twingate connector's container image, the Sysmon binary pulled from
  Sysinternals at Ansible runtime, and every pinned GitHub Action are all
  things CI/CD executes rather than inspects. A compromised upstream
  artifact passes every check that only looks at *this repo's* code.
- **Drift that happens outside a commit.** Someone (including you, in the
  Azure portal, in a hurry) opens a port manually. No PR, no scan, no
  gitleaks run - the scheduled drift-detection job is the only thing in
  this project that would ever notice, and only on its next run.
- **Novel techniques and zero-days.** A ruleset can only encode patterns
  someone has already written a rule for. Nothing here claims to catch
  what hasn't been seen before.
- **The gap between "scanned" and "running as intended."** A Terraform
  plan that passes Checkov still has to actually be applied correctly,
  against the right subscription, by a pipeline whose own permissions
  (the OIDC federated identity) are themselves a thing that needs to be
  scoped correctly and could be a target.

## Why detection is the other half, not a redundant one

Every gap above is a reason the Sentinel layer in this project exists.
Prevention reduces how much can go wrong and how easily; detection is what
catches it when something does anyway - including the exact classes of
failure (business logic, supply chain, manual drift, novel technique) that
no amount of pipeline hygiene addresses. `coverage.md`'s honest gap list
(e.g., no rule written for data staging) is the detection layer's version
of the same discipline this document applies to the preventive layer:
stating plainly what is and isn't covered, rather than implying completeness
either side doesn't have.

## The practical takeaway for this project

Nothing here is a reason to skip CI/CD, policy-as-code, or least privilege -
each measurably reduces risk and is worth having. It's a reason not to
describe the result as "secure" in an unqualified way, in this project or
in a real one. "Here's what's prevented, here's what's detected, here's
what's neither" is a more credible claim than either alone, and it's the
claim this document is making on purpose.
