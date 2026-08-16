# ZT-NET-015 — Subnets do not auto-assign public IP addresses.
#
# Public exposure must be a decision, not the default outcome of a launch.
package main

import rego.v1

deny contains msg if {
	some subnet in of_type("aws_subnet")
	subnet.change.after.map_public_ip_on_launch == true
	tier_of(subnet) != "edge"
	msg := sprintf(
		"ZT-NET-015: %s sets map_public_ip_on_launch = true outside an edge tier. Set it false, or tag the subnet Tier=edge if public addressing is intended.",
		[subnet.address],
	)
}
