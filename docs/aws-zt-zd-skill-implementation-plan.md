# Implementation Plan: AWS Zero Trust / Zero Downtime Architecture Skill

**Goal:** a skill package that takes a user's solution concept and produces a validated AWS architecture — IaC plus a traceable control mapping — grounded in your curated knowledge base rather than model recall.

---

## 0. Target topology

Three skills, not one. Splitting them keeps each SKILL.md under the ~500-line working limit, lets the two domains trigger independently, and prevents Zero Trust guidance from being loaded when someone only asks a deployment-strategy question.

```
aws-solution-architect/          # orchestrator: intake → generate → validate → repair
├── SKILL.md
├── references/
│   ├── intake-schema.md         # the structured brief the concept gets normalized into
│   ├── output-contract.md       # exact deliverable format
│   └── tier-model.md            # tier-0/1/2 criticality → which controls are mandatory
└── scripts/
    ├── validate.sh              # runs the full deterministic gate
    └── kb_search.py             # retrieval over the full curated KB

aws-zero-trust/
├── SKILL.md
├── references/
│   ├── control-catalog.md       # index: control ID → title → domain (table of contents)
│   ├── identity.md              # ZT-IDN-*
│   ├── network.md               # ZT-NET-*
│   ├── workload-identity.md     # ZT-WLD-*
│   ├── data-protection.md       # ZT-DAT-*
│   └── verification.md          # ZT-TEL-*
├── assets/terraform/            # vetted modules the generator composes, not invents
└── policies/                    # machine-checkable rules, one per control

aws-zero-downtime/
├── SKILL.md
├── references/
│   ├── control-catalog.md
│   ├── topology.md              # ZD-TOP-*  multi-AZ, cells, static stability
│   ├── deployment.md            # ZD-DEP-*  blue/green, canary, rolling
│   ├── data-continuity.md       # ZD-DAT-*  expand/contract, replication, failover
│   └── degradation.md           # ZD-DEG-*  draining, retries, circuit breakers
├── assets/terraform/
└── policies/
```

**Why `policies/` is a sibling of `references/`:** reference files are prose Claude reads; policy files are rules a validator executes. Keeping them separate makes it obvious which controls are actually enforced versus merely described — that gap is the single most useful health metric for this system.

---

## Phase 1 — Turn the knowledge base into a control catalog

This is the highest-leverage phase and the one most likely to be skipped. **Do not copy the KB into the skill.** Curated prose is written for humans to read linearly; a skill needs content that is addressable, deduplicated, and checkable.

### 1.1 Define the control record schema

Every atomic piece of guidance in your KB becomes one record:

```yaml
id: ZT-NET-014
title: Private-tier subnets deny unrestricted ingress
domain: network
tier: required          # required | recommended | contextual
applies_when: "Any VPC-attached compute not explicitly designated an edge tier"
rationale: >
  Perimeter-only trust fails the moment one edge host is compromised. Ingress
  must be authorized per-source-identity, not per-network-location.
aws_implementation: |
  - Security group ingress references peer SG IDs, never CIDR blocks, for
    east-west traffic.
  - Public exposure terminates at ALB/CloudFront; origin protected by
    VPC origin or SG referencing the managed prefix list.
iac_ref: assets/terraform/modules/network/private-tier/
check: policies/opa/zt-net-014.rego
kb_source: kb://networking/segmentation.md#segment-boundaries
exceptions:
  - condition: "Documented public-facing NLB for non-HTTP protocol"
    requires: "Compensating control ZT-NET-021 (Network Firewall inspection)"
supersedes: []
```

The fields that matter most:

- **`kb_source`** — the traceability link. Every generated architecture can cite which KB section justified a decision. This is what makes the output defensible in a security review.
- **`check`** — the determinism hook. Prose without a check is advice; prose with a check is a control.
- **`tier` + `applies_when`** — prevents the model from carpet-bombing every architecture with all 200 controls. Most bad output in this category comes from over-application, not under-application.
- **`exceptions`** — real architectures violate ideal controls. Encoding the legitimate exception paths stops the model from either silently ignoring a control or refusing a valid design.

### 1.2 Run the ingestion

Do this as a one-time, reviewed pipeline — not an automated sync. The distillation is where the value is added, and it needs human sign-off.

1. **Inventory.** Script a pass over the KB producing a manifest: path, title, word count, last-modified, detected domain. You need to know the shape before you decide the split.
2. **Extract candidate controls.** Batch the KB through a model with the schema above as the output contract. Expect roughly 1 control per 200–400 words of well-written source material. Flag low-confidence extractions for review rather than dropping them.
3. **Deduplicate and reconcile.** Curated KBs accumulate contradictions across years. Cluster near-identical controls, then have a human resolve each conflict explicitly and record the losing variant under `supersedes`. Do not let the model silently pick a winner.
4. **Assign stable IDs.** Never renumber. IDs appear in generated output and in customer-facing reports; churn destroys traceability.
5. **Classify for retrieval** using the routing rule below.
6. **Write reference files**, grouped by domain, each opening with a control-ID table of contents.

### 1.3 Bundle-versus-retrieve routing rule

| Content characteristic | Destination | Loading cost |
|---|---|---|
| Small, stable, needed on every run (tier model, output contract) | SKILL.md body | Loaded on trigger |
| Domain guidance, conditionally needed | `references/*.md` | Loaded on demand |
| Large, long-tail, or volatile (per-service notes, past design reviews, incident writeups) | External index, reached via `scripts/kb_search.py` | Only the returned snippets |
| Objectively checkable | `policies/*` + `scripts/validate.sh` | Zero — executes without loading |
| Reusable IaC | `assets/terraform/` | Zero until read |

Two things push content toward retrieval rather than bundling: volume, and volatility. AWS service availability, region/AZ coverage, quota defaults, and service names drift constantly — bundling them guarantees stale output within a quarter.

### 1.4 The retrieval script

`scripts/kb_search.py` should be a tiny CLI with a stable contract:

```
kb_search.py "aurora global database failover rpo" --domain data --top-k 5
→ JSON: [{doc_id, title, snippet, kb_uri, score, last_reviewed}]
```

Two viable backends:

- **Local index** (sqlite-vec, LanceDB, or FAISS) built at package time. Fast, no runtime dependency, works offline, easy to version alongside the skill. Preferred unless the KB changes weekly.
- **Bedrock Knowledge Bases** with OpenSearch Serverless or Aurora pgvector. Choose this if the KB is already in S3/Confluence with existing sync, or if multiple systems need the same retrieval layer. Costs more and adds a runtime dependency, but decouples KB updates from skill releases.

Either way: hybrid search (BM25 + dense) meaningfully outperforms pure vector search on this corpus, because control lookups are full of exact-match tokens — service names, control IDs, CIDR notation, API actions.

---

## Phase 2 — Author the skills

### 2.1 Frontmatter

The description is the only thing loaded at startup, and it is the entire triggering mechanism. Claude tends to under-trigger skills, so write it to fire on the *problem*, not just the jargon:

```yaml
---
name: aws-zero-trust
description: >
  Applies a curated Zero Trust control catalog to AWS architectures — identity
  federation, network segmentation, workload identity, data protection, and
  continuous verification — and emits Terraform plus a control-coverage matrix.
  Use whenever the user describes an AWS system to design or review, mentions
  Zero Trust, least privilege, segmentation, mTLS, IAM boundaries, or asks
  whether an architecture is secure — even if they never say "Zero Trust".
---
```

Note the last clause. Most real requests arrive as "review this architecture" or "how should I lock this down", not as "apply Zero Trust."

### 2.2 SKILL.md body structure

Keep the orchestrator body to workflow and routing; push all substance into references.

```markdown
# AWS Zero Trust Architecture

## Workflow
1. Normalize the concept into the intake schema (references/intake-schema.md).
   If criticality tier is unstated, ask — do not assume tier-0.
2. Determine applicable controls: read references/control-catalog.md, then load
   only the domain files the intake actually touches.
3. For anything not covered by the catalog, run scripts/kb_search.py before
   answering from general knowledge. Mark any claim not backed by the KB or a
   retrieved snippet as UNGROUNDED in the output.
4. Compose Terraform from assets/terraform/ modules. Write new resources only
   when no module fits, and say so explicitly.
5. Run scripts/validate.sh. Fix every failure and re-run until clean.
6. Emit the deliverable per references/output-contract.md.

## Non-negotiables
- Never claim a control is satisfied without either a module reference or a
  passing check. "Satisfied" and "recommended" are different output states.
- Every control applied cites its ID and kb_source.
- Controls deliberately not applied are listed with the reason.
```

That step 5 loop — validate, repair, re-validate — is what separates a plausible-looking diagram from a defensible one. Make the stop condition objective.

### 2.3 Writing guidance

- Imperative voice throughout.
- Explain *why* a control exists; models generalize far better from rationale than from bare directives, and your users will ask.
- Keep file references one level deep. `references/network.md` — not `references/aws/network/ingress.md`.
- No time-sensitive claims in the body. "As of 2025, X is the newest…" ages badly; put anything version-dependent behind retrieval.
- Concrete examples over abstract ones. One worked intake → architecture → control matrix example is worth several pages of description.

---

## Phase 3 — The deterministic validation layer

The skill's credibility rests here. Build `scripts/validate.sh` as a staged gate that fails fast:

**Stage 1 — Syntax and plan generation**
`terraform init -backend=false && terraform validate && terraform plan -out=tf.plan && terraform show -json tf.plan > plan.json`

**Stage 2 — Policy-as-code against plan.json**
- **Conftest/OPA** with a Rego rule per control — your primary engine, since the control catalog maps 1:1 to policy files.
- **Checkov** and **Trivy config** for broad baseline coverage you don't want to hand-write.
- **cfn-guard** if you're on CloudFormation; **cdk-nag** if CDK.

**Stage 3 — IAM-specific analysis** (the highest-value AWS-native gate for Zero Trust)
IAM Access Analyzer custom policy checks catch what generic linters miss:
- `CheckNoPublicAccess` — resource policies granting external access
- `CheckAccessNotGranted` — assert specific sensitive actions are absent
- `CheckNoNewAccess` — diff a generated policy against a reference baseline

**Stage 4 — Zero Downtime invariants** (assertions over plan.json, mostly custom)
- No resource in the critical path confined to a single AZ
- Deployment resources declare a rollback path (CodeDeploy deployment group, ECS circuit breaker, Lambda alias weighting)
- ALB target groups define deregistration delay and health check thresholds
- RDS/Aurora Multi-AZ where tier ≤ 1; database changes follow expand/contract ordering
- Auto Scaling min capacity survives the loss of one AZ

**Stage 5 — Output contract**
Machine-check that the control-coverage matrix is complete: every `required` control for the declared tier is either satisfied, waived with a recorded exception, or explicitly failed. No silent omissions.

Emit structured JSON so the repair loop in step 5 of the workflow can act on it, keyed by control ID.

---

## Phase 4 — Evaluation

Skills of this type fail in two specific ways, and you need to measure both.

**Trigger evaluation.** Write 15–25 realistic prompts — a mix of true positives ("design a multi-tenant SaaS backend on AWS for a healthcare client") and near-miss negatives ("explain what mTLS is", "review this Azure design"). Run each several times; you're measuring trigger rate, not a single outcome. Under-triggering is the more common failure.

**Output evaluation.** Build a golden set of 8–12 concept briefs spanning your tier model, each with a hand-labeled expected control set. Score:

| Metric | What it catches |
|---|---|
| Control recall | Missed required controls — the security-relevant failure |
| Control precision | Over-application, the usability failure that makes output unusable |
| Validator pass rate on first generation | Whether the skill front-loads correctness or leans on the repair loop |
| Repair-loop iterations to clean | Convergence; a rising number signals contradictions in the catalog |
| Grounding rate | Share of claims citing a `kb_source` versus `UNGROUNDED` |
| Hallucinated resources | AWS resources/arguments that don't exist — caught free by `terraform validate` |

Run a no-skill baseline on the same briefs. If the delta is small, the problem is almost always that the catalog encodes generic best practice rather than your curated, differentiated knowledge — which is a Phase 1 problem, not a prompting one.

---

## Phase 5 — Packaging and operations

- **Version the catalog independently of the skill.** `catalog-v3.2` referenced from `SKILL.md`. Generated architectures record which catalog version produced them, so you can answer "why did we approve this six months ago."
- **Treat KB changes as PRs against control records**, not as re-ingestion runs. Re-running extraction wholesale will churn IDs and break traceability.
- **Add a review-date field per control.** Anything AWS-specific older than ~6 months should be flagged for re-verification against live docs.
- **Distribute as a plugin** if you want the skills, validation scripts, and any MCP connectors installable as one unit.
- **Apply the product to itself.** A Zero Trust generator holding long-lived AWS credentials is an uncomfortable artifact. Per-tenant role assumption, short-lived credentials via OIDC, no execution of generated IaC without an explicit human gate, and generated Terraform treated as untrusted input if you ever plan or apply it.

---

## Suggested sequencing

| Weeks | Focus | Exit criterion |
|---|---|---|
| 1–2 | Phase 1 on one domain only (network is the best pilot — most checkable) | ~25 control records, human-reviewed, with `check` populated |
| 2–3 | Phase 3 validator for those controls | `validate.sh` runs green/red against two hand-written reference architectures |
| 3–4 | Phase 2 SKILL.md + orchestrator | End-to-end run on one concept brief produces a validated deliverable |
| 4–5 | Phase 4 evals on the pilot domain | Baseline delta measured; catalog gaps identified |
| 5+ | Expand to remaining domains | Repeat 1→3→4 per domain |

The pilot-domain-first ordering matters. Ingesting the whole KB before you know whether the control schema survives contact with a real validator is the most expensive way to discover the schema was wrong.

---

## Open decisions

1. **KB format and volume** — determines whether the local index or Bedrock Knowledge Bases is right, and how much of Phase 1 can be automated.
2. **Does the system ever apply IaC, or only generate it?** Generation-only removes an entire class of security requirements from your own architecture.
3. **Multi-account model** — if generated architectures assume Control Tower / Organizations landing zones, that assumption belongs in the intake schema, not implied in the catalog.
4. **Who owns catalog changes?** The review gate in Phase 1.3 needs a named owner or it degrades into auto-merge within a month.
