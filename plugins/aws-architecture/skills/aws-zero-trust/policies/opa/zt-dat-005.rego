# ZT-DAT-005 — Access control is enforced at the resource.
#
# Resource policies fail open in a way identity policies do not: a bucket policy
# naming the wrong principal is silently world-readable. Encryption does nothing
# about a principal who is authorized and should not be.
package main

import rego.v1

resource_policy_types := {
	"aws_s3_bucket_policy",
	"aws_sqs_queue_policy",
	"aws_sns_topic_policy",
	"aws_kms_key",
	"aws_secretsmanager_secret_policy",
}

deny contains msg if {
	some r in resources
	r.type in resource_policy_types
	doc := json.unmarshal(policy_doc(r))
	some stmt in statements(doc)
	stmt.Effect == "Allow"
	is_public_principal(stmt.Principal)
	not stmt.Condition
	msg := sprintf(
		"ZT-DAT-005: %s allows Principal '*' with no Condition. Scope to specific principals, or constrain with aws:PrincipalOrgID or aws:SourceVpce.",
		[r.address],
	)
}

policy_doc(r) := r.change.after.policy

statements(doc) := s if {
	is_array(doc.Statement)
	s := doc.Statement
} else := [doc.Statement]

is_public_principal(p) if p == "*"

is_public_principal(p) if p.AWS == "*"

is_public_principal(p) if {
	is_array(p.AWS)
	"*" in p.AWS
}
