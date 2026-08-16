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
| Validator toolchain | `../../scripts/preflight.sh --json` | **Tell the user before designing anything** — see below. Continue only if nothing required is missing. |
| A promoted control catalog | `aws-zero-trust/references/control-catalog.md` exists | Report which domains are unavailable. Offer to run against candidate records in `knowledge-base/extracted/`, clearly labelled as unreviewed. |
| Catalog version | Read `catalog_version` from the catalog header | Record it in the deliverable. Never emit output without one. |
| Retrieval corpus | `scripts/kb_search.py --status` exits 0 | Continue, but every claim not covered by a catalog control is `UNGROUNDED`. |

State the catalog version and any degraded preconditions in the deliverable
header. The reader must be able to tell what the output was actually built from.

### Reporting the toolchain to the user

Run the preflight **first**, and report what it finds *in your reply to the
user*, not only in the deliverable header. The timing is the whole point: a
missing tool costs one `brew install` at intake and a wasted design cycle at
validation, and the person who can fix it is reading your reply.

`preflight.sh --json` returns `status`, `required_missing`, `optional_missing`,
`kb_root`, and a `consequence` string. Act on `status`:

| `status` | What it means | What to do |
|---|---|---|
| `ok` | Full toolchain | Say nothing. Do not congratulate the user on their PATH. |
| `degraded` | Optional tools absent | Design normally, but tell the user **before** you start: name each missing tool, what it would have verified, and its install command. Say plainly that the validator cannot return 0 until they are installed. |
| `fail` | A required tool is absent | **Stop.** The validator cannot run, so nothing you produce can be reported as validated. Give the install commands and offer to continue on the explicit understanding that the output is unvalidated advice. |

Report the tools, the consequence, and the fix together. "checkov not found" on
its own is a fact the user cannot act on; "checkov is missing, so the baseline
coverage controls will report `skipped` and block the gate — `pip install
checkov`" is one they can. Never present a missing optional tool as a mere
warning that can be ignored: a `skipped` control blocks exactly as a failure
does, and that surprises people who were told it was optional.

`kb_root: unset` is expected on a fresh install and is not a toolchain problem —
mention it once, with its consequence (claims outside the catalog are marked
`UNGROUNDED`), and do not repeat it every run.

## Workflow

**1. Normalize the concept into the intake brief.**
Read `references/intake-schema.md`. Fill every required field.
If criticality tier is unstated, **ask** — do not assume tier-0. Over-assumption
produces carpet-bombed architectures that are unusable, which is the more common
failure of this system than under-protection.
Record unresolved fields as explicit assumptions; never silently default them.

**If no Region is specified, do not stop and do not pick one silently.** Ask for
it in the batched question set; if it is still unanswered, proceed with the
labelled placeholder from `intake-schema.md`, record the assumption, and tell
the user in your reply — not only in the deliverable. The gate stays shut on
`INTAKE-REGION` until a Region is chosen or the user defers deliberately.

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

**4b. Render the architecture diagram.**
`validate.sh` writes `architecture.mmd` and `architecture.txt` at Stage 1b by
projecting `plan.json`. Both go into deliverable §3 — see
`references/diagrams.md`.
**Never hand-draw the primary diagram.** A diagram generated from the validated
plan cannot drift from the Terraform; one drawn from intent is an unverified
claim sitting in the most trusted position in the document. Anything real but
absent from the Terraform — on-prem, SaaS, an existing TGW — belongs in a
separate diagram labelled as hand-drawn.

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
- **Never present a hand-drawn diagram as the generated one**, and never render
  a placeholder Region as a bare Region name. Both put an unverified claim where
  a reader has no way to detect it.
- **Do not execute generated IaC.** This skill generates and validates; it does
  not apply. `terraform plan` runs with `-backend=false` and no credentials.
  Applying is a separate, human-gated decision.

## Scope

Generation and validation only. If asked to apply, deploy, or run the generated
Terraform against a live account, decline and explain that applying is outside
this skill — then hand over the plan and the validation report so a human can
make that call.
