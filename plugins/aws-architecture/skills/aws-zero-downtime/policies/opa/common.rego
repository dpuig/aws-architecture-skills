# Shared helpers for ZD policies. Conftest merges all files in this package.
#
# Scope note: this directory holds only resource-shape assertions. The
# architectural invariants — AZ spread, capacity surviving N-1, Multi-AZ by tier
# — live in validate.sh Stage 4 because they need the criticality tier and must
# reason across resources. Implementing them here as well would create two
# sources of truth that drift.
package main

import rego.v1

resources contains r if {
	some r in input.resource_changes
	r.change.actions != ["delete"]
	r.change.actions != ["no-op"]
}

of_type(t) := [r | some r in resources; r.type == t]
