# ZD-DEG-009 — Zonal brownout is bounded by health thresholds.
#
# By default a target group is healthy while it has ONE healthy target. For a
# large fleet that is not availability — it is one instance absorbing an entire
# zone's load, and failing. AWS documents both thresholds precisely so the
# default can be overridden.
package main

import rego.v1

deny contains msg if {
	some tg in of_type("aws_lb_target_group")
	not dns_failover_configured(tg)
	msg := sprintf(
		"ZD-DEG-009: %s sets no target_group_health DNS failover threshold, so a zone stays in DNS while degraded down to a single healthy target.",
		[tg.address],
	)
}

dns_failover_configured(tg) if {
	some cfg in tg.change.after.target_group_health
	some dns in cfg.dns_failover
	dns.minimum_healthy_targets_percentage != "off"
}

dns_failover_configured(tg) if {
	some cfg in tg.change.after.target_group_health
	some dns in cfg.dns_failover
	to_number(dns.minimum_healthy_targets_count) > 1
}
