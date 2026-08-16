# Zero Trust Control Catalog — Index

**Catalog version:** see `/CATALOG_VERSION` · 53 controls · extracted 2026-08-15

Read this file first. Load domain files only for the domains a brief touches.

## Status

| Property | Value |
|---|---|
| Phase 1.3 human review | **Not performed.** All controls are `review_status: pending`. |
| `authority` coverage | 53 / 53 — every control cites a verified upstream source |
| `kb_source` coverage | **0 / 53** — no curated house KB exists |
| Enforceable (`check` defined) | 12 / 53 (23%) |

The `kb_source` figure is the one to watch. It means this catalog currently
encodes public AWS documentation rather than institutional judgment. The
controls are correct; they are not yet differentiated. See SKILL.md § Catalog
status before quoting this catalog as a competitive artifact.

## Domains

| Prefix | Domain | File | Controls | Checked |
|---|---|---|---|---|
| ZT-IDN | Identity | `identity.md` | 13 | 2 |
| ZT-NET | Network | `network.md` | 16 | 4 |
| ZT-WLD | Workload identity | `workload-identity.md` | 8 | 2 |
| ZT-DAT | Data protection | `data-protection.md` | 9 | 3 |
| ZT-TEL | Verification | `verification.md` | 7 | 1 |

## All controls

### ZT-IDN — Identity
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZT-IDN-001 | Human access uses federated temporary credentials | required | 0,1,2 | — |
| ZT-IDN-002 | A centralized identity provider is authoritative | required | 0,1 | — |
| ZT-IDN-003 | Phishing-resistant MFA where IAM users remain | required | 0,1,2 | — |
| ZT-IDN-004 | Root user credentials are protected and unused | required | 0,1,2 | — |
| ZT-IDN-005 | No long-term access keys without a recorded use case | required | 0,1 | ✓ |
| ZT-IDN-006 | Policies grant least privilege | required | 0,1 | ✓ |
| ZT-IDN-007 | Permissions are reduced continuously | recommended | 0,1 | — |
| ZT-IDN-008 | Policy conditions constrain access further | recommended | 0,1 | — |
| ZT-IDN-009 | Public and cross-account access is analyzed | required | 0,1 | Stage 3 |
| ZT-IDN-010 | Organization-wide permission guardrails exist | required | 0,1 | — |
| ZT-IDN-011 | Permissions boundaries delegate safely | recommended | 0,1 | — |
| ZT-IDN-012 | An emergency access path is defined and tested | required | 0,1 | — |
| ZT-IDN-013 | Access follows identity lifecycle | required | 0,1 | — |

### ZT-NET — Network
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZT-NET-001 | Network layers defined by trust boundary | required | 0,1,2 | — |
| ZT-NET-002 | IP space centrally allocated and non-overlapping | required | 0,1 | — |
| ZT-NET-003 | Internet egress centralized and inspected | required | 0,1 | ✓ |
| ZT-NET-004 | Traffic between layers explicitly authorized | required | 0,1,2 | — |
| ZT-NET-005 | Reachability requires service network association | recommended | 0,1 | — |
| ZT-NET-006 | Security groups on VPC–service network association | recommended | 0,1 | — |
| ZT-NET-007 | Service networks carry a coarse auth policy | recommended | 0,1 | — |
| ZT-NET-008 | Services carry a fine-grained auth policy | recommended | 0,1 | — |
| ZT-NET-009 | Application access evaluated per request | required | 0,1 | — |
| ZT-NET-010 | AWS service access via VPC endpoints | required | 0,1 | — |
| ZT-NET-012 | Inspection-based protection in the traffic path | recommended | 0,1 | — |
| ZT-NET-013 | Network protection applied by automation | required | 0,1 | — |
| ZT-NET-014 | Private-tier subnets deny unrestricted ingress | required | 0,1 | ✓ |
| ZT-NET-015 | Subnets do not auto-assign public IPs | required | 0,1,2 | ✓ |
| ZT-NET-016 | Every security group rule carries a description | recommended | 0,1,2 | ✓ |
| ZT-NET-021 | Non-HTTP public exposure is firewall-inspected | required | 0,1 | — |

*ZT-NET-011 reserved, not yet authored.*

### ZT-WLD — Workload identity
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZT-WLD-001 | AWS-hosted workloads use instance or task roles | required | 0,1,2 | ✓ |
| ZT-WLD-002 | External workloads use certificate-based federation | required | 0,1 | — |
| ZT-WLD-003 | CI/CD authenticates via OIDC, not stored keys | required | 0,1 | — |
| ZT-WLD-004 | Each workload has its own identity | required | 0,1 | — |
| ZT-WLD-005 | Secrets are stored in a managed secret store | required | 0,1,2 | ✓ |
| ZT-WLD-006 | Service-to-service calls are mutually authenticated | recommended | 0,1 | — |
| ZT-WLD-007 | Workload credentials are short-lived | required | 0,1 | — |
| ZT-WLD-008 | Container workloads use per-pod identity | required | 0,1 | — |

### ZT-DAT — Data protection
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZT-DAT-001 | Data is classified before it is stored | required | 0,1 | — |
| ZT-DAT-002 | Encryption at rest is enforced, not merely enabled | required | 0,1,2 | ✓ |
| ZT-DAT-003 | Key management is deliberate | required | 0,1 | — |
| ZT-DAT-004 | Key usage is audited | recommended | 0,1 | — |
| ZT-DAT-005 | Access control is enforced at the resource | required | 0,1 | ✓ |
| ZT-DAT-006 | Encryption in transit is enforced | required | 0,1,2 | ✓ |
| ZT-DAT-007 | Certificates are centrally managed | required | 0,1 | — |
| ZT-DAT-008 | Data-at-rest protection is automated | recommended | 0,1 | — |
| ZT-DAT-009 | Regulated data is tokenized or masked | contextual | 0 | — |

### ZT-TEL — Verification
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZT-TEL-001 | Service and application logging is configured | required | 0,1,2 | ✓ |
| ZT-TEL-002 | Logs land in a standardized, tamper-resistant location | required | 0,1 | — |
| ZT-TEL-003 | Security alerts are correlated and enriched | required | 0,1 | — |
| ZT-TEL-004 | Non-compliant resources trigger remediation | recommended | 0,1 | — |
| ZT-TEL-005 | Configuration change is detected, not assumed | required | 0,1 | — |
| ZT-TEL-006 | Authorization decisions are observable | required | 0,1 | — |
| ZT-TEL-007 | Detection coverage reviewed against the control set | recommended | 0 | — |

## Cross-domain dependencies

Controls that name another control. Breaking one of these breaks the other.

| Control | Depends on | Why |
|---|---|---|
| ZT-NET-014 (exception) | ZT-NET-021 | Non-HTTP public exposure needs a compensating inspection point |
| ZT-NET-003 (exception) | ZT-NET-012 | Decentralized egress needs local inspection |
| ZT-NET-021 | ZT-TEL-002 | Firewall flow logs must reach the archive |
| ZT-IDN-004 | ZT-TEL-003 | Root sign-in alerting |
| ZT-IDN-005 | ZT-WLD-002 | Try certificate federation before concluding a key is needed |
| ZT-DAT-004 | ZT-TEL-003 | Key-usage findings need a routing path |
| ZT-DAT-008 | ZT-TEL-004 | Remediation path for non-compliant storage |
| ZT-TEL-005 | ZT-NET-013 | Drift detection is what makes "applied by automation" checkable |
| ZT-TEL-006 | ZT-NET-007, ZT-NET-008 | Lattice policies must be logged at both levels |
| ZT-WLD-006 | ZT-NET-008 | mTLS and Lattice auth policies are alternative implementations |

## Known gaps

1. **No `kb_source` on any control.** The blocking finding — see
   `/VERIFICATION.md`.
2. **ZT-NET-011 reserved but unauthored** (private DNS resolution); source not
   yet ingested.
3. **ZT-NET-009 authority is thin** — an overview page with no testable
   configuration detail, yet the control is `required`.
4. **ZT-NET-016 authority is weak** — SEC05-BP04 concerns automation, not rule
   documentation.
5. **No SPIFFE-grounded controls** in ZT-WLD despite SRC-SPIFFE being registered;
   ZT-WLD-006 rests on SEC09-BP03 instead.
6. **77% of controls have no check.** Most are architectural assertions no
   generic linter expresses. Expect them to sit at `recommended`.
