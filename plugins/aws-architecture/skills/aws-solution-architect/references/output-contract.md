# Output Contract

The exact deliverable format. Workflow step 6.

The contract exists so the output is checkable by machine, not only readable by
humans. `validate.sh` Stage 5 asserts against it: every mandatory control for
the declared tier must resolve to a state, and no control may be silently
absent.

---

## Required sections, in order

1. Header
2. Intake summary
3. Architecture
4. Terraform
5. Control coverage matrix
6. Controls not applied
7. Validation report
8. Grounding summary

Sections are not optional. An empty section is rendered with an explicit "none",
never omitted — absence must never be ambiguous between "nothing to report" and
"not checked."

---

## 1. Header

```
Catalog version:      3.2
Generated:            2026-08-15
Criticality tier:     0
Validator:            PASS (4 iterations)
Degraded preconditions: none
```

`Degraded preconditions` lists anything from the SKILL.md precondition table
that failed — missing retrieval corpus, unpromoted catalog, absent validator
tooling. If the output was produced against unreviewed candidate records, it
says so here, in the first thing the reader sees.

## 2. Intake summary

The normalized brief, plus **assumptions rendered prominently**. Assumptions are
not an appendix; they are the premises the whole deliverable rests on. A reader
who disagrees with an assumption can stop reading, which saves them time.

## 3. Architecture

Prose plus a diagram if it helps. Name the trust boundaries and the failure
domains explicitly — those are what the control matrix refers to, and a matrix
whose subjects are undefined cannot be audited.

## 4. Terraform

Split by provenance. These carry different assurance and must not be blended:

```
### Composed from vetted modules
- module "network_private_tier"  ← aws-zero-trust/assets/terraform/modules/network/private-tier/
- module "alb_canary"            ← aws-zero-downtime/assets/terraform/modules/deployment/alb-canary/

### Hand-written (no module fit)
- aws_vpc_endpoint.bedrock — no module exists for this endpoint type
```

Every hand-written resource states why no module fit. A growing hand-written
list is the signal that the module library needs extending — it is a useful
metric, and blending the two destroys it.

## 5. Control coverage matrix

The core artifact. One row per applicable control.

| Control | Title | Tier | State | Evidence | Authority | KB source |
|---|---|---|---|---|---|---|
| ZT-NET-014 | Private-tier subnets deny unrestricted ingress | required | `satisfied` | `zt-net-014.rego` pass | SRC-AWS-WAF-SEC#SEC05-BP02 | kb://networking/segmentation.md#segment-boundaries |
| ZT-NET-009 | Per-request application access | required | `recommended` | no check defined | SRC-AWS-VERIFIED-ACCESS#feature-overview | — |
| ZD-TOP-003 | Static stability at N-1 AZ | required | `waived` | exception: single-AZ dev env | SRC-AWS-FIB#az-boundaries | kb://resilience/az-strategy.md |

### The four states

| State | Condition | Never |
|---|---|---|
| `satisfied` | `check` exists **and** passes, **or** a vetted module implements it | Assigned on intent, plan-time reasoning, or a skipped check |
| `recommended` | Applied in guidance only — no check, or no enforceable artifact | Rendered identically to `satisfied` |
| `waived` | Applicable but excepted; requires a matching `exceptions` entry **and** a satisfied compensating control | Used to dispose of an inconvenient control |
| `failed` | Applicable, checked, did not pass | Omitted from the matrix |

A fifth state, `skipped`, appears only when a validator stage could not run.
It is a degradation, not an outcome: it means the control's state is unknown.
`skipped` on a mandatory control fails the deliverable exactly as `failed` does,
because an unverified control and a broken one are equally undefensible.

### Matrix rules

- Every control cites `authority` **and** `kb_source`. A missing `kb_source`
  renders as `—` and is counted in §8, not hidden.
- `satisfied` rows name the specific evidence: the passing check file, or the
  module. "Implemented in the design" is not evidence.
- Sort by state — `failed`, then `skipped`, then `waived`, then `recommended`,
  then `satisfied`. The reader's attention belongs at the top.

## 6. Controls not applied

Every control considered and excluded, with the reason. Three legitimate
reasons; anything else is a gap, not an exclusion:

| Control | Reason | Detail |
|---|---|---|
| ZT-NET-005 | `applies_when` not met | No VPC Lattice in this design |
| ZD-DEP-011 | Below criticality threshold | Control is tier-0 only; workload is tier-1 |
| ZT-DAT-008 | Out of scope per brief | User excluded key management |

"We considered and excluded it" and "we never looked" must be distinguishable.
This section is what makes that possible, and it is the section a reviewer will
read most carefully.

## 7. Validation report

The validator's JSON, summarized:

```
Stage 1  Terraform syntax and plan      PASS
Stage 2  Policy-as-code                 PASS   (14 rules, 0 violations)
Stage 3  IAM analysis                   SKIP   ⚠ no credentials — 3 controls unverified
Stage 4  Zero-downtime invariants       PASS   (6 assertions)
Stage 5  Output contract                PASS
```

Skips are surfaced with their consequence, never as quiet passes. Attach the
raw JSON so the result is reproducible.

## 8. Grounding summary

```
Controls applied:            22
Backed by catalog control:   22
Of which curated (kb_source): 0     ⚠
Retrieved snippets cited:     3
UNGROUNDED claims:            2
```

List each `UNGROUNDED` claim inline where it appears in the architecture, and
again here. A labelled gap is a manageable risk; an unlabelled one is a
liability.

The **curated** count is the honest measure of whether this system contributes
anything beyond a capable model's recall. A deliverable where it reads 0 is
built entirely from public documentation. That is not necessarily wrong — but
the reader is entitled to know it, and the number should trend up over time.

---

## Failure output

When the validator cannot be brought clean within 5 repair iterations, do not
emit a deliverable claiming success. Emit the same structure with:

- Header `Validator: FAIL (5 iterations, not converged)`
- The matrix, with failures at top
- A short diagnosis of what did not converge

A rising repair count usually means two controls in the catalog contradict each
other, and no architecture satisfies both. That is a Phase 1 catalog defect
surfacing as a Phase 3 symptom — report it as such, naming both control IDs, so
it gets fixed at the source rather than worked around per-architecture.
