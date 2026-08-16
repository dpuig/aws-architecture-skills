# ZT-IDN-006 — Policies grant least privilege.
#
# The test is deliberately crude: wildcard action AND wildcard resource in the
# same Allow statement. That pattern is unambiguous, and catching it in the plan
# is worth more than a sophisticated analysis nobody runs.
package main

import rego.v1

policy_bearing_types := {
	"aws_iam_policy",
	"aws_iam_role_policy",
	"aws_iam_user_policy",
	"aws_iam_group_policy",
}

deny contains msg if {
	some r in resources
	r.type in policy_bearing_types
	doc := json.unmarshal(r.change.after.policy)
	some stmt in statements(doc)
	stmt.Effect == "Allow"
	has_wildcard(stmt.Action)
	has_wildcard(stmt.Resource)
	msg := sprintf(
		"ZT-IDN-006: %s allows Action '*' on Resource '*'. Scope to specific actions and resource ARNs; use Access Analyzer policy generation from CloudTrail activity to find the real set.",
		[r.address],
	)
}

# Statement may be a single object or a list.
statements(doc) := s if {
	is_array(doc.Statement)
	s := doc.Statement
} else := [doc.Statement]

has_wildcard(v) if v == "*"

has_wildcard(v) if {
	is_array(v)
	"*" in v
}
