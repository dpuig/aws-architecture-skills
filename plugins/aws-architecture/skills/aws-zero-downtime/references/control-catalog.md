# Zero Downtime Control Catalog — Index

**Catalog version:** see `/CATALOG_VERSION` · 43 controls · extracted 2026-08-15

Read this file first. Load domain files only for the domains a brief touches.

## Status

| Property | Value |
|---|---|
| Phase 1.3 human review | **Not performed.** All controls are `review_status: pending`. |
| `authority` coverage | 43 / 43 |
| `kb_source` coverage | **0 / 43** — no curated house KB exists |
| Enforceable (`check` defined) | 10 / 43 (23%) |

## Domains

| Prefix | Domain | File | Controls | Checked |
|---|---|---|---|---|
| ZD-TOP | Topology | `topology.md` | 12 | 3 |
| ZD-DEP | Deployment | `deployment.md` | 11 | 2 |
| ZD-DAT | Data continuity | `data-continuity.md` | 10 | 3 |
| ZD-DEG | Degradation | `degradation.md` | 10 | 2 |

## Where checks execute

| Stage | Mechanism | Controls |
|---|---|---|
| 2 | `policies/opa/*.rego` via conftest | ZD-TOP-011, ZD-DEP-003, ZD-DAT-003, ZD-DAT-004, ZD-DEG-009 |
| 4 | `validate.sh` Python assertions | ZD-TOP-001, ZD-TOP-004, ZD-DAT-002, ZD-DEG-001, ZD-DEP-002 |

Stage 4 checks are **tier-aware**: the same plan passes at tier 1 and fails at
tier 0. That is why they are not Rego rules — a policy engine evaluating one
resource at a time cannot see the workload's criticality.

⚠️ **The five Stage 4 control IDs are hard-coded in `validate.sh`.** Renumbering
any of them breaks the validator without producing an error — the control simply
stops being reported.

## All controls

### ZD-TOP — Topology
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZD-TOP-001 | Workload spans multiple Availability Zones | required | 0,1 | Stage 4 |
| ZD-TOP-002 | Single-location components have automated recovery | required | 0,1 | — |
| ZD-TOP-003 | Static stability: capacity pre-provisioned for N-1 | required | 0 | — |
| ZD-TOP-004 | Auto Scaling minimum survives loss of one AZ | required | 0,1 | Stage 4 |
| ZD-TOP-005 | Recovery relies on the data plane, not the control plane | required | 0 | — |
| ZD-TOP-006 | Bulkheads limit scope of impact | recommended | 0,1 | — |
| ZD-TOP-007 | Cell-based partitioning is evaluated and decided | recommended | 0 | — |
| ZD-TOP-008 | Zonal impairment is detectable | required | 0 | — |
| ZD-TOP-009 | AZ evacuation is a rehearsed procedure | recommended | 0 | — |
| ZD-TOP-010 | Multi-Region posture is explicit | required | 0 | — |
| ZD-TOP-011 | Failover targets healthy resources automatically | required | 0,1 | ✓ |
| ZD-TOP-012 | An availability target is stated and architected to | required | 0,1 | — |

### ZD-DEP — Deployment
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZD-DEP-001 | Deployments are automated | required | 0,1,2 | — |
| ZD-DEP-002 | Every deployment declares a rollback path | required | 0,1 | Stage 4 |
| ZD-DEP-003 | Infrastructure is immutable | required | 0,1 | ✓ |
| ZD-DEP-004 | Functional testing gates the pipeline | required | 0,1 | — |
| ZD-DEP-005 | Resiliency testing gates the pipeline | recommended | 0 | — |
| ZD-DEP-006 | Runbooks exist for standard activities | recommended | 0,1 | — |
| ZD-DEP-007 | Exposure is progressive and tier-appropriate | required | 0,1 | — |
| ZD-DEP-008 | Deployments touch one AZ at a time | required | 0 | — |
| ZD-DEP-009 | Promotion between stages is health-gated | required | 0,1 | — |
| ZD-DEP-010 | Deploy is decoupled from release | recommended | 0,1 | — |
| ZD-DEP-011 | Deployment requires no maintenance window | required | 0,1 | — |

### ZD-DAT — Data continuity
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZD-DAT-001 | Recovery objectives are defined | required | 0,1 | — |
| ZD-DAT-002 | Databases are Multi-AZ | required | 0,1 | Stage 4 |
| ZD-DAT-003 | Backups are automated and retained | required | 0,1,2 | ✓ |
| ZD-DAT-004 | Backups are encrypted and access-controlled | required | 0,1 | ✓ |
| ZD-DAT-005 | Recovery is periodically tested | required | 0,1 | — |
| ZD-DAT-006 | Schema changes follow expand/contract | required | 0,1 | — |
| ZD-DAT-007 | Replication lag is monitored against RPO | required | 0 | — |
| ZD-DAT-008 | All data needing backup is identified | required | 0,1 | — |
| ZD-DAT-009 | DR configuration drift is managed | recommended | 0 | — |
| ZD-DAT-010 | Recovery is automated | recommended | 0 | — |

### ZD-DEG — Degradation
| ID | Title | Tier | Crit | Check |
|---|---|---|---|---|
| ZD-DEG-001 | Target groups declare draining and health thresholds | required | 0,1,2 | Stage 4 |
| ZD-DEG-002 | Client timeouts are set | required | 0,1 | — |
| ZD-DEG-003 | Retries are limited and use backoff with jitter | required | 0,1 | — |
| ZD-DEG-004 | Requests are throttled | required | 0,1 | — |
| ZD-DEG-005 | Hard dependencies are made soft where possible | recommended | 0,1 | — |
| ZD-DEG-006 | Fail fast; queues are bounded | required | 0,1 | — |
| ZD-DEG-007 | Services are stateless where possible | recommended | 0,1 | — |
| ZD-DEG-008 | Emergency levers exist | recommended | 0 | — |
| ZD-DEG-009 | Zonal brownout is bounded by health thresholds | recommended | 0 | ✓ |
| ZD-DEG-010 | Slow start is enabled for warm-up-sensitive targets | contextual | 0,1 | — |

## Cross-domain dependencies

| Control | Depends on | Why |
|---|---|---|
| ZD-TOP-004 | ZD-TOP-003 | ASG minimum is the concrete form of static stability |
| ZD-TOP-009 | ZD-TOP-008, ZD-TOP-005 | Cannot evacuate what you cannot detect; evacuation must be data-plane |
| ZD-TOP-010 | ZD-DAT-001 | The DR strategy must satisfy the stated RPO/RTO |
| ZD-DEP-002 | ZD-DAT-006 | A dropped column cannot be rolled back by redeploying |
| ZD-DEP-008 | ZD-TOP-003 | One-AZ-at-a-time only works if N-1 capacity absorbs it |
| ZD-DEP-011 | ZD-DEG-001, ZD-DAT-006 | No-window deployment needs draining and compatible schema |
| ZD-DEP-005 | ZD-TOP-001,-003,-004,-008 | FIS exercises all four in one experiment |
| ZD-DAT-004 | ZT-DAT-002 | Backup encryption is stated in full in the Zero Trust catalog |
| ZD-DEG-009 | ZD-TOP-003 | Shifting a zone's traffic requires spare capacity to receive it |
| ZD-DEG-007 | ZD-DEP-003, ZD-TOP-004 | Disposability is the precondition for immutability and scale-in |

**Cross-catalog:** ZD-DAT-004 depends on ZT-DAT-002. The two catalogs are not
independent, and a deliverable applying one without the other will have a gap at
that seam.

## Known gaps

1. **No `kb_source` on any control** — the blocking finding across all three
   skills.
2. **ZD-DAT-006 (expand/contract) rests on a third-party source.** AWS publishes
   no equivalent, and this is one of the most load-bearing controls in the
   catalog — ZD-DEP-002 and ZD-DEP-011 both depend on it.
3. **77% of controls have no check**, and most of the unchecked ones are process
   assertions (runbooks exist, recovery is tested, objectives are defined) that
   no plan-time analysis can verify. Unlike the network domain, this is not a
   gap that more Rego would close — it needs evidence from outside the plan.
4. **ZD-DEG-002/003/004/006 are application-level** — timeouts, retries,
   throttling, queue bounds live in code, not Terraform. They will sit at
   `recommended` permanently under a plan-only validator.
5. ~~SRC-AWS-STATIC-STAB and SRC-AWS-MULTIREGION unverified while anchoring
   `required` controls.~~ **Resolved 2026-08-15.** Both fetched and verified.
   SRC-AWS-MULTIREGION's registered URL turned out to point at the *archived*
   whitepaper; the maintained version is under `prescriptive-guidance/latest/`
   and the register now points there. Both controls gained concrete
   requirements from the verified text — the 66%-of-load-tested figure in
   ZD-TOP-003, and the data-reconciliation requirement in ZD-TOP-010.
   No schema rule 2 violations remain in this catalog.
