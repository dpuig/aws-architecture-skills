# Shared helpers. Conftest merges all files in this package.
#
# Policies read `resource_changes` rather than `planned_values` because it is a
# flat list — resources inside modules appear at the top level, so no recursion
# is needed and module nesting cannot hide a violation.
package main

import rego.v1

resources contains r if {
	some r in input.resource_changes
	r.change.actions != ["delete"]
	r.change.actions != ["no-op"]
}

of_type(t) := [r | some r in resources; r.type == t]

# Tier is carried as a tag, per ZT-NET-001: tier must be declared, never
# inferred from a subnet name or CIDR.
tier_of(r) := t if {
	t := r.change.after.tags.Tier
} else := "unset"
