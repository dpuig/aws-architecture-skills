# Control Record Schema

The contract every control in the catalog conforms to. Phase 1.2 extraction
targets this schema; Phase 1.3 review validates against it; `scripts/validate.sh`
consumes `check` and `tier` from it.

One control record is one atomic piece of guidance. If a record needs the word
"and" in its title, it is probably two records.

---

## Full schema

```yaml
# ---- identity -------------------------------------------------------------
id: ZT-NET-014                    # required, immutable, never reused
title: Private-tier subnets deny unrestricted ingress
domain: network                   # required; one of the domain files
catalog_version: 3.2              # required; version this record was last edited in

# ---- applicability --------------------------------------------------------
tier: required                    # required | recommended | contextual
applies_when: "Any VPC-attached compute not explicitly designated an edge tier"
applies_to_criticality: [0, 1]    # tier-model criticality levels; see tier-model.md

# ---- substance ------------------------------------------------------------
rationale: >
  Perimeter-only trust fails the moment one edge host is compromised. Ingress
  must be authorized per-source-identity, not per-network-location.
aws_implementation: |
  - Security group ingress references peer SG IDs, never CIDR blocks, for
    east-west traffic.
  - Public exposure terminates at ALB/CloudFront; origin protected by
    VPC origin or SG referencing the managed prefix list.

# ---- grounding (two distinct namespaces) ----------------------------------
kb_source: kb://networking/segmentation.md#segment-boundaries
authority: SRC-AWS-FIB#az-boundaries

# ---- enforcement ----------------------------------------------------------
check: policies/opa/zt-net-014.rego
iac_ref: assets/terraform/modules/network/private-tier/

# ---- lifecycle ------------------------------------------------------------
last_reviewed: 2026-08-15         # required; drives the staleness gate
review_owner: "@unassigned"       # required; see kb-sources.md open item 4
supersedes: []
exceptions:
  - condition: "Documented public-facing NLB for non-HTTP protocol"
    requires: "Compensating control ZT-NET-021 (Network Firewall inspection)"
```

---

## The two grounding fields

This is the part most likely to be collapsed back into one field by someone who
doesn't know why it was split. It matters, so the reasoning is recorded here.

| Field | Points at | Answers | Namespace |
|---|---|---|---|
| `kb_source` | Your curated KB | "What is *our* position on this?" | `kb://...` |
| `authority` | Upstream standard or vendor doc | "Who says so, externally?" | `SRC-*` from `kb-sources.md` |

A well-formed control has both. The upstream standard establishes that the
control is defensible to an outside reviewer; the curated KB entry establishes
that it reflects your judgment rather than a generic import.

**Why not one field.** With them merged, two very different defects look
identical:

- **Missing `authority`** → the control is your house opinion with no external
  backing. Fine for `contextual`, disqualifying for `required` in a compliance
  conversation.
- **Missing `kb_source`** → the control was imported wholesale from a public
  standard with no curation applied. This is the failure mode the plan's Phase 4
  warns about: if a no-skill baseline scores nearly as well as the skill, it is
  almost always because the catalog is full of records like this. Generic best
  practice, restated.

Splitting the field makes both countable. `authority`-coverage and
`kb_source`-coverage are separate health metrics, and the second one is the
honest measure of whether this system encodes anything the model didn't already
know.

**Neither field is fetched at runtime.** Both are citations, read by humans
during review and printed into the deliverable's control matrix. Generation reads
the record, not the sources behind it.

### Well-formedness rules

Enforce these in Phase 1.3 review and in `validate.sh` Stage 5:

1. `tier: required` → `authority` MUST be present and MUST resolve to a source
   carrying the **N** marker in `kb-sources.md`.
2. `tier: required` → the `authority` source MUST NOT be `unverified` in the
   register.
3. Every record SHOULD have `kb_source`. Records without it are reported as
   *uncurated* in the catalog health report — not an error, but a tracked count
   that should trend toward zero.
4. `check: null` is legal and honest. It means the control is advice, not an
   enforced control, and the deliverable must render it as `recommended`, never
   `satisfied`.
5. `exceptions[].requires` MUST name a real control ID.

---

## Field notes

**`id`** — immutable. Appears in generated output and customer-facing reports;
churn destroys traceability. A superseded control is marked, never renumbered and
never deleted.

**`catalog_version`** — lets a generated architecture record exactly which
catalog produced it. This is what answers "why did we approve this six months
ago" without archaeology.

**`tier` vs `applies_to_criticality`** — two independent axes, frequently
confused. `tier` is how strongly the control is held *when it applies*;
`applies_to_criticality` is *which workloads* it applies to at all. A control can
be `required` but only for tier-0 systems. Keeping them separate is what stops
the model carpet-bombing every architecture with the full catalog — the
over-application failure that makes output unusable.

**`applies_when`** — prose, evaluated by the model at intake. Write it as a test
a reader can apply, not as a description. "Any VPC-attached compute not
explicitly designated an edge tier" is testable; "workloads needing strong
segmentation" is not.

**`rationale`** — the field that most improves generalization, and the one with
the licensing exposure. Write it in your own words. Verbatim copying from
copyrighted sources (AWS, CIS, Google) creeps in here during extraction; NIST
material is public domain and may be quoted freely. See `kb-sources.md`
§Licensing.

**`check`** — the determinism hook. Prose without a check is advice; prose with a
check is a control. Before hand-writing Rego, look for an upstream rule in the
check-source table of `kb-sources.md` — reusing `CKV_AWS_*` or a Security Hub
control ID is cheaper and better maintained.

**`last_reviewed` / `review_owner`** — the staleness gate. Anything AWS-specific
older than ~6 months is flagged for re-verification against live docs. An
unassigned `review_owner` on a `required` control should fail the health report;
without a name, the review gate degrades into auto-merge.

**`supersedes`** — records the losing side of a deduplication conflict. Curated
KBs accumulate contradictions across years; when two near-identical controls are
reconciled, a human decides and the loser is recorded here. Never let extraction
silently pick a winner — the discarded variant is often the one that encoded a
hard-won exception.

**`exceptions`** — real architectures violate ideal controls for legitimate
reasons. Encoding the valid exception paths is what stops the model from either
silently ignoring a control or refusing a sound design. Each exception names its
compensating control, so a waiver is a trade, not a hole.

---

## Output states

The deliverable's control matrix distinguishes four states. Collapsing them is
the fastest way to lose credibility in a security review.

| State | Condition |
|---|---|
| `satisfied` | `check` exists **and** passes, or `iac_ref` module is composed in |
| `recommended` | Applied in guidance only; no check, or no enforceable artifact |
| `waived` | Applicable but excepted; requires a matching `exceptions` entry |
| `failed` | Applicable, checked, and the check did not pass |

"Satisfied" and "recommended" are different states and must never be rendered
identically. A control with `check: null` can never reach `satisfied`.

---

## Worked example

See `ZT-NET-014` above. Read it as the reference implementation of this schema:
every field populated, both grounding namespaces present, an enforceable check, a
real module, and one legitimate exception with a named compensating control.

One worked record is worth more to an extraction pass than several pages of
description — keep this one current as the schema evolves.
