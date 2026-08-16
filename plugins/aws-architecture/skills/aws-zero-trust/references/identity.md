# ZT-IDN — Identity

Human identity, federation, and permissions management. Extracted 2026-08-15
from SRC-AWS-IAM-BP and the Well-Architected Security Pillar (SEC02, SEC03).

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

Machine and workload identity live in `workload-identity.md` (ZT-WLD), not here.
The split is deliberate: the controls differ, and mixing them produces guidance
that is wrong for both.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZT-IDN-001 | Human access uses federated temporary credentials | required | — |
| ZT-IDN-002 | A centralized identity provider is authoritative | required | — |
| ZT-IDN-003 | Phishing-resistant MFA where IAM users remain | required | — |
| ZT-IDN-004 | Root user credentials are protected and unused | required | — |
| ZT-IDN-005 | No long-term access keys without a recorded use case | required | `zt-idn-005` |
| ZT-IDN-006 | Policies grant least privilege | required | `zt-idn-006` |
| ZT-IDN-007 | Permissions are reduced continuously | recommended | — |
| ZT-IDN-008 | Policy conditions constrain access further | recommended | — |
| ZT-IDN-009 | Public and cross-account access is analyzed | required | — |
| ZT-IDN-010 | Organization-wide permission guardrails exist | required | — |
| ZT-IDN-011 | Permissions boundaries delegate safely | recommended | — |
| ZT-IDN-012 | An emergency access path is defined and tested | required | — |
| ZT-IDN-013 | Access follows identity lifecycle | required | — |

---

### ZT-IDN-001 — Human access uses federated temporary credentials
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC02-BP02, SEC02-BP04
**Applies when:** Any workload with human operators or administrators
**Authority:** SRC-AWS-IAM-BP#bp-users-federation-idp · **Check:** —

A long-lived credential is a standing grant that survives the departure of the
person it was issued to, the compromise of the laptop it sat on, and the
deletion of the ticket that justified it. Temporary credentials expire whether
or not anyone remembers to revoke them — which is the only revocation mechanism
that works reliably at scale.

- Human access via IAM Identity Center or an external IdP assuming roles.
- No IAM users for workforce access.
- Session duration scoped to the task, not the working day.

---

### ZT-IDN-002 — A centralized identity provider is authoritative
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC02-BP04
**Applies when:** More than one AWS account, or any workforce access
**Authority:** SRC-AWS-IAM-BP#bp-users-federation-idp · **Check:** —

Identity scattered across accounts cannot be revoked in one action, which means
offboarding is best-effort. Centralization is what converts "we removed their
access" from an assertion into a fact.

- IAM Identity Center as the access plane, backed by the corporate IdP.
- Group membership in the IdP drives AWS permission sets.
- Account-local IAM users exist only for the exceptions in ZT-IDN-005.

---

### ZT-IDN-003 — Phishing-resistant MFA where IAM users remain
**Tier:** required · **Criticality:** 0,1,2
**Applies when:** Any IAM user or root user exists
**Authority:** SRC-AWS-IAM-BP#enable-mfa-for-privileged-users · **Check:** —

MFA that can be relayed to an attacker in real time stops opportunistic attacks
and not targeted ones. Passkeys and security keys bind the authentication to the
origin, which is what defeats relay.

- Passkeys or FIDO security keys wherever supported.
- TOTP only where hardware is genuinely unavailable, recorded as an exception.
- MFA enforced on the root user without exception.

---

### ZT-IDN-004 — Root user credentials are protected and unused
**Tier:** required · **Criticality:** 0,1,2
**Applies when:** Any AWS account
**Authority:** SRC-AWS-IAM-BP#lock-away-credentials · **Check:** —

The root user cannot be constrained by SCPs, permissions boundaries, or IAM
policy. It is the one principal for which every other control in this catalog is
inert — so the control has to be on its use, not on its permissions.

- No root access keys.
- MFA enabled; credentials held under break-glass custody.
- Root sign-in alerting wired to ZT-TEL-003.
- Routine work never uses root.

---

### ZT-IDN-005 — No long-term access keys without a recorded use case
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC02-BP02
**Applies when:** Any IAM user is defined
**Authority:** SRC-AWS-IAM-BP#update-access-keys · **Check:** `policies/opa/zt-idn-005.rego`

AWS documents the legitimate exceptions — workloads that cannot assume roles,
third-party clients without Identity Center support, CodeCommit, Keyspaces.
Those are narrow and enumerable. Anything outside them is an access key created
because it was easier, and it will outlive its purpose.

- `aws_iam_access_key` resources require a recorded justification.
- Keys rotated on personnel change, using last-used data to rotate safely.
- Prefer ZT-WLD-002 (IAM Roles Anywhere) before concluding a key is required.

**Exception:** one of the AWS-documented cases above → requires the specific
case named in the resource's tags and a rotation owner.

---

### ZT-IDN-006 — Policies grant least privilege
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC03-BP02
**Applies when:** Any IAM policy is authored
**Authority:** SRC-AWS-IAM-BP#grant-least-privilege · **Check:** `policies/opa/zt-idn-006.rego`

`Action: "*"` on `Resource: "*"` is not a permission grant, it is the absence of
one. The check here is deliberately crude — wildcard action *and* wildcard
resource in the same allow statement — because that pattern is unambiguous and
catching it early is worth more than a sophisticated analysis nobody runs.

- Customer-managed policies scoped to specific actions and resource ARNs.
- AWS-managed policies are a starting point, not a destination.
- Use Access Analyzer policy generation from CloudTrail activity to tighten.

---

### ZT-IDN-007 — Permissions are reduced continuously
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC03-BP04
**Applies when:** Any workload in production for more than one quarter
**Authority:** SRC-AWS-IAM-BP#remove-credentials · **Check:** —

Permissions granted during development are sized for exploration. Nothing
removes them later unless something is designed to.

- Review last-accessed data on a defined cadence.
- Remove unused users, roles, policies, and credentials.
- Access Analyzer unused-access findings routed to an owner.

---

### ZT-IDN-008 — Policy conditions constrain access further
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC03-BP02
**Applies when:** Policies grant access to sensitive actions or resources
**Authority:** SRC-AWS-IAM-BP#use-policy-conditions · **Check:** —

Conditions are where per-request context enters the authorization decision —
which is the Zero Trust premise expressed in IAM's own vocabulary.

- `aws:SecureTransport` required on data-plane access.
- `aws:PrincipalOrgID` on resource policies to bound cross-account reach.
- `aws:SourceVpce` or `aws:SourceVpc` where access should be endpoint-only.

---

### ZT-IDN-009 — Public and cross-account access is analyzed
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC03-BP07
**Applies when:** Any resource policy grants access outside the account
**Authority:** SRC-AWS-IAM-BP#bp-preview-access · **Check:** validator Stage 3

Resource policies fail open in a way identity policies do not: a bucket policy
naming the wrong principal is silently world-readable. Access Analyzer is the
AWS-native gate that catches it before deployment.

- Access Analyzer `CheckNoPublicAccess` on resource policies in the plan.
- `CheckAccessNotGranted` asserting sensitive actions are absent.
- `CheckNoNewAccess` diffing against a reference baseline on change.

---

### ZT-IDN-010 — Organization-wide permission guardrails exist
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC03-BP05
**Applies when:** `account_model` is multi-account
**Authority:** SRC-AWS-IAM-BP#bp-permissions-guardrails · **Check:** —

SCPs and RCPs bound what any principal in an account can do, including
principals created later by people who never read this catalog. They are the
only control here that constrains the future.

- SCPs limiting principals; RCPs limiting access to resources.
- Guardrails deny the actions no workload in the OU should ever take.
- Neither grants permission — identity and resource policies still required.

---

### ZT-IDN-011 — Permissions boundaries delegate safely
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC03-BP05
**Applies when:** Developers may create IAM roles
**Authority:** SRC-AWS-IAM-BP#bp-permissions-boundaries · **Check:** —

Without a boundary, delegating role creation delegates privilege escalation: a
developer who can create a role can create an administrative one.

- Boundary policy attached to every role a delegated principal may create.
- The delegating policy requires the boundary via a condition.

---

### ZT-IDN-012 — An emergency access path is defined and tested
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC03-BP03
**Applies when:** Criticality 0 or 1
**Authority:** SRC-AWS-WAF-SEC#SEC03-BP03 · **Check:** —

Federation depends on the IdP. When the IdP is the thing that is down, an
untested break-glass path is discovered during the incident, which is the worst
possible time to find out it does not work.

- Break-glass role independent of the primary IdP.
- Use is alerted, time-bound, and reviewed after the fact.
- Path exercised on a schedule, not assumed.

---

### ZT-IDN-013 — Access follows identity lifecycle
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC03-BP06
**Applies when:** Any workforce or third-party human access
**Authority:** SRC-AWS-WAF-SEC#SEC03-BP06 · **Check:** —

Joiner-mover-leaver handling is where centralized identity pays off. Access that
does not change when the person's role changes accumulates into exactly the
standing privilege ZT-IDN-001 was meant to prevent.

- Provisioning and deprovisioning driven from the IdP, not from AWS.
- Role changes revoke prior permission sets rather than adding to them.
- Third-party access carries an expiry date.
