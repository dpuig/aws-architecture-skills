output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "target_group_arn" {
  description = "Target group ARN, for attaching to a listener rule."
  value       = aws_lb_target_group.this.arn
}

output "desired_count" {
  description = <<-EOT
    Task count the module provisioned.

    At criticality 0 this exceeds baseline_count, because ZD-TOP-003 requires
    the surviving AZs to absorb full load without launching anything. Surface it
    in the deliverable so the cost of static stability is visible rather than
    discovered on an invoice.
  EOT
  value       = local.desired_count
}

output "rollback_configured" {
  description = "Whether an automatic rollback path exists (ZD-DEP-002). Always true for this module; exported so a coverage matrix can cite it as evidence."
  value       = true
}
