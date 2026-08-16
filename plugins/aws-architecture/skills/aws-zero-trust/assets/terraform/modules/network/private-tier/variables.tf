variable "workload" {
  description = "Workload name. Appears in resource names and the Workload tag."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the private tier in."
  type        = string
}

variable "subnets" {
  description = <<-EOT
    Private subnets, keyed by a short AZ identifier (a, b, c).

    The tier model requires 3 AZs at criticality 0 and 2 at criticality 1; this
    module does not enforce that itself, because the criticality is a property
    of the workload rather than of the network. validate.sh Stage 4 asserts it
    against the plan (ZD-TOP-001).
  EOT

  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))

  validation {
    condition     = length(var.subnets) >= 2
    error_message = "A private tier spanning fewer than 2 AZs cannot survive the loss of one."
  }
}

variable "egress_prefix_list_id" {
  description = <<-EOT
    Managed prefix list for the centralized egress path (ZT-NET-003).

    Null creates no egress rule at all, which is the correct default: a private
    tier with no declared egress path should have none, rather than inheriting
    the 0.0.0.0/0 default AWS applies to a bare security group.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags. Tier and Workload are set by the module and cannot be overridden."
  type        = map(string)
  default     = {}
}
