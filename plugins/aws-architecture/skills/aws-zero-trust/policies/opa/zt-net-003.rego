# ZT-NET-003 — Internet egress is centralized and inspected.
#
# Workload VPCs must not own an internet gateway; egress belongs in the shared
# inspection VPC. An IGW in a workload VPC is an uninspected exfiltration path.
package main

import rego.v1

deny contains msg if {
	some igw in of_type("aws_internet_gateway")
	tier_of(igw) != "egress"
	msg := sprintf(
		"ZT-NET-003: %s is an internet gateway not tagged Tier=egress. Route egress through the shared inspection VPC, or tag this resource as the egress tier.",
		[igw.address],
	)
}
