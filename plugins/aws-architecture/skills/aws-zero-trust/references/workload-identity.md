# ZT-WLD — Workload Identity

Machine identity: how code proves who it is without a shared secret. Extracted
2026-08-15 from SRC-AWS-IAM-BP (workload credentials section) and SEC02.

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone.

Human identity is `identity.md` (ZT-IDN). The distinction matters: humans can be
asked to re-authenticate, machines cannot, so the controls diverge.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZT-WLD-001 | AWS-hosted workloads use instance or task roles | required | `zt-wld-001` |
| ZT-WLD-002 | External workloads use certificate-based federation | required | — |
| ZT-WLD-003 | CI/CD authenticates via OIDC, not stored keys | required | — |
| ZT-WLD-004 | Each workload has its own identity | required | — |
| ZT-WLD-005 | Secrets are stored in a managed secret store | required | `zt-wld-005` |
| ZT-WLD-006 | Service-to-service calls are mutually authenticated | recommended | — |
| ZT-WLD-007 | Workload credentials are short-lived | required | — |
| ZT-WLD-008 | Container workloads use per-pod, not per-node, identity | required | — |

---

### ZT-WLD-001 — AWS-hosted workloads use instance or task roles
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC02-BP02
**Applies when:** Any compute running on EC2, ECS, EKS, or Lambda
**Authority:** SRC-AWS-IAM-BP#bp-workloads-use-roles · **Check:** `policies/opa/zt-wld-001.rego`

AWS delivers temporary credentials to the compute resource directly; the SDK
discovers them without configuration. Distributing a long-lived key to a
workload running *on AWS* is therefore never a technical necessity — it is a
shortcut, and the credential it creates has no expiry.

- EC2 instance profiles, ECS task roles, Lambda execution roles, EKS Pod
  Identity or IRSA.
- No `AWS_ACCESS_KEY_ID` in environment variables, user data, task definitions,
  or container images.

---

### ZT-WLD-002 — External workloads use certificate-based federation
**Tier:** required · **Criticality:** 0,1
**Applies when:** Workloads outside AWS need AWS API access
**Authority:** SRC-AWS-IAM-BP#bp-workloads-use-roles · **Check:** —

AWS enumerates four mechanisms for delivering temporary credentials off-platform
— Roles Anywhere with X.509, `AssumeRoleWithSAML`, `AssumeRoleWithWebIdentity`,
and IoT Core mTLS. The existence of four options means "we had to use a static
key" needs to survive the question of why none of them fit.

- IAM Roles Anywhere with certificates from the corporate PKI.
- Trust anchor scoped to a specific CA; profiles scoped to specific roles.
- Certificate revocation path tested, not assumed.

---

### ZT-WLD-003 — CI/CD authenticates via OIDC, not stored keys
**Tier:** required · **Criticality:** 0,1
**Applies when:** A pipeline outside AWS deploys into AWS
**Authority:** SRC-AWS-IAM-BP#bp-workloads-use-roles · **Check:** —

A CI system holding deployment credentials is the highest-value credential store
in most organizations, and it is usually the least monitored. OIDC federation
removes the stored secret entirely.

- `AssumeRoleWithWebIdentity` against the CI provider's OIDC issuer.
- Trust policy conditions pin the repository *and* the branch or environment —
  issuer alone lets any repo in the org assume the role.
- Deployment role separate from, and more constrained than, the build role.

---

### ZT-WLD-004 — Each workload has its own identity
**Tier:** required · **Criticality:** 0,1
**Applies when:** More than one workload runs in an account
**Authority:** SRC-AWS-IAM-BP#grant-least-privilege · **Check:** —

A role shared between workloads is the union of their permissions, granted to
each. It also destroys attribution: CloudTrail shows the role, so after an
incident nobody can say which workload made the call.

- One role per workload, per environment.
- Role names encode workload and environment.
- No "application" or "shared-services" catch-all role.

---

### ZT-WLD-005 — Secrets are stored in a managed secret store
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC02-BP03
**Applies when:** The workload needs any credential it cannot obtain from a role
**Authority:** SRC-AWS-WAF-SEC#SEC02-BP03 · **Check:** `policies/opa/zt-wld-005.rego`

Some secrets are irreducible — a third-party API key has no AWS role to assume.
The control is not "have no secrets" but "have no secrets in places that get
copied": repositories, images, environment blocks, and Terraform state.

- Secrets Manager or SSM Parameter Store (SecureString), retrieved at runtime.
- Rotation configured where the provider supports it.
- No plaintext secret in Terraform, task definitions, or user data — note that
  a value in Terraform is also a value in state.

---

### ZT-WLD-006 — Service-to-service calls are mutually authenticated
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC09-BP03
**Applies when:** Services call each other across a trust boundary
**Authority:** SRC-AWS-WAF-SEC#SEC09-BP03 · **Check:** —

One-way TLS proves the server's identity to the client and nothing about the
client. Without mutual authentication the callee's authorization decision rests
on network position — the exact inheritance Zero Trust rejects.

- VPC Lattice auth policies with SigV4 (see ZT-NET-008), or mTLS via Private CA.
- SPIFFE identifiers where a service mesh is in use.
- Client identity used in the authorization decision, not merely logged.

---

### ZT-WLD-007 — Workload credentials are short-lived
**Tier:** required · **Criticality:** 0,1
**Applies when:** Any workload identity is issued
**Authority:** SRC-AWS-IAM-BP#bp-workloads-use-roles · **Check:** —

Credential lifetime is the window an attacker gets from a single theft. It is
one of the few security parameters that is a pure dial, with a real cost only
when set absurdly low.

- Default session duration; extend only with a recorded reason.
- No credential caching beyond the SDK's own refresh.
- Long-running processes refresh rather than holding a credential for their
  lifetime.

---

### ZT-WLD-008 — Container workloads use per-pod, not per-node, identity
**Tier:** required · **Criticality:** 0,1
**Applies when:** EKS or ECS with multiple workloads per host
**Authority:** SRC-AWS-IAM-BP#bp-workloads-use-roles · **Check:** —

Node-level identity grants every pod on the host the union of what any pod
needs. On a shared node that is a lateral movement path that requires no
exploit — just scheduling.

- EKS Pod Identity or IRSA; ECS task roles rather than instance profiles.
- Node role limited to what the kubelet itself requires.
- IMDS access from containers blocked or hop-limited so pods cannot reach the
  node role.
