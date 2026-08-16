# Intake Schema

The structured brief every concept is normalized into before any control is
selected. Workflow step 1.

Fields marked **required** must be filled or explicitly recorded as an
assumption. An assumption is a first-class output: it appears in the deliverable
header, so the reader can challenge the premise rather than only the design.

---

## Schema

```yaml
# ---- identity -------------------------------------------------------------
name: "Claims intake API"                      # required
description: >                                 # required
  One paragraph in the user's own framing. Do not editorialize; the brief is
  the record of what was asked for.
requested_by: null
date: 2026-08-15                               # required

# ---- criticality ----------------------------------------------------------
criticality: 1                                 # required — 0 | 1 | 2
criticality_reason: >                          # required — see tier-model.md
  Internal PII, no external SLA, one-hour outage disrupts one team.
mixed_criticality: false                       # true → partition and re-brief

# ---- regulatory -----------------------------------------------------------
compliance_regimes: []                         # e.g. [HIPAA, PCI-DSS, SOC2]
data_classification: internal-pii              # public | internal | confidential
                                               #   | internal-pii | regulated
data_residency: null                           # e.g. "EU only"

# ---- platform assumptions -------------------------------------------------
# These change which controls apply. Guessing them is the most common cause of
# an architecture that is correct in the abstract and wrong for the org.
account_model: unknown                         # required — see below
landing_zone: unknown                          # control-tower | lza | custom
                                               #   | none | unknown
existing_network: unknown                      # greenfield | extends-existing
regions: []                                    # required — [] means ask
iac_language: terraform                        # terraform | cdk | cloudformation
will_be_applied: false                         # required — see below

# ---- shape ----------------------------------------------------------------
compute: []                                    # ecs-fargate | eks | ec2 | lambda
                                               #   | batch | other
datastores: []                                 # rds-postgres | aurora | dynamodb
                                               #   | s3 | elasticache | other
exposure: internal                             # required — public-internet
                                               #   | internal | partner-vpn
                                               #   | on-prem-only
consumers: []                                  # human-users | services
                                               #   | third-party | batch
protocols: [https]                             # https | grpc | tcp | mqtt | other

# ---- continuity -----------------------------------------------------------
rpo: null                                      # e.g. "5m" — null means ask
rto: null                                      # e.g. "1h"
release_frequency: null                        # daily | weekly | monthly | rare
maintenance_window: null                       # null → treat as zero-downtime
traffic_profile: null                          # steady | diurnal | spiky | batch

# ---- boundaries -----------------------------------------------------------
out_of_scope: []                               # things the user has excluded
known_constraints: []                          # e.g. "must reuse existing TGW"
assumptions: []                                # auto-populated from unfilled
                                               #   required fields
```

---

## Field notes

**`criticality`** — the single highest-leverage field. It gates the obligation
matrix in `tier-model.md`. Ask if unstated. Do not infer it from the user's
tone; enthusiasm is not criticality.

**`account_model`** — required, and the field most often skipped. Values:

| Value | Meaning |
|---|---|
| `single-account` | Everything in one account |
| `multi-account-manual` | Several accounts, no landing zone automation |
| `control-tower` | AWS Control Tower governs OUs and guardrails |
| `landing-zone-accelerator` | LZA deployment |
| `unknown` | **Ask.** Do not assume. |

This is open decision #3 from the implementation plan, resolved here rather than
implied in the catalog. Generated architectures differ substantially depending
on whether OU-level guardrails already exist — a control that Control Tower
already enforces should not be re-implemented in the workload, and a control it
does *not* enforce must not be assumed away.

**`will_be_applied`** — open decision #2, made explicit per brief.
`false` means the output is generation-only: no state backend, no credentials,
no execution. This removes an entire class of security requirements from the
generator itself. If a user asks for `true`, the answer is still that this skill
does not apply IaC — the flag exists so the deliverable can say who will, and
so the plan can be written for a human-gated pipeline rather than a direct run.

**`exposure`** and **`consumers`** together drive most ZT-NET applicability.
`public-internet` + `human-users` pulls in Verified Access and edge controls;
`internal` + `services` pulls in service-to-service authorization instead.
Getting these wrong produces a plausible architecture solving the wrong problem.

**`maintenance_window: null`** is treated as *zero-downtime required*, not as
"unspecified." This is a deliberate asymmetry: assuming a window exists when it
does not produces a design that cannot be deployed, whereas assuming none exists
produces a design that is merely more careful than necessary.

**`rpo` / `rto`** — null means ask, for criticality 0 and 1. At criticality 2,
null may be recorded as an assumption and the tier defaults applied.

**`out_of_scope`** — record what the user excluded, verbatim. Without it, the
not-applied list in the deliverable cannot distinguish "excluded by the user"
from "we decided against it," and those are very different conversations.

---

## Normalization rules

1. **Preserve the user's framing in `description`.** The brief is evidence of
   what was asked. Rewriting it into architecture vocabulary loses the ability
   to check later whether the right thing was built.
2. **Never fill a required field silently.** Unfilled → an `assumptions` entry
   naming the field, the value used, and why.
3. **Ask at most once, batched.** Collect every open question and ask them
   together. Serial interrogation is worse than a single well-formed question
   list, and the user usually knows several answers at once.
4. **Re-brief on contradiction.** If the concept implies criticality 0 (regulated
   data) but the user stated tier 2, surface the conflict rather than resolving
   it silently in either direction.

---

## Worked example

```yaml
name: "Claims intake API"
description: >
  Public-facing API where insurance brokers submit claims documents. Needs to
  be up during business hours, holds claimant PII, replaces a legacy on-prem
  service that had a nightly maintenance window.
date: 2026-08-15

criticality: 0
criticality_reason: >
  Regulated data (claimant PHI), external partner SLA, and a breach triggers
  mandatory disclosure. Broker-facing outage stops claim submission entirely.
mixed_criticality: false

compliance_regimes: [HIPAA]
data_classification: regulated
data_residency: "US only"

account_model: control-tower
landing_zone: control-tower
existing_network: extends-existing
regions: [us-east-1]
iac_language: terraform
will_be_applied: false

compute: [ecs-fargate]
datastores: [aurora, s3]
exposure: public-internet
consumers: [third-party, services]
protocols: [https]

rpo: "5m"
rto: "1h"
release_frequency: weekly
maintenance_window: null          # → zero-downtime required
traffic_profile: diurnal

out_of_scope:
  - "Broker identity provider — already exists, federated via existing IdP"
known_constraints:
  - "Must attach to existing Transit Gateway in the network account"
assumptions:
  - field: regions
    value: [us-east-1]
    reason: "User said 'US only'; single Region assumed pending confirmation.
             At criticality 0 the tier model expects a multi-Region strategy —
             flagged for the user rather than silently designed around."
```

Note the last assumption. It records a tension between the brief and the tier
model instead of resolving it unilaterally. That is the correct behavior: the
architecture proceeds, the conflict is visible, and the user decides.
