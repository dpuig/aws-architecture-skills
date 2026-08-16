# ZT-NET-014 — Private-tier subnets deny unrestricted ingress.
#
# Covers both the inline `ingress` block on aws_security_group and the standalone
# aws_vpc_security_group_ingress_rule. Upstream Checkov rules CKV_AWS_24/25 catch
# only ports 22 and 3389; this asserts the general case.
package main

import rego.v1

open_cidr := {"0.0.0.0/0", "::/0"}

deny contains msg if {
	some sg in of_type("aws_security_group")
	tier_of(sg) != "edge"
	some ingress in sg.change.after.ingress
	some cidr in ingress.cidr_blocks
	cidr in open_cidr
	msg := sprintf(
		"ZT-NET-014: %s allows ingress from %s on port %v. Reference a peer security group ID instead, or designate this an edge tier (Tier=edge).",
		[sg.address, cidr, ingress.from_port],
	)
}

deny contains msg if {
	some rule in of_type("aws_vpc_security_group_ingress_rule")
	tier_of(rule) != "edge"
	rule.change.after.cidr_ipv4 in open_cidr
	msg := sprintf(
		"ZT-NET-014: %s allows ingress from %s. Reference a peer security group ID instead, or designate this an edge tier.",
		[rule.address, rule.change.after.cidr_ipv4],
	)
}
