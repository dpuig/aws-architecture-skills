# Criticality Tier Model

Converts "how much does this workload matter" into "which controls are
obligatory." Read this in workflow step 2, before selecting controls.

Two independent axes, routinely confused:

- **Workload criticality** (this file) — 0, 1, or 2. A property of the *system*.
- **Control tier** (`required` / `recommended` / `contextual`) — how strongly a
  control is held when it applies. A property of the *control*.

The obligation matrix below is where they meet. Keeping them separate is what
stops the catalog carpet-bombing every architecture — the over-application
failure that makes output unusable and trains users to ignore it.

---

## Determining criticality

Ask directly. **If unstated, ask — do not assume tier-0.** Assuming maximum
criticality feels safe and is not: it produces 200-control output for an
internal reporting tool, the user discards the whole deliverable, and the
controls that genuinely mattered go with it.

Place the workload at the **highest tier any single question triggers**.

| Question | Tier 0 if… |
|---|---|
| What happens in a one-hour outage? | Revenue stops, safety is affected, or a regulator must be notified |
| What data does it hold? | Regulated data — PHI, cardholder, or equivalent under a named regime |
| Who depends on it? | External customers under contractual SLA, or other tier-0 systems |
| What does a breach cost? | Mandatory disclosure |

| Question | Tier 1 if… |
|---|---|
| What happens in a one-hour outage? | Material internal disruption; work stops but recovers |
| What data does it hold? | Confidential business data, internal PII |
| Who depends on it? | Internal teams broadly, or tier-1 systems |

**Tier 2** is the remainder: internal tools, experiments, non-production. Failure
is an inconvenience absorbed without escalation.

### Recording the decision

The tier and the reason both go in the intake brief. "Tier 1" is not a decision;
"Tier 1 — internal PII, no external SLA, one-hour outage disrupts one team" is.
The reason is what makes the tier reviewable later, when someone disagrees.

---

## Obligation matrix

A control applies only if its `applies_to_criticality` includes the workload's
tier **and** its `applies_when` matches the brief. Given that, obligation is:

| Control `tier` | Criticality 0 | Criticality 1 | Criticality 2 |
|---|---|---|---|
| `required` | **Mandatory** | **Mandatory** | Advisory |
| `recommended` | **Must be resolved** | Advisory | Advisory |
| `contextual` | Advisory | Advisory | Advisory |

**Mandatory** — must reach `satisfied` or `waived` with a recorded exception.
A `failed` mandatory control fails the whole deliverable.

**Must be resolved** — cannot be silently omitted. Must be applied, or
explicitly declined with a reason in the deliverable. The escalation exists
because at tier 0 the difference between "we chose not to" and "nobody looked"
is the difference between an accepted risk and an unknown one.

**Advisory** — applied where it fits; omission needs no justification, though
the control still appears in the not-applied list with its reason.

---

## Tier-driven defaults

Where the catalog offers a range, criticality picks the point. These are
starting positions, overridable by the brief with a recorded reason.

| Dimension | Tier 0 | Tier 1 | Tier 2 |
|---|---|---|---|
| AZ spread | ≥3 AZs, static stability at N-1 | ≥2 AZs | Single AZ acceptable |
| Region posture | Multi-Region strategy required, even if not yet built | Single Region, documented recovery | Single Region |
| Database | Multi-AZ mandatory; cross-Region replica considered | Multi-AZ | Single instance acceptable |
| Deployment | Canary or blue/green with automated rollback | Rolling with health gates | Any, rollback documented |
| Change gate | Human approval to production | Automated with health checks | Automated |
| Blast radius | Cell-based partitioning evaluated and decided | Not required | Not required |

The "evaluated and decided" phrasing is deliberate. At tier 0 the obligation is
to have made the call consciously and recorded it — not necessarily to have
built cells.

---

## Interaction with exceptions

A `waived` mandatory control requires a matching `exceptions` entry on the
control record, and the exception's `requires` field must name a real
compensating control that is itself `satisfied`. A waiver naming an unsatisfied
compensating control is not a waiver — it is a `failed` control with extra
words, and the validator treats it as such.

---

## Mixed-criticality systems

Where one system spans tiers — a tier-0 payments path inside a tier-1
application — do not average. Partition the brief and record the tier per
component. Averaging produces an architecture that over-protects the cheap parts
and under-protects the expensive one, which is the worst available outcome.

If partitioning is impractical, apply the highest tier to the whole and say so
explicitly, so the cost is visible and someone can push back on it.
