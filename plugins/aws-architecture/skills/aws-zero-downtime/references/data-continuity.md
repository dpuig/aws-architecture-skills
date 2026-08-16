# ZD-DAT — Data Continuity

Backups, replication, schema evolution, and recovery. Extracted 2026-08-15 from
the Well-Architected Reliability Pillar (REL09, REL13).

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

⚠️ **ZD-DAT-002 is referenced by name in `validate.sh` Stage 4.**

Data is where zero-downtime designs usually fail. Compute is replaceable and
stateless work is easy to move; the database is the component that cannot be
recreated from an artifact, and every control here exists because of that
asymmetry.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZD-DAT-001 | Recovery objectives are defined | required | — |
| ZD-DAT-002 | Databases are Multi-AZ | required | Stage 4 |
| ZD-DAT-003 | Backups are automated and retained | required | `zd-dat-003` |
| ZD-DAT-004 | Backups are encrypted and access-controlled | required | `zd-dat-004` |
| ZD-DAT-005 | Recovery is periodically tested | required | — |
| ZD-DAT-006 | Schema changes follow expand/contract | required | — |
| ZD-DAT-007 | Replication lag is monitored against RPO | required | — |
| ZD-DAT-008 | All data needing backup is identified | required | — |
| ZD-DAT-009 | DR configuration drift is managed | recommended | — |
| ZD-DAT-010 | Recovery is automated | recommended | — |

---

### ZD-DAT-001 — Recovery objectives are defined
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL13-BP01
**Applies when:** Any workload holding state
**Authority:** SRC-AWS-WAF-REL#REL13-BP01 · **Check:** —

RPO and RTO are the inputs every other control in this domain consumes. Without
them, "back up the database" has no frequency and "fail over" has no deadline,
so both get sized by whatever was convenient.

- RPO and RTO stated per datastore, not per workload — they legitimately differ.
- Objectives set by the business, recorded in the intake brief.
- Reconciled against ZD-TOP-010: a 5-minute RPO and a single-Region
  backup-and-restore strategy are not compatible, and the deliverable should say
  so.

---

### ZD-DAT-002 — Databases are Multi-AZ
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL10-BP01
**Applies when:** Any managed database in the critical path
**Authority:** SRC-AWS-WAF-REL#REL10-BP01 · **Check:** validator Stage 4

A single-AZ database makes the entire workload single-AZ regardless of how the
compute is spread. This is the most common way a nominally multi-AZ architecture
turns out not to be.

- RDS `multi_az = true`; Aurora clusters with instances in separate AZs.
- Failover is automatic and its expected duration is recorded against ZD-DAT-001.
- Applies to caches and search clusters holding non-reconstructible state.

---

### ZD-DAT-003 — Backups are automated and retained
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** REL09-BP03
**Applies when:** Any persistent datastore
**Authority:** SRC-AWS-WAF-REL#REL09-BP03 · **Check:** `policies/opa/zd-dat-003.rego`

Multi-AZ protects against infrastructure failure. It does not protect against a
bad migration, a mistaken `DELETE`, or a compromised credential — all of which
replicate faithfully to the standby.

- `backup_retention_period` > 0 and sized to the RPO, never left at default.
- Point-in-time recovery enabled where supported.
- AWS Backup plans for cross-service coverage.
- Retention meets the longest of business, legal, and regulatory requirements.

---

### ZD-DAT-004 — Backups are encrypted and access-controlled
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL09-BP02
**Applies when:** Any backup exists
**Authority:** SRC-AWS-WAF-REL#REL09-BP02 · **Check:** `policies/opa/zd-dat-004.rego`

A backup is a complete copy of production data with weaker access controls and
less monitoring. Cross-references ZT-DAT-002, which is where the encryption
requirement is stated in full.

- Snapshots and backup vaults encrypted (see ZT-DAT-002).
- Backup deletion requires elevated permission; vault lock where the retention
  is regulatory.
- Copies held in an account the production workload cannot write to — a
  credential that can delete the backups protects against nothing.

---

### ZD-DAT-005 — Recovery is periodically tested
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL09-BP04, REL13-BP03
**Applies when:** Criticality 0 or 1
**Authority:** SRC-AWS-WAF-REL#REL09-BP04 · **Check:** —

An untested backup is a hypothesis, and the failure modes are silent by
construction: a backup that has been failing for months looks exactly like one
that has been succeeding until someone tries to restore it.

- Restore exercised on a defined cadence, into a real environment.
- The test measures actual RTO and compares it to the ZD-DAT-001 objective.
- Failures treated as incidents.

---

### ZD-DAT-006 — Schema changes follow expand/contract
**Tier:** required · **Criticality:** 0,1
**Applies when:** Any relational schema changes while the workload runs
**Authority:** SRC-FOWLER-EVODB · **Check:** —

This is what makes ZD-DEP-011 possible for stateful workloads. A schema change
deployed atomically with the code that needs it requires both to switch at the
same instant — which requires downtime, or a version skew nobody has tested.

Three deployments, never fewer:

1. **Expand** — add the new column or table, nullable or defaulted. Old code
   ignores it.
2. **Migrate** — deploy code writing both old and new; backfill.
3. **Contract** — once no running code reads the old shape, remove it.

- Each phase deploys independently and is individually reversible.
- No phase requires a specific code version to already be running everywhere.
- Contract is a separate release, days or weeks later — not the same afternoon.

> This is also what makes ZD-DEP-002's rollback path real. A migration that
> dropped a column cannot be rolled back by redeploying the previous artifact.

**Authority note:** SRC-FOWLER-EVODB is third-party. AWS publishes no
equivalent, so this control — one of the most load-bearing in the catalog —
rests on an external source. Worth knowing when assessing defensibility.

---

### ZD-DAT-007 — Replication lag is monitored against RPO
**Tier:** required · **Criticality:** 0 · **WAF:** REL11-BP01
**Applies when:** Any asynchronous replication is in the recovery path
**Authority:** SRC-AWS-WAF-REL#REL11-BP01 · **Check:** —

RPO is not a property of the replication technology; it is a property of the
replication lag at the moment of failure. Unmonitored lag means the RPO is
whatever it happened to be, discovered afterwards.

- Replica lag alarmed at a threshold below the stated RPO, leaving time to act.
- Cross-Region lag measured separately from in-Region.
- Sustained breach treated as an RPO violation in progress, not a performance
  issue.

---

### ZD-DAT-008 — All data needing backup is identified
**Tier:** required · **Criticality:** 0,1 · **WAF:** REL09-BP01
**Applies when:** Any workload holding state
**Authority:** SRC-AWS-WAF-REL#REL09-BP01 · **Check:** —

The data that gets missed is never the primary database. It is the S3 bucket
holding uploads, the parameter store holding configuration, the secret nobody
can regenerate, or the queue that turns out not to be transient.

- Inventory every stateful resource and classify it: backed up, reproducible
  from source, or acceptably lost.
- "Reproducible" must name the source and the procedure.
- Reviewed when the architecture changes, since new stores arrive unclassified.

---

### ZD-DAT-009 — DR configuration drift is managed
**Tier:** recommended · **Criticality:** 0 · **WAF:** REL13-BP04
**Applies when:** A DR Region or site exists
**Authority:** SRC-AWS-WAF-REL#REL13-BP04 · **Check:** —

A DR environment that diverges from production fails during the only event it
exists for. Drift accumulates silently because nothing exercises the DR site.

- Same IaC deploys both; the difference is parameters, not code.
- Drift detection on the DR stack.
- Quotas and limits verified in the DR Region — they are per-Region, and a
  failover into an account with default quotas fails at exactly the wrong time.

---

### ZD-DAT-010 — Recovery is automated
**Tier:** recommended · **Criticality:** 0 · **WAF:** REL13-BP05
**Applies when:** Criticality 0
**Authority:** SRC-AWS-WAF-REL#REL13-BP05 · **Check:** —

- Recovery steps scripted and rehearsed, not documented and hoped for.
- The trigger is explicit: who or what decides to fail over, and on what signal.
- Automation itself tested, since untested automation is a second untested
  system in the recovery path.
