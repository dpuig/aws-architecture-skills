# ZD-DAT-004 — Backups are encrypted and access-controlled.
#
# A backup is a complete copy of production data with weaker access controls and
# less monitoring than the primary. Cross-references ZT-DAT-002, which states
# the encryption requirement in full.
package main

import rego.v1

deny contains msg if {
	some vault in of_type("aws_backup_vault")
	not vault.change.after.kms_key_arn
	msg := sprintf(
		"ZD-DAT-004: %s has no kms_key_arn. A backup vault holds a full copy of production data and must be encrypted with a customer-managed key.",
		[vault.address],
	)
}

deny contains msg if {
	some snap in of_type("aws_db_snapshot")
	snap.change.after.encrypted != true
	msg := sprintf("ZD-DAT-004: %s is not encrypted.", [snap.address])
}

# Vault lock is what makes retention survive a compromised credential: without
# it, a principal that can delete backups defeats the entire control.
deny contains msg if {
	count(of_type("aws_backup_vault")) > 0
	count(of_type("aws_backup_vault_lock_configuration")) == 0
	msg := "ZD-DAT-004: backup vaults exist with no aws_backup_vault_lock_configuration. Without vault lock, a principal able to delete backups defeats the retention requirement."
}
