---
name: aws-solution-architect
description: >
  Turns a solution concept into a validated AWS architecture — Terraform plus a
  traceable control-coverage matrix — grounded in a curated control catalog
  rather than model recall. Normalizes the brief, selects controls by
  criticality tier, composes vetted modules, runs a deterministic validation
  gate, and repairs until clean. Use whenever the user describes an AWS system
  to design, build, or review; asks for an architecture, landing zone, network
  design, or Terraform for AWS; or asks whether a design is secure, resilient,
  or production-ready — even if they never say Zero Trust, zero downtime, or
  compliance.
---

# AWS Solution Architect

Orchestrates intake → control selection → generation → validation → repair.
This skill holds workflow and routing only. All substance lives in the control
catalogs of `aws-zero-trust` and `aws-zero-downtime`.

## Preconditions

Check these before doing anything else. **If a precondition fails, say so and
stop — do not proceed with an ungrounded design.** A confident architecture
backed by nothing is the specific failure this system exists to prevent.

| Requirement | How to check | If missing |
|---|---|---|
| A promoted control catalog | `aws-zero-trust/references/control-catalog.md` exists | Report which domains are unavailable. Offer to run against candidate records in `knowledge-base/extracted/`, clearly labelled as unreviewed. |
| Catalog version | Read `catalog_version` from the catalog header | Record it in the deliverable. Never emit output without one. |
| Retrieval corpus | `scripts/kb_search.py --status` exits 0 | Continue, but every claim not covered by a catalog control is `UNGROUNDED`. |

State the catalog version and any degraded preconditions in the deliverable
header. The reader must be able to tell what the output was actually built from.

## Workflow

**1. Normalize the concept into the intake brief.**
Read `references/intake-schema.md`. Fill every required field.
If criticality tier is unstated, **ask** — do not assume tier-0. Over-assumption
produces carpet-bombed architectures that are unusable, which is the more common
failure of this system than under-protection.
Record unresolved fields as explicit assumptions; never silently default them.

**2. Determine the applicable control set.**
Read `references/tier-model.md` to convert criticality into obligation.
Then read the domain catalogs — the index first, and only the domain files the
intake actually touches:

| Intake signal | Load |
|---|---|
| Any VPC, subnet, security group, ingress, service mesh | `aws-zero-trust/references/network.md` |
| Users, roles, federation, SSO, cross-account access | `aws-zero-trust/references/identity.md` |
| Containers, Lambda, service-to-service calls, mTLS | `aws-zero-trust/references/workload-identity.md` |
| Storage, databases, PII, encryption, key management | `aws-zero-trust/references/data-protection.md` |
| Logging, detection, audit, monitoring | `aws-zero-trust/references/verification.md` |
| Multi-AZ, multi-Region, cells, failover | `aws-zero-downtime/references/topology.md` |
| Releases, rollout, rollback, CI/CD | `aws-zero-downtime/references/deployment.md` |
| Schema change, replication, backup, RPO/RTO | `aws-zero-downtime/references/data-continuity.md` |
| Retries, timeouts, draining, overload | `aws-zero-downtime/references/degradation.md` |

Evaluate each control's `applies_when` against the brief. A control that does
not apply is not a gap — but record the determination, because "we considered
and excluded it" and "we never looked" are different claims.

**3. Retrieve anything the catalog does not cover.**
Run `scripts/kb_search.py "<query>" --domain <domain> --top-k 5` **before**
answering from general knowledge. Cite returned snippets by `kb_uri`.
Any claim backed by neither a catalog control nor a retrieved snippet is marked
`UNGROUNDED` in the output. Do not omit it — mark it. A labelled gap is useful;
a hidden one is not.

**4. Compose the architecture.**
Build from `assets/terraform/` modules in the domain skills. Write new resources
only where no module fits, and say so explicitly per resource. Module provenance
appears in the deliverable: composed modules and hand-written resources are
listed separately, because they carry different assurance.

**5. Validate and repair.**
Run `scripts/validate.sh`. It emits JSON keyed by control ID.
Fix every failure and re-run until clean. The stop condition is objective: the
validator exits 0. Do not stop because the design looks right.
If a control cannot be satisfied, it becomes `waived` with a recorded exception
or `failed` with a reason — never silently dropped.
If repair iterations exceed 5, stop and report. A rising repair count signals
contradictions in the catalog, not a stubborn design.

**6. Emit the deliverable.**
Follow `references/output-contract.md` exactly. Machine-check completeness:
every `required` control for the declared tier is `satisfied`, `waived`, or
`failed`. No silent omissions.

## Grounding rules

Every applied control cites its `id`, its `authority`, and its `kb_source`.
The two grounding fields answer different questions and both belong in the
output — see `references/control-record-schema.md`:

- `authority` — the upstream standard. Makes the control defensible externally.
- `kb_source` — the curated house position. Makes it *ours* rather than generic.

A control with no `kb_source` is reported as **uncurated** in the deliverable's
grounding summary. This is not an error, but the reader is entitled to know
which parts of their architecture reflect institutional judgment and which are
restated public documentation.

## Non-negotiables

- **Never claim a control is satisfied without either a module reference or a
  passing check.** `satisfied` and `recommended` are different output states and
  must never render identically.
- **A skipped check is not a passing check.** If a validator stage could not run
  (tool absent, credentials missing), affected controls are `skipped`, never
  `satisfied`. Report the degradation.
- **A control with `check: null` can never reach `satisfied`.** It is advice.
- **Controls deliberately not applied are listed with the reason.**
- **Never renumber a control ID.** IDs appear in customer-facing output.
- **Do not execute generated IaC.** This skill generates and validates; it does
  not apply. `terraform plan` runs with `-backend=false` and no credentials.
  Applying is a separate, human-gated decision.

## Scope

Generation and validation only. If asked to apply, deploy, or run the generated
Terraform against a live account, decline and explain that applying is outside
this skill — then hand over the plan and the validation report so a human can
make that call.
