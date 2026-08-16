# ZT-TEL — Verification

Logging, detection, correlation, and remediation. Extracted 2026-08-15 from the
Well-Architected Security Pillar (SEC04).

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

Zero Trust's "never trust, always verify" has two halves, and this domain is the
second one. Controls elsewhere in the catalog decide access; these controls
establish whether those decisions are actually being made as designed. A control
nobody can observe is an intention.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZT-TEL-001 | Service and application logging is configured | required | `zt-tel-001` |
| ZT-TEL-002 | Logs land in a standardized, tamper-resistant location | required | — |
| ZT-TEL-003 | Security alerts are correlated and enriched | required | — |
| ZT-TEL-004 | Non-compliant resources trigger remediation | recommended | — |
| ZT-TEL-005 | Configuration change is detected, not assumed | required | — |
| ZT-TEL-006 | Authorization decisions are observable | required | — |
| ZT-TEL-007 | Detection coverage is reviewed against the control set | recommended | — |

---

### ZT-TEL-001 — Service and application logging is configured
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC04-BP01
**Applies when:** Any workload
**Authority:** SRC-AWS-WAF-SEC#SEC04-BP01 · **Check:** `policies/opa/zt-tel-001.rego`

Logging that is switched on after an incident begins covers none of the incident.
This is the one control whose value is entirely determined before it is needed.

- CloudTrail enabled in all regions, including management and data events for
  sensitive resources.
- VPC flow logs on workload VPCs.
- ALB/CloudFront access logs enabled.
- Application logs to CloudWatch Logs with a defined retention period.

---

### ZT-TEL-002 — Logs land in a standardized, tamper-resistant location
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC04-BP02
**Applies when:** Criticality 0 or 1, or any multi-account model
**Authority:** SRC-AWS-WAF-SEC#SEC04-BP02 · **Check:** —

Logs stored in the account that generated them are writable by whoever
compromised that account. Centralization is not a convenience — it is what makes
the record survive the event it records.

- Delivery to a dedicated log archive account (Control Tower provides one).
- Object Lock or equivalent immutability on the archive bucket.
- Producing accounts have write access, not delete.
- Security Lake with OCSF normalization where multiple sources must be joined.

---

### ZT-TEL-003 — Security alerts are correlated and enriched
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC04-BP03
**Applies when:** Criticality 0 or 1
**Authority:** SRC-AWS-WAF-SEC#SEC04-BP03 · **Check:** —

A finding without context arrives as a question rather than an answer. Enrichment
is what makes the difference between an alert somebody triages and an alert
somebody mutes.

- GuardDuty enabled; findings aggregated to the security account.
- Security Hub as the aggregation point across accounts and regions.
- Findings enriched with resource tags — workload, environment, owner, and the
  ZT-DAT-001 classification.
- Alert on mutating API calls the workload should never make, and on any change
  to security posture.

---

### ZT-TEL-004 — Non-compliant resources trigger remediation
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC04-BP04
**Applies when:** AWS Config or Security Hub is in use
**Authority:** SRC-AWS-WAF-SEC#SEC04-BP04 · **Check:** —

Detection without a response path produces a dashboard whose numbers only ever
rise. Automating the safe subset keeps the remainder small enough to act on.

- Config rules mapped to catalog controls where an upstream rule exists.
- Auto-remediation for unambiguous, low-risk cases — public access blocked,
  encryption enabled on a new resource.
- Everything else routed to an owner with an SLA, not to a queue.

---

### ZT-TEL-005 — Configuration change is detected, not assumed
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC04-BP01
**Applies when:** Infrastructure is defined as code
**Authority:** SRC-AWS-WAF-SEC#detection · **Check:** —

ZT-NET-013 requires network controls be applied by automation. This control is
what makes that claim checkable afterwards: drift is the gap between what the
code says and what the account does.

- Config recording enabled for the resource types the catalog governs.
- Drift detection on IaC stacks; out-of-band change alerts.
- Changes outside a known deployment or scaling event are treated as incidents
  until explained.

---

### ZT-TEL-006 — Authorization decisions are observable
**Tier:** required · **Criticality:** 0,1
**Applies when:** VPC Lattice, Verified Access, or resource policies mediate access
**Authority:** SRC-AWS-LATTICE#vpc-service-network-features · **Check:** —

The catalog's network and identity controls assert that access is decided per
request. Without logs of those decisions the assertion cannot be checked, and
"deny by default" becomes a claim about intent rather than behavior.

- VPC Lattice access logs enabled at the service network *and* service level —
  the two capture different scopes.
- Verified Access logs all attempts, permitted and denied.
- Denied requests reviewed: a policy that never denies anything is usually
  matching more broadly than intended.

---

### ZT-TEL-007 — Detection coverage is reviewed against the control set
**Tier:** recommended · **Criticality:** 0
**Applies when:** Criticality 0
**Authority:** SRC-AWS-WAF-SEC#detection · **Check:** —

The gap worth measuring is between controls the catalog asserts and controls
anything would notice being violated. That gap is invisible unless something
compares the two lists deliberately.

- Map each applied control to the signal that would reveal its failure.
- Controls with no corresponding signal are recorded as unmonitored.
- Review on catalog version change, since new controls arrive unmonitored by
  default.
