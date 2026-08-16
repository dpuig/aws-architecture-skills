# ZT-IDN-005 — No long-term access keys without a recorded use case.
#
# AWS enumerates the legitimate exceptions (workloads that cannot assume roles,
# third-party clients without Identity Center support, CodeCommit, Keyspaces).
# They are narrow and enumerable, so a key in a plan should be arguing its case.
package main

import rego.v1

deny contains msg if {
	some key in of_type("aws_iam_access_key")
	msg := sprintf(
		"ZT-IDN-005: %s creates a long-term access key. Prefer a role (ZT-WLD-001) or certificate federation (ZT-WLD-002). If one of the AWS-documented exceptions applies, waive this control with the specific case recorded.",
		[key.address],
	)
}
