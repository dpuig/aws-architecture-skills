# ZT-DAT-002 — Encryption at rest is enforced, not merely enabled.
#
# Enabling encryption on the resources you remember is a property of today's
# architecture. This check makes it a property of the plan.
package main

import rego.v1

# Resource type → the attribute that must be true.
encryption_flag := {
	"aws_db_instance": "storage_encrypted",
	"aws_rds_cluster": "storage_encrypted",
	"aws_ebs_volume": "encrypted",
	"aws_dynamodb_table": "server_side_encryption",
	"aws_efs_file_system": "encrypted",
	"aws_redshift_cluster": "encrypted",
}

deny contains msg if {
	some r in resources
	field := encryption_flag[r.type]
	field != "server_side_encryption"
	r.change.after[field] != true
	msg := sprintf(
		"ZT-DAT-002: %s does not set %s = true. Encryption at rest is required for all persistent storage, including snapshots and backups.",
		[r.address, field],
	)
}

# DynamoDB expresses it as a block rather than a boolean.
deny contains msg if {
	some tbl in of_type("aws_dynamodb_table")
	not sse_enabled(tbl)
	msg := sprintf(
		"ZT-DAT-002: %s has no enabled server_side_encryption block.",
		[tbl.address],
	)
}

sse_enabled(tbl) if {
	some sse in tbl.change.after.server_side_encryption
	sse.enabled == true
}
