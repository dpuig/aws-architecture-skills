# ZD-DEP — Deployment

Shipping change without an outage. Extracted 2026-08-15 from the Well-Architected
Reliability Pillar (REL08) and the Deployment Pipeline Reference Architecture.

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

⚠️ **ZD-DEP-002 is referenced by name in `validate.sh` Stage 4.**

**Note on sourcing:** the Blue/Green Deployments on AWS whitepaper
(SRC-AWS-BLUEGREEN-WP) is AWS-labelled historical, last revised 2021-09-29. It
remains the clearest taxonomy of the techniques and is cited for *rationale*
only. No control here takes it as `authority`.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZD-DEP-001 | Deployments are automated | required | — |
| ZD-DEP-002 | Every deployment declares a rollback path | required | Stage 4 |
| ZD-DEP-003 | Infrastructure is immutable | required | `zd-dep-003` |
| ZD-DEP-004 | Functional testing gates the pipeline | required | — |
| ZD-DEP-005 | Resiliency testing gates the pipeline | recommended | — |
| ZD-DEP-006 | Runbooks exist for standard activities | recommended | — |
| ZD-DEP-007 | Exposure is progressive and tier-appropriate | required | — |
| ZD-DEP-008 | Deployments touch one AZ at a time | required | — |
| ZD-DEP-009 | Promotion between stages is health-gated | required | — |
| ZD-DEP-010 | Deploy is decoupled from release | recommended | — |
| ZD-DEP-011 | Deployment requires no maintenance window | required | — |

---

### ZD-DEP-001 — Deployments are automated
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** REL08-BP05
**Applies when:** Any workload deployed more than once
**Authority:** SRC-AWS-WAF-REL#REL08-BP05 · **Check:** —

Manual deployment makes every release a bespoke event whose outcome depends on
who ran it. Automation is the precondition for every other control in this
domain — you cannot canary, gate, or roll back a process someone performs by
hand.

- Pipeline is the only path to production; no console or local `apply`.
- The same artifact promotes across environments; nothing is rebuilt per stage.
- Deployment is idempotent and re-runnable.

---

### ZD-DEP-002 — Every deployment declares a rollback path
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL08-BP05
**Applies when:** Any deployment-managing resource in the plan
**Authority:** SRC-AWS-DPRA · **Check:** validator Stage 4

Rollback must be a configured mechanism, not an intention. The moment it is
needed is the moment nobody has time to invent one, and "redeploy the previous
version" is not a rollback if the previous version's artifact has already been
garbage-collected.

- ECS: deployment circuit breaker with `rollback = true`.
- Lambda: alias weighting with CodeDeploy, and alarms wired to trigger it.
- EC2/ASG: CodeDeploy deployment group with automatic rollback on alarm.
- Rollback is automatic on health signal, not gated on a human decision.

**Exception:** a forward-only change whose rollback is genuinely impossible —
typically a destructive schema migration → requires ZD-DAT-006 (expand/contract,
which makes the change reversible) or an explicit, recorded acceptance.

---

### ZD-DEP-003 — Infrastructure is immutable
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL08-BP04
**Applies when:** Any compute fleet
**Authority:** SRC-AWS-WAF-REL#REL08-BP04 · **Check:** `policies/opa/zd-dep-003.rego`

In-place mutation produces hosts whose state is the sum of every change ever
applied to them, in order, with failures. Replacement produces hosts whose state
is a function of the artifact alone — which is the property that makes rollback
mean anything.

- New AMIs or images per release; no in-place package upgrades.
- Launch templates, not launch configurations (which cannot be versioned).
- No SSH-based configuration management in the deployment path.

---

### ZD-DEP-004 — Functional testing gates the pipeline
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL08-BP02
**Applies when:** Any automated deployment
**Authority:** SRC-AWS-WAF-REL#REL08-BP02 · **Check:** —

- Tests run against a deployed environment, not only at build time.
- Failure stops promotion; it does not warn and continue.
- The pipeline is the authority on release readiness — if it is green, the
  change ships; if it is red, nothing does, including the fix for something
  else.

---

### ZD-DEP-005 — Resiliency testing gates the pipeline
**Tier:** recommended · **Criticality:** 0 · **WAF:** REL08-BP03
**Applies when:** Criticality 0
**Authority:** SRC-AWS-WAF-REL#REL08-BP03 · **Check:** —

Every ZD-TOP control is a hypothesis until something fails on purpose. This is
the control that converts them into facts.

- AWS Fault Injection Service experiments in a pre-production stage.
- The AZ-availability power-interruption scenario exercises ZD-TOP-001, -003,
  -004 and -008 in one run.
- Steady-state hypothesis defined before the experiment; a run with no stated
  expectation cannot fail.

---

### ZD-DEP-006 — Runbooks exist for standard activities
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** REL08-BP01
**Applies when:** Criticality 0 or 1
**Authority:** SRC-AWS-WAF-REL#REL08-BP01 · **Check:** —

- Deployment, rollback, and evacuation each have a runbook.
- Runbooks are executable where possible (Systems Manager documents), because
  prose runbooks drift from reality and nobody notices until they are used.
- Reviewed after each incident that used one.

---

### ZD-DEP-007 — Exposure is progressive and tier-appropriate
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL08-BP05
**Applies when:** Any production deployment
**Authority:** SRC-AWS-DPRA · **Check:** —

The purpose of progressive exposure is to bound the number of users who see a
bad change. Its value comes entirely from the gap between first exposure and
full rollout — a canary promoted after 60 seconds has tested nothing but
startup.

| Criticality | Strategy |
|---|---|
| 0 | Canary or blue/green, automated rollback, bake time sized to observe real traffic |
| 1 | Rolling with health gates |
| 2 | Any, with a documented rollback |

- Bake time long enough for the slowest meaningful signal — error rates surface
  in minutes, latency regressions and memory leaks in hours.
- Canary traffic representative, not synthetic-only.

---

### ZD-DEP-008 — Deployments touch one Availability Zone at a time
**Tier:** required · **Criticality:** 0 · **WAF:** REL08-BP05
**Applies when:** Criticality 0
**Authority:** SRC-AWS-WAF-REL#implement-change · **Check:** —

AWS's own rule: never touch multiple AZs in a Region simultaneously. A
deployment that lands everywhere at once is a correlated failure the AZ
independence assumption explicitly excludes — it converts the topology work in
ZD-TOP into nothing.

- Deployment sequenced by AZ, with a health gate between zones.
- The blast radius of a bad release is one AZ, which ZD-TOP-003 capacity
  absorbs.
- Applies to configuration and feature-flag changes, not only code.

---

### ZD-DEP-009 — Promotion between stages is health-gated
**Tier:** required · **Criticality:** 0,1
**Applies when:** More than one deployment stage exists
**Authority:** SRC-AWS-DPRA · **Check:** —

- Each stage defines the signals that must be healthy before promotion.
- Gates are automatic; a manual approval is a policy decision, not a health
  check, and the two should not be confused.
- The pipeline halts on an unhealthy signal rather than proceeding with a
  warning.

---

### ZD-DEP-010 — Deploy is decoupled from release
**Tier:** recommended · **Criticality:** 0,1
**Applies when:** Feature work ships continuously
**Authority:** SRC-AWS-WAF-REL#implement-change · **Check:** —

A feature flag turns a rollback into a configuration change — seconds rather
than a deployment cycle, and without reverting unrelated changes that shipped in
the same release.

- Features ship disabled and are enabled independently.
- Flags have owners and removal dates; a permanent flag is a branch in
  production that nobody tests both sides of.
- Kill switches for expensive or risky paths (see ZD-DEG-008).

---

### ZD-DEP-011 — Deployment requires no maintenance window
**Tier:** required · **Criticality:** 0,1
**Applies when:** `maintenance_window` is null in the intake brief
**Authority:** SRC-AWS-DPRA · **Check:** —

The intake schema treats an unspecified maintenance window as *zero-downtime
required*. This control is where that decision becomes architecture.

- Connection draining on target deregistration (ZD-DEG-001).
- Schema changes backward-compatible (ZD-DAT-006).
- No deployment step requires stopping the workload.

**Exception:** the business has explicitly agreed a window → requires the
agreement recorded with a named owner. "We have always had one" is not an
agreement.
