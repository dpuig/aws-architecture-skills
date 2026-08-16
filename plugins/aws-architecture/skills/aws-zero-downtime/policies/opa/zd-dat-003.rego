# ZD-DAT-003 — Backups are automated and retained.
#
# Multi-AZ protects against infrastructure failure. It does not protect against
# a bad migration or a mistaken DELETE — those replicate faithfully to the
# standby. A retention period of 0 means no automated backups at all.
package main

import rego.v1

backup_bearing := {
	"aws_db_instance",
	"aws_rds_cluster",
	"aws_docdb_cluster",
	"aws_neptune_cluster",
}

deny contains msg if {
	some r in resources
	r.type in backup_bearing
	retention := object.get(r.change.after, "backup_retention_period", 0)
	retention == 0
	msg := sprintf(
		"ZD-DAT-003: %s has backup_retention_period = 0, so automated backups are disabled. Size retention to the RPO stated under ZD-DAT-001.",
		[r.address],
	)
}

# Point-in-time recovery is the DynamoDB equivalent and is off by default.
deny contains msg if {
	some tbl in of_type("aws_dynamodb_table")
	not pitr_enabled(tbl)
	msg := sprintf(
		"ZD-DAT-003: %s has no enabled point_in_time_recovery block. Without it the table cannot be restored to a moment before a bad write.",
		[tbl.address],
	)
}

pitr_enabled(tbl) if {
	some pitr in tbl.change.after.point_in_time_recovery
	pitr.enabled == true
}
