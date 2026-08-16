# ZD-TOP-011 — Failover targets healthy resources automatically.
#
# Failover that requires a human is not failover; it is an incident response
# procedure with better branding.
#
# Two plan-time hazards are handled explicitly here, because both cause a rule
# to silently never fire — which is worse than having no rule, since it still
# counts as coverage:
#
#   1. Values that reference another resource's computed attribute land in
#      `after_unknown`, not `after`. `target_group_arns` is one of these.
#   2. Rego treats JSON null as truthy, so `not x` does not match an explicit
#      null. Use is_unset() instead.
package main

import rego.v1

# True when the key is absent OR explicitly null.
is_unset(obj, key) if object.get(obj, key, null) == null

# Cross-zone load balancing off means a zone that has lost targets still
# receives its full DNS share of traffic, concentrating load on the survivors.
# NLBs default to off; ALBs default to on.
deny contains msg if {
	some tg in of_type("aws_lb_target_group")
	tg.change.after.load_balancing_cross_zone_enabled == "false"
	msg := sprintf(
		"ZD-TOP-011: %s disables cross-zone load balancing. A zone that loses targets keeps its share of traffic, concentrating load on the remaining instances.",
		[tg.address],
	)
}

# An ASG not using ELB health checks only notices EC2-level failure, so a
# process that is running but not serving stays in rotation indefinitely.
deny contains msg if {
	some asg in of_type("aws_autoscaling_group")
	attached_to_target_group(asg)
	asg.change.after.health_check_type != "ELB"
	msg := sprintf(
		"ZD-TOP-011: %s is attached to a target group but uses health_check_type = %q. Set it to ELB, or an instance that is running but not serving is never replaced.",
		[asg.address, asg.change.after.health_check_type],
	)
}

attached_to_target_group(asg) if {
	count(object.get(asg.change.after, "target_group_arns", [])) > 0
}

# The ARN is computed, so at plan time the attachment shows up here instead.
attached_to_target_group(asg) if {
	object.get(asg.change, "after_unknown", {}).target_group_arns
}

# Route 53 failover records without a health check always resolve to the
# primary, including when the primary is down.
deny contains msg if {
	some rec in of_type("aws_route53_record")
	count(object.get(rec.change.after, "failover_routing_policy", [])) > 0
	is_unset(rec.change.after, "health_check_id")
	msg := sprintf(
		"ZD-TOP-011: %s uses a failover routing policy with no health_check_id, so it will never fail over.",
		[rec.address],
	)
}
