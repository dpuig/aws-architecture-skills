# ZD-TOP — Topology

Fault isolation boundaries, static stability, and blast radius. Extracted
2026-08-15 from the Well-Architected Reliability Pillar (REL10, REL11), the AWS
Fault Isolation Boundaries whitepaper, Advanced Multi-AZ Resilience Patterns,
and the cell-based architecture guide.

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

⚠️ **ZD-TOP-001 and ZD-TOP-004 are referenced by name in `validate.sh` Stage 4.**
Renumbering them breaks the validator silently.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZD-TOP-001 | Workload spans multiple Availability Zones | required | Stage 4 |
| ZD-TOP-002 | Single-location components have automated recovery | required | — |
| ZD-TOP-003 | Static stability: capacity pre-provisioned for N-1 | required | — |
| ZD-TOP-004 | Auto Scaling minimum survives loss of one AZ | required | Stage 4 |
| ZD-TOP-005 | Recovery relies on the data plane, not the control plane | required | — |
| ZD-TOP-006 | Bulkheads limit scope of impact | recommended | — |
| ZD-TOP-007 | Cell-based partitioning is evaluated and decided | recommended | — |
| ZD-TOP-008 | Zonal impairment is detectable | required | — |
| ZD-TOP-009 | AZ evacuation is a rehearsed procedure | recommended | — |
| ZD-TOP-010 | Multi-Region posture is explicit | required | — |
| ZD-TOP-011 | Failover targets healthy resources automatically | required | `zd-top-011` |
| ZD-TOP-012 | An availability target is stated and architected to | required | — |

---

### ZD-TOP-001 — Workload spans multiple Availability Zones
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL10-BP01
**Applies when:** Any workload with VPC-attached compute or storage
**Authority:** SRC-AWS-FIB#abstract-and-introduction · **Check:** validator Stage 4

An Availability Zone is the smallest boundary AWS guarantees independent power,
cooling, and physical isolation across. Everything below it — a rack, a host, a
volume — shares a failure domain the workload cannot see and cannot route
around.

- Tier 0: three AZs. Tier 1: two. Tier 2: one is acceptable.
- Subnets, compute, and storage all spread; a three-AZ subnet layout with
  single-AZ compute spans nothing.
- Every AZ carries production traffic. A standby AZ that has never served a
  request is an untested AZ (see ZD-TOP-003).

**Exception:** tier 2, or a component whose state genuinely cannot be
distributed → requires ZD-TOP-002.

---

### ZD-TOP-002 — Single-location components have automated recovery
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL10-BP02
**Applies when:** Any component confined to one AZ
**Authority:** SRC-AWS-WAF-REL#REL10-BP02 · **Check:** —

Some components legitimately cannot span AZs. The obligation then shifts from
"survive the failure" to "recover from it without a human", because a recovery
that waits for someone to be paged has an RTO measured in whatever the on-call
rotation happens to be doing.

- Recovery automated and time-bounded; the bound is recorded.
- The component's data is replicated even where the compute is not.
- Recovery exercised on the ZD-DAT-005 cadence.

---

### ZD-TOP-003 — Static stability: capacity is pre-provisioned for N-1
**Tier:** required · **Criticality:** 0 · **WAF:** REL11-BP05
**Applies when:** Criticality 0
**Authority:** SRC-AWS-STATIC-STAB · **Check:** —

The discriminating control in this catalog. A system that responds to losing an
AZ by *launching replacement capacity* has made its survival depend on the EC2
control plane, at the exact moment that control plane is under the most load and
most likely to be impaired. Pre-provisioned capacity survives because it needs
nothing to happen.

- Overprovision **50% across three AZs**, so each zone runs at **66% of the
  level it was load-tested to**. Across two AZs the equivalent is 100%.
- No scaling action required in the failure path.
- Bimodal behavior is the failure to avoid: a system that behaves differently
  under failure has a mode nobody has tested.
- The EC2 data plane is itself designed this way — a running instance keeps its
  local routing information and continues to send and receive traffic through a
  control plane impairment. Architectures that depend only on the data plane
  during recovery inherit that property (ZD-TOP-005).

> The cost is real and is the point. If the tier does not justify running 50%
> spare capacity, the workload is not tier 0 — resolve that in the intake rather
> than by weakening this control.

---

### ZD-TOP-004 — Auto Scaling minimum survives loss of one Availability Zone
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL11-BP05
**Applies when:** Any Auto Scaling group in the critical path
**Authority:** SRC-AWS-WAF-REL#REL11-BP05 · **Check:** validator Stage 4

The concrete form of ZD-TOP-003 for an ASG. `min_size` below the AZ count means
losing one AZ drops the group below its own floor, and recovery then depends on
a launch succeeding.

- `min_size` ≥ number of AZs, so each AZ retains at least one instance after a
  loss.
- `desired_capacity` sized for N-1 load, not N.
- Health check grace period longer than real instance warm-up.

---

### ZD-TOP-005 — Recovery relies on the data plane, not the control plane
**Tier:** required · **Criticality:** 0 · **WAF:** REL11-BP04
**Applies when:** Criticality 0
**Authority:** SRC-AWS-WAF-REL#REL11-BP04 · **Check:** —

Control planes (creating resources, changing configuration) are more complex and
less available than data planes (routing a packet, reading an object). AWS
publishes this distinction precisely so architectures can depend on the
stronger half during an event.

- Failover shifts traffic between already-running resources.
- No resource creation, no configuration change, no API call to a control plane
  in the recovery path.
- Route 53 health checks and ALB target health are data-plane mechanisms; a
  Lambda that calls `CreateInstance` is not.

---

### ZD-TOP-006 — Bulkheads limit scope of impact
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** REL10-BP03
**Applies when:** One workload serves multiple tenants, workloads, or request classes
**Authority:** SRC-AWS-WAF-REL#REL10-BP03 · **Check:** —

Without partitioning, one poisonous request, one hot tenant, or one runaway
client consumes the capacity every other consumer depends on. The bulkhead
converts a total outage into a partial one.

- Separate connection pools, queues, or thread pools per dependency.
- Per-tenant quotas so no single tenant can exhaust shared capacity.
- Request classes isolated: a bulk export path cannot starve interactive
  traffic.

---

### ZD-TOP-007 — Cell-based partitioning is evaluated and decided
**Tier:** recommended · **Criticality:** 0 · **WAF:** REL10-BP03
**Applies when:** Criticality 0
**Authority:** SRC-AWS-CELLS · **Check:** —

The obligation is to have made the call consciously and recorded it — not
necessarily to have built cells. Cells are expensive and correct for a specific
shape of problem; adopting them reflexively is as much a failure as never
considering them.

- Decide and record: cell size, partition key, and how a tenant maps to a cell.
- Cells share nothing in the request path, including the database.
- The router is the remaining single point of failure and is designed as such.

---

### ZD-TOP-008 — Zonal impairment is detectable
**Tier:** required · **Criticality:** 0 · **WAF:** REL11-BP01
**Applies when:** Criticality 0
**Authority:** SRC-AWS-MAZ-PATTERNS#multi-az-observability · **Check:** —

Gray failure is the case this control exists for: an AZ that is degraded but not
down, where aggregate metrics look acceptable because two healthy AZs average
out the third. The workload sees elevated errors; the dashboard sees a rounding
error.

- Metrics dimensioned **per AZ**, not aggregated across them.
- Composite alarms comparing AZs against each other rather than against a fixed
  threshold.
- Both server-side and client-side signals — a fully impaired AZ may stop
  reporting rather than report badly.

---

### ZD-TOP-009 — AZ evacuation is a rehearsed procedure
**Tier:** recommended · **Criticality:** 0
**Applies when:** ZD-TOP-008 is satisfied
**Authority:** SRC-AWS-MAZ-PATTERNS#multi-az-recovery-patterns · **Check:** —

Detection without a response path produces an alarm nobody can act on.
Evacuation must be a single, rehearsed action, because it will be invoked by
whoever is on call at 3am with partial information.

- Zonal shift or an equivalent documented mechanism.
- Evacuation is data-plane only (ZD-TOP-005).
- Rehearsed on a schedule; the rehearsal is what proves ZD-TOP-003 capacity is
  actually sufficient.

---

### ZD-TOP-010 — Multi-Region posture is explicit
**Tier:** required · **Criticality:** 0 · **WAF:** REL13-BP02
**Applies when:** Criticality 0
**Authority:** SRC-AWS-MULTIREGION#fundamental-2 · **Check:** —

The obligation is a decision, not a second Region. Most tier-0 workloads
correctly run in one Region; what is not acceptable is having never decided,
because that leaves the recovery strategy undefined until the event.

- Strategy named: backup-and-restore, pilot light, warm standby, or active-active.
- The strategy's implied RTO/RPO reconciled with ZD-DAT-001's stated objectives.
- Region-level dependencies identified, including global services.
- A multi-Region architecture **is** a network partition by definition, so CAP
  forces a choice between availability and consistency. Name which was chosen.
- **Most multi-Region designs need no active-active.** Sharding the client base
  across Regions — treating Regions as cells (ZD-TOP-007) — gets most of the
  blast-radius reduction without the rewrite active-active demands: intelligent
  routing, session affinity, idempotent transactions, and conflict resolution.

⚠️ **The commonly missed requirement.** With asynchronous replication, writes
pending at the moment of failure will not have committed to the standby. A
**data reconciliation process is required**, it is specific business logic, and
**the datastore does not provide it.** A design that names a strategy but has no
reconciliation plan has an undefined RPO in practice regardless of what
ZD-DAT-001 states. Cross-check against ZD-DAT-007.

---

### ZD-TOP-011 — Failover targets healthy resources automatically
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL11-BP02
**Applies when:** Any load-balanced or replicated component
**Authority:** SRC-AWS-WAF-REL#REL11-BP02 · **Check:** `policies/opa/zd-top-011.rego`

Failover that requires a human is not failover; it is an incident response
procedure with better branding.

- Health checks configured with thresholds tuned to real recovery time.
- Cross-zone load balancing enabled so a zone losing targets does not lose its
  share of traffic.
- Unhealthy targets removed from rotation automatically, and restored
  automatically.

---

### ZD-TOP-012 — An availability target is stated and architected to
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL11-BP07
**Applies when:** Criticality 0 or 1
**Authority:** SRC-AWS-WAF-REL#REL11-BP07 · **Check:** —

An unstated availability target cannot be missed, which is why it goes unstated.
Naming it converts architecture arguments from taste into arithmetic.

- Target stated as a number, with the measurement window and what counts as
  "down".
- Dependency availability multiplies: a chain of four 99.9% dependencies yields
  99.6%, and no amount of effort on the fifth component changes that.
- Where the target and the design disagree, say so in the deliverable rather
  than resolving it silently.
