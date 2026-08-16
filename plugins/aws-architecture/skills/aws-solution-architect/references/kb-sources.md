# Knowledge Base Source Register

Seed manifest for Phase 1.2 (Inventory). Every control record's **`authority`**
field must resolve to a source listed here, addressed as `<SOURCE-ID>#<anchor>`.

This register is **not** the knowledge base. It is the list of upstream documents
the knowledge base is distilled from, plus the metadata needed to decide how each
one is loaded, cited, and re-verified.

> **Two namespaces, do not conflate them.** This register covers *upstream*
> sources — public standards and vendor documentation. A control record's
> `kb_source` points somewhere else entirely: at your own curated KB
> (`kb://...`), recording your house position. `authority` points here.
> See `control-record-schema.md` for why both exist.

---

## How to use this file

1. **Before extracting a control**, confirm its source has an ID below. Sources
   not registered here do not produce controls — add the source first.
2. **Cite by source ID, not URL.** `authority: SRC-NIST-207#3.2` survives a
   documentation URL change; a raw link does not. Resolve IDs to URLs here.
3. **Respect the Routing column.** It applies the bundle-versus-retrieve rule
   from the implementation plan §1.3. `bundle` content may be distilled into
   `references/*.md`; `retrieve` content must stay behind `scripts/kb_search.py`.
4. **Re-verify on the cadence below.** Anything marked `retrieve` is volatile by
   definition and should be re-checked before it anchors a `required` control.

### Source ID scheme

`SRC-<PUBLISHER>-<SHORTNAME>`. Stable forever. Never renumber, never reuse — same
discipline as control IDs, for the same reason: these strings appear in
customer-facing output.

### Type markers

| Marker | Meaning | Feeds which schema field |
|---|---|---|
| **N** | Normative — states a requirement you can cite in review | `authority` |
| **R** | Rationale — explains *why*, rarely prescribes | `rationale` |
| **M** | Machine-readable — rules, schemas, or code with stable IDs | `check`, `iac_ref` |

A source can carry more than one marker. Sources with no **N** marker must not be
the sole `authority` for a `tier: required` control.

### Verified column

| Value | Meaning |
|---|---|
| `2026-08-15` | URL and status confirmed via web search on that date |
| `unverified` | Recorded from prior knowledge; URL not confirmed this session. **Confirm before first citation.** |

---

## Cross-cutting — aws-solution-architect

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-WAF-SEC | [Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html) | N | bundle | 2026-08-15 · pub 2024-11-06 |
| SRC-AWS-WAF-REL | [Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html) | N | bundle | 2026-08-15 |
| SRC-AWS-WAF-OPS | [Well-Architected Operational Excellence Pillar](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html) | N | bundle | unverified |
| SRC-AWS-SRA | [AWS Security Reference Architecture](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html) | N, M | bundle | 2026-08-15 |
| SRC-AWS-BUILDERS | [The Amazon Builders' Library](https://aws.amazon.com/builders-library/) | R | retrieve | unverified |
| SRC-NIST-53R5 | [NIST SP 800-53 Rev 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) | N, M | retrieve | unverified |

**Use the WAF best-practice IDs as a secondary key.** `SEC01-BP01`, `REL02-BP03`,
`OPS05-BP04` and friends are stable across documentation rewrites. Carrying them
on every control record gives two things for free: a join key to AWS's own
material, and a coverage audit — any WAF best practice with no corresponding
control record is a visible catalog gap rather than an invisible one.

**SRC-NIST-53R5 is published in OSCAL** (JSON/XML) with stable control IDs and
pre-built crosswalks to other frameworks. It is the one source in this register
that can be ingested mechanically without a distillation pass.

---

## aws-zero-trust

### ZT-IDN — identity

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-NIST-207 | [NIST SP 800-207 Zero Trust Architecture](https://nvlpubs.nist.gov/nistpubs/specialpublications/NIST.SP.800-207.pdf) | N | bundle | 2026-08-15 |
| SRC-NIST-1800-35 | [NIST SP 1800-35 Implementing a ZTA](https://csrc.nist.gov/pubs/sp/1800/35/final) | N, R | bundle | 2026-08-15 |
| SRC-CISA-ZTMM | [CISA Zero Trust Maturity Model v2.0](https://www.cisa.gov/zero-trust-maturity-model) | N | bundle | unverified |
| SRC-AWS-ZT-STRAT | [AWS PG: Embracing Zero Trust](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-zero-trust-architecture/introduction.html) | N | bundle | 2026-08-15 |
| SRC-AWS-IAM-BP | [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) | N | retrieve | 2026-08-15 |
| SRC-NIST-63B | [NIST SP 800-63B Authentication and Authenticator Management](https://pages.nist.gov/800-63-4/sp800-63b.html) | N | retrieve | unverified |

Notes:

- **SRC-NIST-207** (Aug 2020) remains the conceptual normative reference and is
  not superseded. **SRC-NIST-1800-35** (finalized 2025-06-10) is the
  implementation practice guide it always lacked — 19 sample builds across 24
  vendors, mapped to CSF and 800-53r5. Prefer 1800-35 for anything concrete;
  cite 207 for definitions and the policy-decision/enforcement-point model.
- **SRC-CISA-ZTMM** maturity stages map onto the `tier` field:
  traditional/initial → `contextual`, advanced → `recommended`, optimal →
  `required`. Doing this mapping once, explicitly, prevents the model from
  treating every control as mandatory.

### ZT-NET — network

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-ZT-COMP | [AWS PG: Key components of a ZTA](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-zero-trust-architecture/components.html) | N | bundle | 2026-08-15 |
| SRC-AWS-LATTICE | [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html) | N | retrieve | 2026-08-15 |
| SRC-AWS-VERIFIED-ACCESS | [AWS Verified Access User Guide](https://docs.aws.amazon.com/verified-access/latest/ug/what-is-verified-access.html) | N | retrieve | 2026-08-15 |
| SRC-AWS-MULTIVPC | [Building a Scalable and Secure Multi-VPC Network Infrastructure](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html) | N | bundle | 2026-08-15 · pub 2024-04-17 |

Network is the recommended pilot domain. It has the densest machine-readable
coverage in the check-source table below, which means the Phase 1 schema meets a
real validator soonest — which is the whole point of piloting.

### ZT-WLD — workload identity

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-SPIFFE | [SPIFFE standards](https://github.com/spiffe/spiffe/tree/main/standards) | N | bundle | unverified |
| SRC-AWS-ROLES-ANYWHERE | [IAM Roles Anywhere User Guide](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html) | N | retrieve | unverified |
| SRC-AWS-EKS-POD-ID | [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identity.html) | N | retrieve | unverified |
| SRC-AWS-PCA | [AWS Private CA User Guide](https://docs.aws.amazon.com/privateca/latest/userguide/PcaWelcome.html) | N | retrieve | unverified |

### ZT-DAT — data protection

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-KMS-BP | [AWS KMS best practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html) | N | retrieve | unverified |
| SRC-AWS-S3-BP | [S3 security best practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html) | N | retrieve | unverified |
| SRC-NIST-57 | [NIST SP 800-57 Part 1 Rev 5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final) | N | bundle | unverified |

### ZT-TEL — verification

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-IR-GUIDE | [AWS Security Incident Response Guide](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/welcome.html) | N | bundle | unverified |
| SRC-OCSF | [OCSF schema](https://schema.ocsf.io/) | N, M | retrieve | unverified |
| SRC-NIST-92 | [NIST SP 800-92r1 Log Management](https://csrc.nist.gov/pubs/sp/800/92/r1/ipd) | N | retrieve | unverified |

⚠️ **SRC-NIST-92**: last known as initial public draft. Confirm whether a final
exists before it becomes the `authority` for a `required` control — drafts are
not citable in a security review.

---

## aws-zero-downtime

### ZD-TOP — topology

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-FIB | [AWS Fault Isolation Boundaries](https://docs.aws.amazon.com/whitepapers/latest/aws-fault-isolation-boundaries/abstract-and-introduction.html) | N | bundle | 2026-08-15 |
| SRC-AWS-MAZ-PATTERNS | [Advanced Multi-AZ Resilience Patterns](https://docs.aws.amazon.com/whitepapers/latest/advanced-multi-az-resilience-patterns/advanced-multi-az-resilience-patterns.html) | N | bundle | 2026-08-15 |
| SRC-AWS-CELLS | [Reducing the Scope of Impact with Cell-Based Architecture](https://docs.aws.amazon.com/wellarchitected/latest/reducing-scope-of-impact-with-cell-based-architecture/reducing-scope-of-impact-with-cell-based-architecture.html) | N | bundle | 2026-08-15 |
| SRC-AWS-STATIC-STAB | [Static stability using Availability Zones](https://aws.amazon.com/builders-library/static-stability-using-availability-zones/) | N, R | bundle | 2026-08-15 |
| SRC-AWS-MULTIREGION | [AWS Multi-Region Fundamentals](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-multi-region-fundamentals/introduction.html) | N | bundle | 2026-08-15 |

⚠️ **SRC-AWS-MULTIREGION moved.** The `whitepapers/latest/` PDF is now marked
ARCHIVED; the maintained version lives under `prescriptive-guidance/latest/`.
The register previously pointed at the archived copy while anchoring a
`required` control — the exact failure the `Verified` column exists to catch.
Re-check on the 6-month whitepaper cadence, not just for content changes but
for relocation.

**SRC-AWS-STATIC-STAB promoted R → N.** It was registered as rationale-only, but
it states a testable requirement — overprovision 50% across three AZs so each
runs at 66% of load-tested capacity — which makes it a legitimate `authority`
for ZD-TOP-003. Authors: Becky Weiss and Mike Furr.

**SRC-AWS-FIB** is the correct anchor for the validator's "no critical-path
resource confined to a single AZ" invariant. It states what an AZ, Region,
control plane, and data plane actually guarantee — an assertion sourced from
general knowledge instead will not survive review.

**SRC-AWS-MAZ-PATTERNS** covers gray-failure detection and AZ evacuation, i.e.
the failure modes that survive `multi_az = true`. Controls derived only from the
Reliability Pillar tend to stop at the flag and miss these.

### ZD-DEP — deployment

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-DPRA | [Deployment Pipeline Reference Architecture](https://pipelines.devops.aws.dev/) | N, M | bundle | 2026-08-15 |
| SRC-AWS-CODEDEPLOY-CFG | [CodeDeploy deployment configurations](https://docs.aws.amazon.com/codedeploy/latest/userguide/deployment-configurations.html) | N | retrieve | unverified |
| SRC-AWS-ECS-CB | [ECS deployment circuit breaker](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html) | N | retrieve | unverified |
| SRC-AWS-LAMBDA-ALIAS | [Lambda alias routing configuration](https://docs.aws.amazon.com/lambda/latest/dg/configuration-aliases.html) | N | retrieve | unverified |
| SRC-AWS-BLUEGREEN-WP | [Blue/Green Deployments on AWS](https://docs.aws.amazon.com/whitepapers/latest/blue-green-deployments/welcome.html) | R | bundle | 2026-08-15 |
| SRC-GOOG-SRE-CANARY | [Google SRE Workbook: Canarying Releases](https://sre.google/workbook/canarying-releases/) | R | bundle | unverified |

⚠️ **SRC-AWS-BLUEGREEN-WP is marked R, not N, deliberately.** AWS last revised it
2021-09-29 and now labels it historical reference only, warning that content may
be outdated and links may be dead. It remains the clearest taxonomy of the
techniques, so it earns its place as a `rationale` source — but **no
`tier: required` control may name it as `authority`.** Anchor those on
SRC-AWS-DPRA or the live service docs above.

**SRC-GOOG-SRE-CANARY** covers canary sizing and evaluation statistics, which the
AWS material largely omits. Non-AWS, but the reasoning is platform-neutral.

### ZD-DAT — data continuity

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-RDS-BG | [RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments.html) | N | retrieve | unverified |
| SRC-AWS-AURORA-GLOBAL | [Aurora Global Database](https://docs.aws.amazon.com/AmazonAurora/latest/UserGuide/aurora-global-database.html) | N | retrieve | unverified |
| SRC-FOWLER-EVODB | [Evolutionary Database Design](https://martinfowler.com/articles/evodb.html) | R | bundle | unverified |

RPO/RTO figures in the AWS sources are volatile and must stay behind retrieval.
A bundled RPO number is a stale RPO number within two quarters, and it will be
quoted verbatim into a customer deliverable.

**SRC-FOWLER-EVODB** is the canonical expand/contract reference. AWS publishes no
equivalent, so the ZD-DAT schema-migration controls depend on a third-party
source — worth knowing when assessing catalog defensibility.

### ZD-DEG — degradation

| ID | Source | Type | Routing | Verified |
|---|---|---|---|---|
| SRC-AWS-RETRIES | [Builders' Library: Timeouts, retries and backoff with jitter](https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/) | N, R | bundle | unverified |
| SRC-AWS-LOADSHED | [Builders' Library: Using load shedding to avoid overload](https://aws.amazon.com/builders-library/using-load-shedding-to-avoid-overload/) | N, R | bundle | unverified |
| SRC-AWS-ALB-TG | [ALB target group attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html) | N | retrieve | 2026-08-15 |
| SRC-NYGARD-RELEASEIT | *Release It!* (Nygard), 2nd ed. | R | bundle | n/a — print |

**SRC-AWS-ALB-TG** backs the validator's deregistration-delay and health-check
threshold assertions directly.

**SRC-NYGARD-RELEASEIT** has no citable URL. Use it to shape `rationale`
phrasing; never as `authority`, since a reviewer cannot follow it.

---

## Check sources — feeds `check:` (Phase 3)

Catalogs of existing, stably-identified rules. Point `check:` at one of these
before hand-writing Rego; the ratio of controls reusing an upstream rule to
controls needing bespoke policy is a good early read on how differentiated the
catalog actually is.

| ID | Source | Provides | Verified |
|---|---|---|---|
| SRC-AWS-SECHUB-CTRL | [Security Hub CSPM controls reference](https://docs.aws.amazon.com/securityhub/latest/userguide/controls-reference.html) | Several hundred controls, each with ID, rationale, remediation | unverified |
| SRC-AWS-CONFIG-RULES | [AWS Config managed rules](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) | Runtime checks, complements plan-time policy | unverified |
| SRC-CHECKOV | [Checkov policy index](https://www.checkov.io/5.Policy%20Index/terraform.html) | `CKV_AWS_*` IDs, Terraform-plan-native | 2026-08-15 |
| SRC-TRIVY | [Trivy AWS misconfiguration checks](https://avd.aquasec.com/misconfig/aws/) | `AVD-AWS-*` IDs | unverified |
| SRC-GUARD-REGISTRY | [AWS Guard Rules Registry](https://github.com/aws-cloudformation/aws-guard-rules-registry) | cfn-guard rules pre-mapped to NIST 800-53, CIS, PCI, HIPAA | unverified |
| SRC-CDK-NAG | [cdk-nag rule packs](https://github.com/cdklabs/cdk-nag/blob/main/RULES.md) | `AwsSolutions`, `NIST80053R5`, `HIPAA`, `PCI` packs | unverified |
| SRC-AWS-AA-CUSTOM | [IAM Access Analyzer custom policy checks](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-custom-policy-checks.html) | Validator Stage 3 | unverified |
| SRC-AWS-FIS | [AWS Fault Injection Service scenarios](https://docs.aws.amazon.com/fis/latest/userguide/fis-scenarios.html) | Empirical verification of ZD-TOP invariants | unverified |
| SRC-CIS-AWS-FB | [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services) | Numbered baseline controls | 2026-08-15 |

**SRC-AWS-SECHUB-CTRL is the best extraction seed in this register.** Its records
already carry an ID, a rationale, and a remediation — structurally close to the
control record schema, so extraction there is closer to transformation than
distillation.

**SRC-AWS-FIS** is the only source here that *verifies* a zero-downtime control
rather than asserting it. Its AZ-availability-power-interruption scenario
exercises the ZD-TOP invariants against a real failure.

⚠️ **SRC-CIS-AWS-FB version skew.** Current benchmark is **v7.0.0 (April 2026)**.
Security Hub CSPM added **v5.0** support in October 2025 — automated coverage
trails the published benchmark by two major versions. Pin the version inside the
anchor (`SRC-CIS-AWS-FB@v7.0.0#1.14`) or checks will drift silently away from
their citations.

---

## Licensing

License is a property of the publisher, not the document.

| Publisher | Terms | Practical effect |
|---|---|---|
| NIST (800-207, 800-53, 800-57, 800-63, 1800-35) | US Government work, public domain | Copy verbatim into control records freely |
| AWS (docs, whitepapers, Builders' Library, DPRA) | Copyrighted, all rights reserved | Cite by URL + anchor; paraphrase. No bulk copying into `rationale` |
| CIS | Free PDF for non-commercial use; redistribution restricted | ⚠️ If the skill emits CIS control *text* to a customer, review terms first |
| Google (SRE Workbook) | CC BY-NC-ND 4.0 | Cite and link; no derivative text |
| Fowler / Nygard | Copyrighted | Rationale shaping only |

The schema is mostly safe by construction, since `authority` stores a reference
rather than inlined prose. **The exposure is `rationale`** — that field is where
verbatim copying creeps in during extraction. Worth an explicit check in the
Phase 1.3 human review gate.

---

## Re-verification cadence

Per the plan's Phase 5 review-date requirement:

| Class | Cadence | Trigger |
|---|---|---|
| `retrieve` AWS service docs | 3 months | Any control citing it reaches `required` |
| `bundle` AWS whitepapers | 6 months | Re-read the revision history, not just the URL |
| NIST / CISA | 12 months | Draft → final transitions |
| Check sources | 3 months | Upstream rule catalogs change monthly |
| CIS benchmark | On each release | Confirm Security Hub coverage lag before repinning |

---

## Open items

1. **31 of 38 sources remain `unverified`.** Seven were confirmed by fetch on
   2026-08-15 (see `knowledge-base/sources/manifest.yaml`); the rest are still
   recorded from prior knowledge. Resolve each URL before it becomes the
   `authority` for its first control — the cheapest step in Phase 1 and the most
   expensive to skip, since a dead `authority` link is discovered by a customer,
   not by you.

   Verification has already paid for itself twice: **SRC-AWS-BLUEGREEN-WP** is
   AWS-labelled historical, and **SRC-AWS-MULTIREGION**'s registered URL was the
   archived copy. Both were anchoring controls at the time.

   Highest-priority remaining: **SRC-AWS-SECHUB-CTRL**, the best extraction seed
   in the register and the most likely source of new `check` coverage.
2. **SRC-NIST-92 draft status** unresolved (see ZT-TEL).
3. **No source registered for the multi-account assumption** in the plan's open
   decision #3. If generated architectures assume Control Tower / Organizations
   landing zones, add the Landing Zone Accelerator and Control Tower docs here
   and reference them from `intake-schema.md`.
4. **Register owner unassigned.** Phase 1.3's review gate needs a named owner or
   it degrades to auto-merge; this file is where that ownership becomes concrete.
5. **🔴 No curated KB exists** — so `kb_source` is unpopulated on every control
   extracted so far, and the catalog currently encodes public documentation
   only. This is the blocking finding from the network pilot; see
   `/VERIFICATION.md` before extending ingestion to further domains.
