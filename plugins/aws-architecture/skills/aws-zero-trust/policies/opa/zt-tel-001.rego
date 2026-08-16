# ZT-TEL-001 — Service and application logging is configured.
#
# Logging switched on after an incident begins covers none of the incident.
# This is the one control whose entire value is determined before it is needed.
package main

import rego.v1

# A VPC without flow logs has no record of what moved inside it.
deny contains msg if {
	count(of_type("aws_vpc")) > 0
	count(of_type("aws_flow_log")) == 0
	msg := "ZT-TEL-001: the plan creates a VPC but no aws_flow_log. Enable VPC flow logs; without them, network-layer controls cannot be verified after the fact."
}

# A load balancer without access logs loses the request-level record.
deny contains msg if {
	some lb in of_type("aws_lb")
	not access_logs_enabled(lb)
	msg := sprintf(
		"ZT-TEL-001: %s has no enabled access_logs block. ALB access logs are the request-level record behind ZT-TEL-006.",
		[lb.address],
	)
}

access_logs_enabled(lb) if {
	some logs in lb.change.after.access_logs
	logs.enabled == true
}
