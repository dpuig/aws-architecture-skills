variable "workload" {
  description = "Workload name. Appears in resource names and the Workload tag."
  type        = string
}

variable "criticality" {
  description = <<-EOT
    Workload criticality tier (0, 1, or 2) from the intake brief.

    Drives three behaviours the tier model requires rather than merely suggests:
    N-1 capacity provisioning (ZD-TOP-003), target group health thresholds
    (ZD-DEG-009), and how much headroom the rollout is given. Passing the tier
    in rather than exposing each knob separately keeps the module's behaviour
    consistent with the catalog instead of at the caller's discretion.
  EOT
  type        = number

  validation {
    condition     = contains([0, 1, 2], var.criticality)
    error_message = "Criticality must be 0, 1, or 2. See aws-solution-architect/references/tier-model.md."
  }
}

variable "cluster_arn" {
  description = "ECS cluster ARN."
  type        = string
}

variable "task_definition_arn" {
  description = <<-EOT
    Task definition ARN, pinned to a revision.

    ZD-DEP-003 requires an immutable artifact: passing a family name without a
    revision means a service restart can silently change the running code.
  EOT
  type        = string
}

variable "vpc_id" {
  description = "VPC for the target group."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    Subnets to run tasks in — normally the private-tier output from
    aws-zero-trust/assets/terraform/modules/network/private-tier.

    Length is treated as the AZ count for N-1 capacity sizing, so pass one
    subnet per AZ and no more.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A service in fewer than 2 AZs cannot survive the loss of one (ZD-TOP-001)."
  }
}

variable "security_group_ids" {
  description = "Security groups for the tasks."
  type        = list(string)
}

variable "container_name" {
  description = "Container name in the task definition to attach to the load balancer."
  type        = string
}

variable "container_port" {
  description = "Container port."
  type        = number
}

variable "baseline_count" {
  description = <<-EOT
    Task count needed to serve full load with all AZs healthy.

    At criticality 0 the module scales this up so the surviving AZs can absorb
    full load without launching anything — do not pre-inflate it yourself.
  EOT
  type        = number
  default     = 3
}

variable "deployment_maximum_percent" {
  description = "Upper bound during deployment. 150 gives a canary; 200 gives blue/green."
  type        = number
  default     = 150
}

variable "deregistration_delay" {
  description = <<-EOT
    Connection draining, in seconds. The AWS default is 300, which is correct
    for long-lived connections and needlessly slow for short HTTP requests —
    it lengthens every scale-in and deployment. Size to p99 request duration.
  EOT
  type        = number
  default     = 30
}

variable "slow_start_seconds" {
  description = <<-EOT
    Warm-up ramp, in seconds. 0 disables it (the AWS default). Valid range when
    enabled is 30-900. Only set this where warm-up is real — for a target that
    needs none, it merely slows recovery (ZD-DEG-010).
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.slow_start_seconds == 0 || (var.slow_start_seconds >= 30 && var.slow_start_seconds <= 900)
    error_message = "slow_start_seconds must be 0 (disabled) or between 30 and 900."
  }
}

variable "minimum_healthy_percentage" {
  description = "Percentage of healthy targets below which a zone is failed away (ZD-DEG-009). Criticality 0 only."
  type        = number
  default     = 50
}

variable "health_check_grace_period_seconds" {
  description = "Grace period before health checks count. Must exceed real cold-start time, or deployments roll back on startup rather than on faults."
  type        = number
  default     = 60
}

variable "health_check_path" {
  description = "Health check path. Should exercise a real dependency, not return a static 200 (ZD-DEG-001)."
  type        = string
  default     = "/health"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
