# AWS Zero Trust / Zero Downtime Architecture Skills

A Claude Code plugin that turns a solution concept into a validated AWS
architecture: Terraform plus a traceable control-coverage matrix, backed by a
96-control catalog and a validation gate that **fails closed on anything it
could not verify**.

> **Status: v0.1.0, pre-review.** The catalog has not been through human
> sign-off, and roughly half its controls cite an AWS page that was never
> opened during authoring. Read [VERIFICATION.md](VERIFICATION.md) before
> relying on this for anything that matters — it is a measured account of what
> has and has not been checked, including corrections to earlier claims.

Not affiliated with, endorsed by, or sponsored by Amazon Web Services.
See [NOTICE](NOTICE).

---

## What it does

Three skills that trigger independently but ship as one plugin:

| Skill | Role |
|---|---|
| `aws-solution-architect` | Orchestrator: intake → control selection → generation → validate → repair |
| `aws-zero-trust` | 53 controls — identity, network, workload identity, data protection, verification |
| `aws-zero-downtime` | 43 controls — topology, deployment, data continuity, degradation |

The distinguishing property is not the control list. It is that **"satisfied"
requires evidence**:

- A control with no executable check can never be reported `satisfied` — only
  `recommended`. Advice and enforcement are different output states.
- A check that could not run (missing tool, absent credentials) is reported
  `skipped`, never `satisfied`, and blocks the gate exactly as a failure does.
- Every control cites the upstream source that justifies it.

## Install

```
/plugin marketplace add <this-repo>
/plugin install aws-architecture
```

Then run the toolchain preflight once:

```sh
plugins/aws-architecture/scripts/preflight.sh
```

### Prerequisites

| Tool | Required | Used by |
|---|---|---|
| `python3` | yes | report assembly, retrieval |
| `terraform` | yes | Stage 1 — validate, plan, plan.json |
| `conftest` | yes | Stage 2 — the 17 OPA policies |
| `checkov`, `trivy` | no | Stage 2 — baseline coverage |
| `aws` CLI | no | Stage 3 — IAM Access Analyzer |

Missing optional tools do not silently degrade the result: affected controls
report `skipped` and the validator will not return 0. That is deliberate, and
it means **a fresh install without the optional tools never exits clean.**

## The validator

```sh
skills/aws-solution-architect/scripts/validate.sh <terraform-dir> --tier 0
```

| Stage | What it does | State |
|---|---|---|
| 1 | `terraform validate` + plan + plan.json | working |
| 2 | Conftest/OPA against 17 policies; Checkov; Trivy | working (OPA); Checkov/Trivy untested |
| 3 | IAM Access Analyzer custom policy checks | **never executed** |
| 4 | Tier-aware zero-downtime invariants | working |
| 5 | Output-contract completeness | **not implemented** |

Emits JSON keyed by control ID so a repair loop can act on it.

## Retrieval and the curated corpus

`kb_search.py` provides BM25 retrieval with exact-token preservation, so control
IDs (`ZT-NET-014`) and CIDR notation (`0.0.0.0/0`) survive tokenization.

**The corpus is not shipped, by design.** It resolves from `KB_ROOT`, then
`CLAUDE_PROJECT_DIR/knowledge-base/curated`, then the working directory. A
corpus bundled inside the plugin would be destroyed on every update, and it is
the one part of this system that is genuinely yours.

```sh
export KB_ROOT=/path/to/your/knowledge-base/curated
python3 .../kb_search.py --build-index
python3 .../kb_search.py "aurora failover rpo" --domain data --top-k 5
```

With no corpus the script exits 2, and the skill marks affected claims
`UNGROUNDED` rather than answering from model recall.

## The honest limitation

Every control carries an `authority` (the upstream source). **No control carries
a `kb_source`** — the field for your organisation's own position.

That means this catalog currently encodes public AWS documentation. It is
correct, it is enforced where enforceable, and a capable model could recall much
of it. What it is not, yet, is differentiated. The `kb_source` field, the
`kb://` namespace, and the retrieval layer all exist to close that gap; nothing
has been put into them.

If you fork this, that is the interesting work.

## Repository layout

```
.claude-plugin/marketplace.json    marketplace catalog
CATALOG_VERSION                    single source of truth for catalog version
VERIFICATION.md                    measured account of what is and isn't verified
plugins/aws-architecture/
  ├── .claude-plugin/plugin.json
  ├── scripts/preflight.sh
  └── skills/
      ├── aws-solution-architect/  orchestrator, validator, retrieval
      ├── aws-zero-trust/          53 controls, 12 policies, 1 module
      └── aws-zero-downtime/       43 controls, 5 policies, 1 module
knowledge-base/                    provenance: source manifest and extraction record
docs/                              design notes
```

`knowledge-base/curated/` is intentionally absent — see above.

## Tests

```sh
for s in plugins/aws-architecture/skills/*/tests/run.sh; do bash "$s"; done
```

All three suites pass. They assert that every policy **fires**, not merely that
it compiles — two policies in this repository shipped in a compiling-but-never-
firing state before the suites caught them.

Roughly 6 of 29 individual deny rules still have no fixture coverage; they are
listed in [VERIFICATION.md](VERIFICATION.md).

## Contributing

Control records are not ordinary code — see [CONTRIBUTING.md](CONTRIBUTING.md).
The short version: control IDs are immutable, `satisfied` requires evidence, and
a policy without a test that proves it fires will not be merged.

## Licence

[Apache-2.0](LICENSE). Control text is original prose citing public AWS
documentation; see [NOTICE](NOTICE) for attribution and limits.
