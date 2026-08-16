---
name: aws-zero-downtime
description: >
  Applies a curated availability and continuity control catalog to AWS
  architectures — multi-AZ topology, cells and static stability, blue/green and
  canary deployment, data continuity and failover, graceful degradation — and
  emits Terraform plus a control-coverage matrix. Use whenever the user
  describes an AWS system to design or review, asks about uptime, availability,
  resilience, failover, rollback, deployment strategy, RPO/RTO, disaster
  recovery, maintenance windows, or how to ship without an outage — even if
  they never say "zero downtime".
---

# AWS Zero Downtime

A control catalog for availability and continuity. Every control carries an ID,
an upstream authority, and — where one exists — an executable check.

The operating premise: **failure is continuous, so availability is a property of
how a system behaves during failure, not of how rarely failure occurs.** Every
control here either contains a failure, survives one, or proves the system can.

## Using this skill

**Standalone** — answering a resilience question or reviewing a design. Read
`references/control-catalog.md`, then the one or two domain files the question
touches. Do not load all four.

**Under the orchestrator** — `aws-solution-architect` drives intake, tier
selection, generation, and the validate/repair loop. This skill supplies the
catalog, the modules, and the policies.

## Selecting controls

| Signal in the brief | Domain file | Prefix |
|---|---|---|
| AZs, Regions, cells, blast radius, failover, static stability | `references/topology.md` | ZD-TOP |
| Releases, rollout, rollback, CI/CD, canary, maintenance window | `references/deployment.md` | ZD-DEP |
| Backups, replication, RPO/RTO, schema change, DR | `references/data-continuity.md` | ZD-DAT |
| Retries, timeouts, throttling, draining, overload, brownout | `references/degradation.md` | ZD-DEG |

Apply the obligation matrix in
`aws-solution-architect/references/tier-model.md`. Criticality drives most of
this catalog harder than it drives Zero Trust: a tier-2 internal tool
legitimately runs in one AZ, and telling its owner otherwise wastes their money
and your credibility.

## Where the checks live

Unlike `aws-zero-trust`, this catalog's checks are split across two validator
stages, and the split is deliberate:

| Check kind | Where | Why |
|---|---|---|
| Resource-shape assertions (encryption on a backup, a missing attribute) | `policies/opa/*.rego`, validator Stage 2 | Expressible as a rule over one resource |
| Architectural invariants (AZ spread, capacity survives N-1) | `validate.sh` Stage 4 | Require reasoning across resources and the criticality tier |

A control's `check` field names which. **Stage 4 checks are tier-aware** — the
same plan passes at tier 1 and fails at tier 0 — which is why they cannot be
plain Rego rules.

## Applying controls

- Compose from `assets/terraform/` modules; write new resources only where no
  module fits, and say so per resource.
- Cite `id` and `authority` for every control applied.
- A control with no check is advice — render it `recommended`, never
  `satisfied`.
- **Static stability is the discriminating idea in this catalog.** Where a
  control offers a choice between reacting to failure and pre-provisioning for
  it, prefer pre-provisioning at tier 0. A system that must successfully call a
  control plane in order to survive an event has made its recovery depend on the
  thing most likely to be impaired.

## Exceptions

Each control's `exceptions` list encodes the legitimate paths. To waive: the
situation must match a recorded condition, and the compensating control named in
`requires` must itself be satisfied.

The most commonly abused waiver here is "we have a maintenance window." A
maintenance window is a real exception when the business has genuinely agreed to
one — and a way of avoiding the work when it has not. Record who agreed.

## Catalog status

**Pre-review.** Controls were extracted from verified upstream
sources but have not been through Phase 1.3 human sign-off. Every control
carries `authority`; **none carries `kb_source`**, because no curated house
knowledge base exists yet. State this in any deliverable.

## Non-negotiables

- Never claim a control is satisfied without a passing check or a module
  reference.
- Never renumber a control ID. Five ZD IDs are already referenced by name in
  `validate.sh` Stage 4 — renumbering them silently breaks the validator.
- Never assert an availability figure the architecture does not support. If the
  brief asks for four nines and the design gives three, say so.
- Never treat "it has not failed yet" as evidence. Untested recovery is a
  hypothesis (ZD-DAT-005, ZD-DEP-005).
