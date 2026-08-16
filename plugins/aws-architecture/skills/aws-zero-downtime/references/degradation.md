# ZD-DEG — Degradation

Behaving well under stress: draining, timeouts, retries, throttling, and
graceful degradation. Extracted 2026-08-15 from the Well-Architected Reliability
Pillar (REL05) and the ALB target group documentation.

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

⚠️ **ZD-DEG-001 is referenced by name in `validate.sh` Stage 4.**

Where ZD-TOP contains failures and ZD-DEP avoids causing them, this domain
governs the minutes when the system is under stress and has not yet failed —
the window in which most self-inflicted outages are actually made.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZD-DEG-001 | Target groups declare draining and health thresholds | required | Stage 4 |
| ZD-DEG-002 | Client timeouts are set | required | — |
| ZD-DEG-003 | Retries are limited and use backoff with jitter | required | — |
| ZD-DEG-004 | Requests are throttled | required | — |
| ZD-DEG-005 | Hard dependencies are made soft where possible | recommended | — |
| ZD-DEG-006 | Fail fast; queues are bounded | required | — |
| ZD-DEG-007 | Services are stateless where possible | recommended | — |
| ZD-DEG-008 | Emergency levers exist | recommended | — |
| ZD-DEG-009 | Zonal brownout is bounded by health thresholds | recommended | `zd-deg-009` |
| ZD-DEG-010 | Slow start is enabled for warm-up-sensitive targets | contextual | — |

---

### ZD-DEG-001 — Target groups declare draining and health thresholds
**Tier:** required · **Criticality:** 0,1,2
**Applies when:** Any load-balanced target group
**Authority:** SRC-AWS-ALB-TG#target-group-attributes · **Check:** validator Stage 4

Deregistration without draining terminates in-flight requests, which turns every
routine scale-in and every deployment into a small number of user-visible
errors. The default `deregistration_delay.timeout_seconds` is 300 seconds —
correct for long-lived connections and needlessly slow for short HTTP requests,
which is why it must be set deliberately rather than inherited.

- `deregistration_delay` set explicitly, sized to the p99 request duration
  rather than left at 300.
- `healthy_threshold` and `unhealthy_threshold` set; defaults are rarely right
  for both fast detection and stability.
- Health check path exercises a real dependency, not a static 200.

---

### ZD-DEG-002 — Client timeouts are set
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL05-BP05
**Applies when:** Any call to a remote dependency
**Authority:** SRC-AWS-WAF-REL#REL05-BP05 · **Check:** —

A call with no timeout is a thread held until the operating system gives up,
which can be minutes. Under load, this is how a slow dependency becomes a total
outage: every worker ends up parked on the same call.

- Connect and request timeouts set explicitly on every client. SDK defaults are
  often far longer than the caller's own deadline.
- Timeout budget decreases down the call chain, so an inner call cannot outlive
  the outer request that needs it.
- Timeouts derived from the dependency's p99, not chosen as round numbers.

---

### ZD-DEG-003 — Retries are limited and use backoff with jitter
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL05-BP03
**Applies when:** Any retry logic exists
**Authority:** SRC-AWS-RETRIES · **Check:** —

Retries convert a brief dependency failure into a sustained load multiplier
exactly when the dependency is least able to absorb it. Synchronized retries are
worse — without jitter, every client retries at the same instant, producing a
thundering herd that prevents the recovery it is waiting for.

- Bounded attempt count; no unbounded retry loops.
- Exponential backoff **with jitter** — jitter is the part usually omitted and
  the part that matters most.
- Retries only on transient errors; never on a 4xx.
- Retry budget across the call chain — three layers each retrying three times is
  27 requests, not three.

---

### ZD-DEG-004 — Requests are throttled
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL05-BP02
**Applies when:** Any workload accepting external requests
**Authority:** SRC-AWS-WAF-REL#REL05-BP02 · **Check:** —

Accepting more work than the system can complete does not serve more users; it
serves all of them slowly, then fails all of them at once. Rejecting excess
early keeps the accepted portion healthy.

- Per-client rate limits at the edge (API Gateway, WAF rate rules).
- 429 with `Retry-After`, so well-behaved clients back off correctly.
- Limits sized from measured capacity, not guessed.

---

### ZD-DEG-005 — Hard dependencies are made soft where possible
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** REL05-BP01
**Applies when:** The workload calls dependencies that can fail independently
**Authority:** SRC-AWS-WAF-REL#REL05-BP01 · **Check:** —

Every hard dependency multiplies into the availability target from ZD-TOP-012.
Converting one to soft removes it from that product entirely.

- Identify which dependencies are genuinely required to serve a request and
  which merely enrich it.
- Cached or stale data preferred over an error where correctness permits.
- Degraded responses are explicit and observable — silent degradation is
  indistinguishable from a bug.

---

### ZD-DEG-006 — Fail fast; queues are bounded
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL05-BP04
**Applies when:** Any queue or buffer exists in the request path
**Authority:** SRC-AWS-WAF-REL#REL05-BP04 · **Check:** —

An unbounded queue converts an overload into a latency spiral: work is accepted,
queued, and completed after the client has already given up and retried. The
system is fully busy producing results nobody is waiting for.

- Queues bounded; rejection on full rather than unbounded growth.
- Requests whose deadline has passed are dropped rather than processed.
- Circuit breakers on repeatedly failing dependencies so calls fail immediately
  instead of consuming a timeout each.

---

### ZD-DEG-007 — Services are stateless where possible
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** REL05-BP06
**Applies when:** Any horizontally scaled compute
**Authority:** SRC-AWS-WAF-REL#REL05-BP06 · **Check:** —

Statelessness is what makes an instance disposable, and disposability is the
precondition for ZD-DEP-003, ZD-TOP-004, and every scale-in event.

- Session state in a shared store, not on the instance.
- No sticky sessions unless a specific requirement forces them — stickiness
  reintroduces the coupling this control removes.
- Any instance can serve any request.

---

### ZD-DEG-008 — Emergency levers exist
**Tier:** recommended · **Criticality:** 0 · **WAF:** REL05-BP07
**Applies when:** Criticality 0
**Authority:** SRC-AWS-WAF-REL#REL05-BP07 · **Check:** —

During an incident the useful actions are the ones already built. A lever
designed under pressure is a change deployed without review into a system
already failing.

- Pre-built switches: shed non-essential load, disable expensive features,
  serve cached content.
- Levers are data-plane operations (ZD-TOP-005) and take effect in seconds.
- Tested, and their side effects documented — a lever nobody has pulled is an
  untested code path in the recovery position.

---

### ZD-DEG-009 — Zonal brownout is bounded by health thresholds
**Tier:** recommended · **Criticality:** 0
**Applies when:** An ALB serves criticality-0 traffic across multiple AZs
**Authority:** SRC-AWS-ALB-TG#target-group-health · **Check:** `policies/opa/zd-deg-009.rego`

By default a target group is considered healthy while it has **one** healthy
target. For a large fleet that is not availability — it is one instance
absorbing the load of an entire zone, and failing.

- `target_group_health.dns_failover.minimum_healthy_targets.percentage` set, so
  a degraded zone is removed from DNS rather than kept in rotation.
- `target_group_health.unhealthy_state_routing.*` set, so that below the
  threshold traffic goes to all targets rather than overwhelming the survivors.
- DNS failover threshold ≥ routing failover threshold, per AWS's stated
  requirement.
- Requires ZD-TOP-003 capacity in the remaining zones to absorb the shift.

---

### ZD-DEG-010 — Slow start is enabled for warm-up-sensitive targets
**Tier:** contextual · **Criticality:** 0,1
**Applies when:** Targets need warm-up — JIT runtimes, cold caches, connection pools
**Authority:** SRC-AWS-ALB-TG#target-group-attributes · **Check:** —

`slow_start.duration_seconds` defaults to 0, meaning a newly registered target
receives its full share of traffic immediately. For a JVM or a service with a
cold cache, that is a burst of slow requests and often a failed health check
during a scale-out — which triggers another scale-out.

- `slow_start.duration_seconds` in the 30–900 range where warm-up is real.
- Not a substitute for a health check that reflects actual readiness.
- Contextual by design: enabling it for a target that needs no warm-up merely
  slows recovery.
