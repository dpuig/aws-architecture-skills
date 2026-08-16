# ZT-DAT — Data Protection

Classification, encryption at rest and in transit, and key management. Extracted
2026-08-15 from the Well-Architected Security Pillar (SEC07, SEC08, SEC09).

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZT-DAT-001 | Data is classified before it is stored | required | — |
| ZT-DAT-002 | Encryption at rest is enforced, not merely enabled | required | `zt-dat-002` |
| ZT-DAT-003 | Key management is deliberate | required | — |
| ZT-DAT-004 | Key usage is audited | recommended | — |
| ZT-DAT-005 | Access control is enforced at the resource | required | `zt-dat-005` |
| ZT-DAT-006 | Encryption in transit is enforced | required | `zt-dat-006` |
| ZT-DAT-007 | Certificates are centrally managed | required | — |
| ZT-DAT-008 | Data-at-rest protection is automated | recommended | — |
| ZT-DAT-009 | Regulated data is tokenized or masked where possible | contextual | — |

---

### ZT-DAT-001 — Data is classified before it is stored
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC07
**Applies when:** Any workload persisting data
**Authority:** SRC-AWS-WAF-SEC#data-classification · **Check:** —

Classification is the input every other data control consumes. Without it,
"encrypt sensitive data" has no subject, and the decision gets made
per-resource by whoever wrote that resource.

- Classification recorded as a resource tag at creation.
- Tag values drawn from a fixed set matching the intake schema's
  `data_classification`.
- Untagged datastores treated as the highest classification present in the
  workload until corrected.

---

### ZT-DAT-002 — Encryption at rest is enforced, not merely enabled
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC08-BP02
**Applies when:** Any persistent storage
**Authority:** SRC-AWS-WAF-SEC#SEC08-BP02 · **Check:** `policies/opa/zt-dat-002.rego`

The distinction in the title is the whole control. Enabling encryption on the
resources you remember is a property of today's architecture; enforcing it
through policy is a property of every resource anyone creates later.

- `encrypted`/`storage_encrypted`/`server_side_encryption_configuration` set on
  every persistent store.
- SCP or RCP denying creation of unencrypted resources where the account model
  supports it (ZT-IDN-010).
- Applies to backups and snapshots, which are commonly missed.

---

### ZT-DAT-003 — Key management is deliberate
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC08-BP01
**Applies when:** Data classification is confidential, internal-pii, or regulated
**Authority:** SRC-AWS-WAF-SEC#SEC08-BP01 · **Check:** —

AWS-managed keys are a reasonable default and a poor answer to "who can decrypt
this." A customer-managed key has a key policy, which is where that question
gets an auditable answer.

- Customer-managed KMS keys for classified data; AWS-managed acceptable below.
- Key policy names the principals that may use and administer the key, and they
  are different principals.
- Key rotation enabled.
- Key scope matched to blast radius — one key per workload and environment, not
  one per account.

---

### ZT-DAT-004 — Key usage is audited
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC08-BP01
**Applies when:** Customer-managed keys are in use
**Authority:** SRC-AWS-WAF-SEC#protecting-data-at-rest · **Check:** —

Every use of a KMS key is logged in CloudTrail. That is only useful if something
reads it: an access control you never verify is an assumption.

- CloudTrail `kms:Decrypt` activity queried on a cadence.
- Alert on decrypt calls from unexpected principals or regions.
- Findings routed per ZT-TEL-003.

---

### ZT-DAT-005 — Access control is enforced at the resource
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC08-BP04
**Applies when:** Any datastore reachable by more than one principal
**Authority:** SRC-AWS-WAF-SEC#SEC08-BP04 · **Check:** `policies/opa/zt-dat-005.rego`

Encryption protects data from someone who bypasses the access path. It does
nothing about a principal who is authorized and should not be — which is the
more common case.

- S3 Block Public Access at account and bucket level.
- Bucket and resource policies scoped by `aws:PrincipalOrgID`.
- No `Principal: "*"` in a resource policy without an explicit condition.

---

### ZT-DAT-006 — Encryption in transit is enforced
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC09-BP02
**Applies when:** Any data crosses a network boundary
**Authority:** SRC-AWS-WAF-SEC#SEC09-BP02 · **Check:** `policies/opa/zt-dat-006.rego`

"Internal traffic is trusted" is the assumption Zero Trust exists to remove.
Traffic between two subnets of the same VPC crosses infrastructure the workload
does not control.

- No plaintext HTTP listeners; redirect at the edge, do not serve.
- TLS 1.2 minimum; modern ALB/NLB security policy.
- `aws:SecureTransport` condition denying non-TLS access to S3 and other
  data-plane endpoints.
- PrivateLink for cross-VPC and on-premises service access so traffic stays on
  the AWS backbone.

---

### ZT-DAT-007 — Certificates are centrally managed
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC09-BP01
**Applies when:** Any TLS endpoint is terminated
**Authority:** SRC-AWS-WAF-SEC#SEC09-BP01 · **Check:** —

Certificate expiry is a scheduled outage that arrives without a change ticket.
Managed issuance and renewal is the only reliable defense, because the failure
mode of manual renewal is silence until the deadline.

- ACM for public endpoints, with automatic renewal.
- AWS Private CA for internal and mTLS certificates.
- No manually uploaded certificates without a named renewal owner.

---

### ZT-DAT-008 — Data-at-rest protection is automated
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC08-BP03
**Applies when:** Criticality 0 or 1
**Authority:** SRC-AWS-WAF-SEC#SEC08-BP03 · **Check:** —

Detection of unencrypted or over-exposed storage should not depend on someone
looking.

- AWS Config rules for encryption and public-access posture.
- Macie for discovery of sensitive data in S3 where classification is uncertain.
- Non-compliant resources trigger remediation per ZT-TEL-004.

---

### ZT-DAT-009 — Regulated data is tokenized or masked where possible
**Tier:** contextual · **Criticality:** 0 · **WAF:** SEC07
**Applies when:** `compliance_regimes` includes PCI-DSS or equivalent
**Authority:** SRC-AWS-WAF-SEC#protecting-data-at-rest · **Check:** —

Tokenization reduces compliance scope rather than merely protecting data within
it — a different and usually cheaper outcome than encrypting everything and
auditing the whole estate.

- Tokens carry no derivation from the source value; a cryptographic digest is
  not a token.
- Masking retains only what downstream systems genuinely need — PCI-DSS permits
  the last four digits outside the scope boundary for indexing.
- Scope boundary documented, since that is the artifact an assessor reads.
