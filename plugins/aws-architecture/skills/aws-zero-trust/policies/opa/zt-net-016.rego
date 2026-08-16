# ZT-NET-016 — Every security group rule carries a description.
#
# An undescribed rule cannot be safely removed, so rule sets only ever grow.
package main

import rego.v1

deny contains msg if {
	some sg in of_type("aws_security_group")
	some ingress in sg.change.after.ingress
	not has_description(ingress)
	msg := sprintf(
		"ZT-NET-016: %s has an ingress rule (port %v) with no description. State the calling system and the reason for the flow.",
		[sg.address, ingress.from_port],
	)
}

has_description(rule) if {
	rule.description != ""
	rule.description != null
}
