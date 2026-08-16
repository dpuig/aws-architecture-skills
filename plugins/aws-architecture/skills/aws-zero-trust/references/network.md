# ZT-NET — Network

Segmentation, ingress and egress authorization, and service-to-service
reachability. Extracted 2026-08-15 from SRC-AWS-WAF-SEC (SEC05), SRC-AWS-LATTICE,
SRC-AWS-MULTIVPC, and SRC-AWS-VERIFIED-ACCESS.

**Catalog version: see `/CATALOG_VERSION` — pre-review.** No control in this file has `kb_source`
set; all are grounded on `authority` alone. See SKILL.md § Catalog status.

## Contents

| ID | Title | Tier | Check |
|---|---|---|---|
| ZT-NET-001 | Network layers defined by trust boundary | required | — |
| ZT-NET-002 | IP space centrally allocated and non-overlapping | required | — |
| ZT-NET-003 | Internet egress centralized and inspected | required | `zt-net-003` |
| ZT-NET-004 | Traffic between layers explicitly authorized | required | — |
| ZT-NET-005 | Reachability requires service network association | recommended | — |
| ZT-NET-006 | Security groups on VPC–service network association | recommended | — |
| ZT-NET-007 | Service networks carry a coarse auth policy | recommended | — |
| ZT-NET-008 | Services carry a fine-grained auth policy | recommended | — |
| ZT-NET-009 | Application access evaluated per request | required | — |
| ZT-NET-010 | AWS service access via VPC endpoints | required | — |
| ZT-NET-012 | Inspection-based protection in the traffic path | recommended | — |
| ZT-NET-013 | Network protection applied by automation | required | — |
| ZT-NET-014 | Private-tier subnets deny unrestricted ingress | required | `zt-net-014` |
| ZT-NET-015 | Subnets do not auto-assign public IPs | required | `zt-net-015` |
| ZT-NET-016 | Every security group rule carries a description | recommended | `zt-net-016` |
| ZT-NET-021 | Non-HTTP public exposure is firewall-inspected | required | — |

*ZT-NET-011 reserved — private DNS resolution, source not yet ingested.*

---

### ZT-NET-001 — Network layers are defined by trust boundary, not by convenience
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC05-BP01
**Applies when:** Any workload deploying VPC-attached resources
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP01 · **Check:** — · **Module:** `modules/network/private-tier/`

Grouping resources by shared sensitivity and reachability is what makes every
later control expressible. Without layers there is no "private tier" for a rule
to refer to, and segmentation degrades into per-resource exceptions nobody can
audit.

- Subnets grouped into named tiers (edge / application / data), with tier
  recorded as a resource tag rather than inferred from CIDR or subnet name.
- Each tier has a distinct route table; data-tier route tables have no route to
  an internet gateway.
- Resources inherit tier from subnet placement; no resource spans tiers.

---

### ZT-NET-002 — IP address space is centrally allocated and non-overlapping
**Tier:** required · **Criticality:** 0,1
**Applies when:** Any multi-VPC or multi-account deployment
**Authority:** SRC-AWS-MULTIVPC#ip-address-planning-and-management · **Check:** —

Overlapping CIDRs foreclose future connectivity options and force NAT
workarounds that obscure traffic origin — which in turn defeats identity-based
ingress rules that depend on knowing the true source. The cost is paid years
after the mistake, by a different team.

- CIDRs allocated from an Amazon VPC IPAM pool, not hand-picked.
- Distinct ranges reserved for on-premises versus cloud.
- Hierarchical allocation by Region and business unit to permit summarization.

**Exception:** isolated or disconnected workload with no current or planned
peering → requires documented approval and the overlap recorded in IPAM.

---

### ZT-NET-003 — Internet egress is centralized and inspected
**Tier:** required · **Criticality:** 0,1
**Applies when:** Any VPC whose workloads initiate outbound internet traffic
**Authority:** SRC-AWS-MULTIVPC#welcome · **Check:** `policies/opa/zt-net-003.rego`

Uninspected egress is the exfiltration path and the command-and-control path.
Centralizing it is not primarily a cost measure — it is what makes a single
inspection policy enforceable instead of per-VPC and drifting.

- Egress routed through a shared inspection VPC via Transit Gateway.
- AWS Network Firewall or a Gateway Load Balancer appliance in the path.
- Workload VPCs have no internet gateway of their own; NAT gateways live only
  in the egress VPC.

**Exception:** latency-sensitive workload with a documented throughput
requirement → requires ZT-NET-012 applied at the workload VPC.

---

### ZT-NET-004 — Traffic between network layers is explicitly authorized
**Tier:** required · **Criticality:** 0,1,2 · **WAF:** SEC05-BP02
**Applies when:** Any workload with more than one network tier
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP02 · **Check:** —

Perimeter-only trust fails the moment one host inside the perimeter is
compromised. Controlling flow between layers converts a single breach into a
contained one.

- Security group ingress references peer security group IDs for east-west
  traffic; CIDR-based rules only at the edge tier.
- Each cross-tier flow is a named, single-purpose rule.
- Default-deny between tiers; no "allow all from VPC CIDR" rules.

---

### ZT-NET-005 — Service-to-service reachability requires explicit service network association
**Tier:** recommended · **Criticality:** 0,1
**Applies when:** Workloads using VPC Lattice for service-to-service traffic
**Authority:** SRC-AWS-LATTICE#vpc-service-network-features · **Check:** —

First of VPC Lattice's four defense layers. Association *is* the reachability
decision — absent an association or a service-network VPC endpoint, a client
cannot reach the service at all, regardless of any policy above it.

- Clients reach services only via VPC-to-service-network association or a VPC
  endpoint of type `service network`.
- Association granted per client VPC, never organization-wide.

---

### ZT-NET-006 — Security groups are applied to VPC–service network associations
**Tier:** recommended · **Criticality:** 0,1
**Applies when:** Workloads using VPC Lattice service networks
**Authority:** SRC-AWS-LATTICE#vpc-service-network-features · **Check:** —

Lattice's second layer. Without it, association grants reachability to every
client in the associated VPC and the auth policy becomes the sole control — one
layer, contrary to defense in depth.

- Security groups attached to the VPC–service network association.
- Rules reference client security group IDs, not VPC CIDR.

---

### ZT-NET-007 — Service networks carry a coarse-grained auth policy
**Tier:** recommended · **Criticality:** 0,1
**Applies when:** Workloads using VPC Lattice service networks
**Authority:** SRC-AWS-LATTICE#vpc-service-network-components-overview · **Check:** —

Lattice's third layer, owned by the network administrator rather than the
service team. It sets the floor individual service owners cannot accidentally
drop below — the separation of duties is the point.

- Auth policy attached at the service network, set by the service network owner.
- Policy asserts authenticated principals only; anonymous access denied.
- **Note:** service network auth policies do *not* apply to resource
  configurations. Resources need separate treatment.

---

### ZT-NET-008 — Individual services carry a fine-grained auth policy
**Tier:** recommended · **Criticality:** 0,1
**Applies when:** Workloads using VPC Lattice services
**Authority:** SRC-AWS-LATTICE#vpc-service-network-components-overview · **Check:** —

Lattice's fourth layer. The service owner knows which callers are legitimate;
the network owner does not. Pushing fine-grained authorization to the service is
what makes per-identity decisions accurate rather than nominal.

- Auth policy on each service naming permitted principals and actions.
- Policies identify callers by IAM principal, not by source IP.

**Exception:** service is internal-only and the service network policy is
provably equivalent → requires a recorded equivalence review, re-checked on any
service network policy change.

---

### ZT-NET-009 — Application access is evaluated per request, not per session
**Tier:** required · **Criticality:** 0,1
**Applies when:** Any workload exposing applications to human users
**Authority:** SRC-AWS-VERIFIED-ACCESS#feature-overview · **Check:** —

A traditional model evaluates access once and then grants broad reach, which is
what lets an attacker move laterally between applications after a single
successful authentication. Per-request evaluation makes that movement expensive.

- AWS Verified Access in front of applications, replacing VPN-based
  network-level admission.
- Trust providers integrated for both identity and device signals.
- All access attempts logged centrally.

> **Review note:** the authority anchor is an overview page with no testable
> configuration detail. Fetch the policy-syntax and trust-provider pages before
> this control stays at `required`.

---

### ZT-NET-010 — AWS service access uses VPC endpoints rather than internet egress
**Tier:** required · **Criticality:** 0,1
**Applies when:** Any VPC-attached workload calling AWS service APIs
**Authority:** SRC-AWS-MULTIVPC#welcome · **Check:** —

Routing API calls over the internet widens the egress path ZT-NET-003 exists to
narrow, and makes service traffic indistinguishable from general outbound
traffic at the inspection point.

- Interface endpoints (PrivateLink) for the AWS services in use.
- Gateway endpoints for S3 and DynamoDB.
- Endpoint policies restrict which principals and resources may be reached.

---

### ZT-NET-012 — Inspection-based protection is deployed in the traffic path
**Tier:** recommended · **Criticality:** 0,1 · **WAF:** SEC05-BP03
**Applies when:** Workloads handling untrusted input or regulated data
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP03 · **Check:** —

Flow controls decide whether a connection is permitted; inspection decides
whether its contents are acceptable. Identity-based ingress cannot detect a
malicious payload from a legitimately authorized caller.

- AWS Network Firewall for VPC-level inspection.
- AWS WAF on ALB / CloudFront / API Gateway for HTTP-layer inspection.
- Gateway Load Balancer where a third-party appliance is required.

---

### ZT-NET-013 — Network protection is applied by automation, not by hand
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC05-BP04
**Applies when:** Any workload with more than one environment or account
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP04 · **Check:** —

Hand-applied network controls drift, and drift is invisible until an incident
surfaces it. Automation is what makes the control's state at any later date
knowable rather than assumed.

- All network resources defined in IaC; console changes treated as drift.
- AWS Firewall Manager for organization-wide rule enforcement.
- Drift detection alerting on out-of-band change.

---

### ZT-NET-014 — Private-tier subnets deny unrestricted ingress
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC05-BP02
**Applies when:** Any VPC-attached compute not explicitly designated an edge tier
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP02 · **Check:** `policies/opa/zt-net-014.rego`
**Partial upstream:** `CKV_AWS_24`, `CKV_AWS_25` (ports 22 and 3389 only)

Perimeter-only trust fails the moment one edge host is compromised. Ingress must
be authorized per-source-identity, not per-network-location.

- Security group ingress references peer SG IDs, never CIDR blocks, for
  east-west traffic.
- Public exposure terminates at ALB/CloudFront; origin protected by VPC origin
  or an SG referencing the managed prefix list.
- No `0.0.0.0/0` ingress on any private-tier security group.

**Exception:** documented public-facing NLB for a non-HTTP protocol → requires
ZT-NET-021.

> The upstream Checkov rules cover only ports 22 and 3389. They are a useful
> floor and do **not** satisfy this control, which asserts the general case.

---

### ZT-NET-015 — Subnets do not auto-assign public IP addresses
**Tier:** required · **Criticality:** 0,1,2
**Applies when:** Any subnet outside a designated edge tier
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP01 · **Check:** `policies/opa/zt-net-015.rego`
**Upstream equivalent:** `CKV_AWS_130`

Auto-assignment makes public exposure the default outcome of a routine launch.
The failure is silent: nothing errors, and the instance is simply reachable.
Defaults decide outcomes far more often than policies do.

- `map_public_ip_on_launch = false` on all non-edge subnets.
- Edge-tier subnets requiring public IPs explicitly tagged as such.

---

### ZT-NET-016 — Every security group rule carries a description
**Tier:** recommended · **Criticality:** 0,1,2
**Applies when:** Any security group
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP04 · **Check:** `policies/opa/zt-net-016.rego`
**Upstream equivalent:** `CKV_AWS_23`

An undescribed rule cannot be safely removed, because no one knows what breaks.
Rule sets therefore only ever grow. The description is what makes least
privilege maintainable over years rather than achievable once.

> **Review note:** the authority anchor is weak — SEC05-BP04 concerns automation
> generally, not rule documentation. Sound operationally but closer to house
> convention than a documented AWS requirement. A candidate for demotion to
> `contextual`, or the first control to gain a real `kb_source`.

---

### ZT-NET-021 — Non-HTTP public exposure is firewall-inspected
**Tier:** required · **Criticality:** 0,1 · **WAF:** SEC05-BP03
**Applies when:** A public-facing NLB or non-HTTP listener exists
**Authority:** SRC-AWS-WAF-SEC#SEC05-BP03 · **Check:** —

Compensating control for ZT-NET-014. An NLB cannot terminate at a WAF, so the
HTTP-layer inspection that normally justifies public exposure is unavailable.
Network Firewall restores an inspection point; without it, the ZT-NET-014
exception grants unreviewed public reach.

- AWS Network Firewall in the ingress path with a stateful rule group scoped to
  the expected protocol.
- Rules deny by default and allow only the named protocol and ports.
- Flow logs from the firewall subnet retained per ZT-TEL-002.

*Authored to satisfy ZT-NET-014's exception — schema rule 5 requires that
`exceptions.requires` name a real control.*
