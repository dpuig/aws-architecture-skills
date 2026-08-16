output "subnet_ids" {
  description = "Private subnet IDs, keyed by AZ identifier."
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "subnet_ids_list" {
  description = "Private subnet IDs as a list, for resources taking subnet_ids."
  value       = [for s in aws_subnet.this : s.id]
}

output "security_group_id" {
  description = <<-EOT
    Default-deny security group for the tier.

    Callers reference this ID from peer security group rules rather than opening
    CIDR ranges — that reference is what ZT-NET-014 requires and what makes
    east-west authorization identity-based rather than location-based.
  EOT
  value       = aws_security_group.this.id
}

output "route_table_ids" {
  description = "Route table IDs, keyed by AZ identifier."
  value       = { for k, rt in aws_route_table.this : k => rt.id }
}

output "availability_zones" {
  description = "AZs the tier spans. Feeds the ZD-TOP-001 spread assertion."
  value       = [for s in aws_subnet.this : s.availability_zone]
}
