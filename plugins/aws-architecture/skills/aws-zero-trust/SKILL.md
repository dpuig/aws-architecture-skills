---
name: aws-zero-trust
description: >
  Applies a curated Zero Trust control catalog to AWS architectures — identity
  federation, network segmentation, workload identity, data protection, and
  continuous verification — and emits Terraform plus a control-coverage matrix.
  Use whenever the user describes an AWS system to design or review, mentions
  Zero Trust, least privilege, segmentation, mTLS, IAM boundaries, federation,
  encryption, or asks whether an architecture is secure, how to lock something
  down, or who can reach what — even if they never say "Zero Trust".
---

# AWS Zero Trust

A control catalog, not a set of opinions. Every control carries an ID, an
upstream authority, and — where one exists — an executable check.

Zero Trust here means one thing operationally: **access decisions are made per
request against identity and context, never inherited from network position.**
Every control in this catalog serves that premise or supports verifying it.

## Using this skill

**Standalone** — answering a security question, reviewing a design, or
explaining a control. Read `references/control-catalog.md`, then the one or two
domain files the question touches. Do not load all five.

**Under the orchestrator** — `aws-solution-architect` drives intake, tier
selection, generation, and the validate/repair loop. This skill supplies the
catalog, the modules, and the policies. Follow the orchestrator's workflow;
this file governs only how controls are selected and applied.

## Selecting controls

1. Read `references/control-catalog.md` — the index. It lists every control ID,
   title, tier, and whether a check exists.
2. Load only the domain files the brief touches:

| Signal in the brief | Domain file | Prefix |
|---|---|---|
| Users, roles, federation, SSO, permissions, cross-account | `references/identity.md` | ZT-IDN |
| VPC, subnets, security groups, ingress, service mesh, egress | `references/network.md` | ZT-NET |
| Containers, Lambda, CI/CD, on-prem callers, machine credentials | `references/workload-identity.md` | ZT-WLD |
| Storage, databases, PII, encryption, keys, certificates, TLS | `references/data-protection.md` | ZT-DAT |
| Logging, detection, audit, alerting, incident response | `references/verification.md` | ZT-TEL |

3. For each control in the loaded domains, evaluate `applies_when` against the
   brief. Record the determination either way — "considered and excluded" and
   "never looked" are different claims, and only one of them is defensible.
4. Apply the obligation matrix in
   `aws-solution-architect/references/tier-model.md`. A control's `tier` is how
   strongly it is held; the workload's criticality decides whether that
   obligation binds.

**Do not apply every control.** Over-application is the failure mode that makes
output unusable, and it is more common than under-application. A tier-2 internal
tool does not need the tier-0 control set, and delivering it that way teaches
the user to ignore the matrix entirely.

## Applying controls

- Compose from `assets/terraform/` modules. Write new resources only where no
  module fits, and say so per resource.
- Cite `id` and `authority` for every control applied.
- A control's `check` is what makes it enforced. A control with no check is
  advice — render it `recommended`, never `satisfied`.
- Where a control names an upstream check (`CKV_AWS_130`), that check satisfies
  it only if the control record says so. A clean Checkov run does not satisfy
  controls Checkov never evaluated.

## Exceptions

Real architectures violate ideal controls for legitimate reasons. Each control's
`exceptions` list encodes the valid paths. To waive a control:

1. The situation must match a recorded `exceptions.condition`.
2. The compensating control named in `requires` must itself be satisfied.

A waiver whose compensating control is unsatisfied is not a waiver — it is a
failure with better wording, and the validator treats it as one. If no recorded
exception fits, the control fails; do not invent an exception to dispose of it.

## Catalog status

**Pre-review.** Controls were extracted from verified upstream
sources but have not been through Phase 1.3 human sign-off. Every control
carries `authority`; **none carries `kb_source`**, because no curated house
knowledge base exists yet.

State this in any deliverable. It means the catalog currently encodes public
AWS documentation rather than institutional judgment — the controls are
correct, but a capable model could recall most of them. That gap is the thing
the curated KB is meant to close.

## Non-negotiables

- Never claim a control is satisfied without a passing check or a module
  reference.
- Never renumber a control ID. IDs appear in customer-facing output.
- Never mark a control satisfied because the design "follows the principle".
  Principles are not evidence.
- Never widen a control's `applies_when` to make it fit. If it does not apply,
  it does not apply.
