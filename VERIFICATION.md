# Verification Ledger

What in this repository has actually been checked, and what has not.

Generated 2026-08-15 by measurement, not recollection. Re-measure before
relying on it; the commands are given so you can.

**This file exists because the catalogs are meant to be defensible in review.
A defensible artifact has to be honest about its own gaps first.**

---

## Correction to earlier claims

| Claim made during development | Actual |
|---|---|
| "0 of 149 controls have `kb_source`" | **96 controls**, not 149. Arithmetic error. The `kb_source` figure of 0 was correct. |
| "19 executable policies" | **17 rule-bearing policy files** (+2 shared helper files with no rules), containing **29 individual deny rules**. |
| Stage 5 "PASS" in validator output | Stage 5 was **never implemented**. It previously reported PASS whenever `--catalog` pointed at any file. Fixed 2026-08-15 to report SKIP unconditionally. |

```sh
# recount controls
R=plugins/aws-architecture/skills
grep -hc '^### Z' $R/aws-zero-trust/references/{identity,network,workload-identity,data-protection,verification}.md \
                  $R/aws-zero-downtime/references/{topology,deployment,data-continuity,degradation}.md
```

---

## Packaging (added 2026-08-15)

Restructured into a Claude Code plugin under `plugins/aws-architecture/`.
Verified after the move:

| Check | Result |
|---|---|
| All three test suites | ✅ pass |
| `terraform fmt -check -recursive` | ✅ clean |
| Both JSON manifests parse | ✅ |
| Retrieval: index build, exact-token lookup, exit 2 with no corpus | ✅ |
| Terraform modules `validate` | ✅ |

**Not verified:** the plugin has never actually been installed via
`/plugin marketplace add`. Manifest structure was checked against the published
plugin and marketplace reference documentation, and both files parse as JSON,
but the install path itself is untested. The CI workflow has never run — it is
written against GitHub Actions and has not executed anywhere.

## Controls: 96 total

| Catalog | Controls | With a check | Enforced share |
|---|---|---|---|
| Zero Trust (ZT) | 53 | 12 | 23% |
| Zero Downtime (ZD) | 43 | 10 | 23% |
| **Total** | **96** | **22** | **23%** |

`kb_source` coverage: **0 of 96.** No curated house knowledge base exists. Every
control derives from public AWS documentation.

---

## How well-grounded is each control, really?

This is the section most likely to be skipped and most worth reading. Not all
`authority` anchors are equal.

| Grounding depth | Controls | What it means |
|---|---|---|
| **Page fetched and read in full** | ~35 | The anchor points at text I retrieved and extracted from. Strongest. |
| **Identifier verified, page not read** | ~48 | ⚠️ See below. |
| **Source confirmed by search only** | ~8 | The URL appears in search results. Existence confirmed; content never retrieved. |
| **Source never verified** | ~2 | Recorded from prior knowledge. |

*(Categories sum to ~93 of 96; a few controls carry compound or non-standard
anchor formatting. Treat these as close approximations, not exact counts.)*

### ⚠️ The "identifier verified, page not read" category

**Half the catalog is in this state.** Concretely, for anchors of the form
`SRC-AWS-WAF-SEC#SEC05-BP01` or `SRC-AWS-WAF-REL#REL11-BP05`:

- I fetched the **section index pages** that enumerate best-practice IDs and
  titles. Those IDs and titles are verified and correct.
- I did **not** fetch the individual best-practice pages.
- The requirement text under each control is therefore **my synthesis from the
  best-practice title plus general knowledge — not extraction from the AWS
  page the anchor cites.**

This matters in a specific way: a reviewer following `SRC-AWS-WAF-REL#REL05-BP03`
will find a real AWS page about limiting retry calls. It will probably support
the control. But I have not confirmed that it says what the control says, and it
may include conditions, exceptions, or specifics the control omits.

**Affected: ~22 controls anchored on `SEC*-BP*`, ~26 on `REL*-BP*`.**

Closing this is straightforward but not free: roughly 48 page fetches, one per
best-practice page, re-extracting each control against the real text.

### Which sources were genuinely read

Full text retrieved and extracted from:

| Source | Controls anchored | Notes |
|---|---|---|
| IAM security best practices | 14 | Full page, all anchors are real sections |
| VPC Lattice user guide | 5 | Four-layer defense model extracted verbatim |
| WAF Security Pillar *section* pages | 5 | `detection`, `protecting-data-at-rest`, `data-classification` |
| Multi-VPC whitepaper | 3 | IPAM and centralized egress |
| ALB target groups | 3 | Attribute defaults (300s, 0s) confirmed on-page |
| WAF Reliability `implement-change` | 2 | One-AZ-at-a-time rule extracted |
| Static stability (Builders' Library) | 1 | 66%-of-load-tested figure confirmed |
| Multi-Region Fundamentals | 1 | Data-reconciliation requirement extracted |
| Verified Access | 1 | Thin — overview only, no config detail |

---

## Sources: 38 registered

| State | Count |
|---|---|
| Fetched and read | 10 |
| Confirmed via search only | ~11 |
| Never verified | 31 rows still marked `unverified` |

Verification caught two real defects, which is the argument for finishing it:

1. **SRC-AWS-BLUEGREEN-WP** is AWS-labelled *historical* (last revised
   2021-09-29). It was demoted to rationale-only; no control anchors on it.
2. **SRC-AWS-MULTIREGION**'s registered URL was the **archived** whitepaper. The
   maintained version had moved to `prescriptive-guidance/`. It was anchoring a
   `required` control at the time.

### Known inaccuracy in the register

`SRC-AWS-MULTIREGION` resolves to `.../aws-multi-region-fundamentals/introduction.html`.
That page returned only a header on fetch; the page I actually read and
extracted from was `fundamental-2.html`. The control anchors on `#fundamental-2`,
so the citation is sound, but **the registered top-level URL has not itself been
successfully retrieved.**

---

## Policies: 17 files, 29 rules

**All 17 rule-bearing policy files fire** against the test fixtures — verified,
and the suites assert it.

**Individual rules are only partly exercised.** A file firing means at least one
of its rules fired, not all of them. Measured:

| Rule | Covered |
|---|---|
| `zt-net-014` standalone `aws_vpc_security_group_ingress_rule` | ❌ no fixture resource |
| `zt-wld-001` ECS task-definition credentials | ❌ |
| `zt-dat-006` legacy TLS-1-0 `ssl_policy` | ❌ |
| `zd-dat-004` unencrypted `aws_db_snapshot` | ❌ |
| `zt-dat-002` DynamoDB and non-RDS stores | ✅ |
| `zd-top-011` all three sub-rules | ✅ explicitly asserted |
| `zt-idn-006` single-statement (non-array) policy document | ❌ untested branch |

**Roughly 6 of 29 rules have never executed against real plan JSON.** They
compile, and two rules in this repository already shipped compiling-but-never-
firing (a plan-time `after_unknown` bug and Rego treating `null` as truthy), so
compilation is not evidence.

```sh
# reproduce
for s in plugins/aws-architecture/skills/*/tests/run.sh; do bash "$s"; done
```

---

## Validator: what has actually run

| Stage | Status |
|---|---|
| 0 Preflight | ✅ exercised |
| 1 Terraform validate + plan | ✅ exercised, catches real errors |
| 2 Conftest / OPA | ✅ exercised end-to-end, ID extraction verified |
| 2 Checkov | ❌ **never run** — not installed |
| 2 Trivy | ❌ **never run** — not installed |
| 3 IAM Access Analyzer | ❌ **never run** — no AWS CLI, no credentials. The embedded Python has never executed. |
| 4 Zero-downtime invariants | ✅ exercised, red/green asserted |
| 5 Output contract | ❌ **not implemented at all** |

Stage 5 is the significant one: the output contract specifies that every
mandatory control must resolve to a state with no silent omissions, and
**nothing enforces that.** The stage now reports SKIP so it cannot produce a
false clean, but the guarantee described in `output-contract.md` does not exist
in code.

Because Stages 2 (partial), 3, and 5 cannot run here, **the validator has never
returned exit 0 on any input.** Both "compliant" fixtures still exit 1 on
degradation. The clean path is therefore itself untested.

---

## Terraform modules

Two modules, both pass `terraform validate` against the real AWS provider
schema — so resource types and argument names are correct.

Neither has been **instantiated**. No plan has ever been generated with these
modules called and variables supplied, which means:

- `count` / `for_each` / `dynamic` branches are unexercised.
- `validation` blocks on variables have never been triggered.
- The N-1 capacity arithmetic in `ecs-canary` has never produced a number.

---

## Retrieval

`kb_search.py` was tested against a **2-document** corpus. Exact-token matching
(`ZT-NET-014`, `0.0.0.0/0`) and domain filtering both verified.

Not tested: behaviour at realistic corpus size, BM25 parameter suitability
(`K1`/`B` are stock defaults, untuned against any corpus), phrase-boost false
positives, index rebuild on corpus change. Dense retrieval is documented as an
extension point and **is not implemented**.

---

## Summary: what you can and cannot say about this repository

**Supportable:**
- 96 controls, each citing a traceable upstream source ID.
- 22 controls enforced by an executable check.
- A validator whose Stage 1, 2, and 4 demonstrably catch real defects, proven
  red/green against hand-written fixtures.
- Three passing test suites.

**Not supportable without further work:**
- That every control's requirement text matches the AWS page it cites
  (~48 controls unconfirmed).
- That the catalog encodes anything proprietary (`kb_source` is 0 of 96).
- That the validator enforces output-contract completeness (Stage 5 absent).
- That IAM analysis works (Stage 3 never executed).
- That every policy rule works (~6 of 29 never executed).
