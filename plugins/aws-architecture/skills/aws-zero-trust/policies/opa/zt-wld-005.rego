# ZT-WLD-005 — Secrets are stored in a managed secret store.
#
# A literal password in a plan is also a password in Terraform state, in the
# plan file, and in whatever CI system produced them. The control is not "have
# no secrets" but "have no secrets in places that get copied".
package main

import rego.v1

password_bearing := {
	"aws_db_instance": "password",
	"aws_rds_cluster": "master_password",
	"aws_redshift_cluster": "master_password",
	"aws_docdb_cluster": "master_password",
}

deny contains msg if {
	some r in resources
	field := password_bearing[r.type]
	value := r.change.after[field]
	is_string(value)
	value != ""
	msg := sprintf(
		"ZT-WLD-005: %s sets %s to a literal value, which lands in Terraform state. Use manage_master_user_password with Secrets Manager, or reference a secret at runtime.",
		[r.address, field],
	)
}
