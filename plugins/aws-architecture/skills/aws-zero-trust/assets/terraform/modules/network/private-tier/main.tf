# Private-tier subnets — satisfies ZT-NET-001, ZT-NET-014, ZT-NET-015.
#
# Composed by the generator; not written per-architecture. Changes here change
# every architecture built after them, so treat this as catalog content and
# version it with the catalog.
#
# What this module deliberately does NOT do:
#   - create an internet gateway (ZT-NET-003 — egress belongs in the shared
#     inspection VPC)
#   - create NAT gateways (same reason)
#   - open any ingress (ZT-NET-014 — callers attach rules referencing peer
#     security group IDs)

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  # Tier is a tag, never inferred from name or CIDR (ZT-NET-001).
  common_tags = merge(var.tags, {
    Tier     = "private"
    Workload = var.workload
  })
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id            = var.vpc_id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  # ZT-NET-015: public addressing is never the default outcome of a launch.
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.workload}-private-${each.key}"
  })
}

# One route table per AZ so a single AZ's routing can be changed — or evacuated —
# without touching the others.
resource "aws_route_table" "this" {
  for_each = var.subnets

  vpc_id = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.workload}-private-${each.key}"
  })
}

resource "aws_route_table_association" "this" {
  for_each = var.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

# Default-deny security group. Callers attach rules referencing peer security
# group IDs (ZT-NET-004); this module never opens ingress itself.
resource "aws_security_group" "this" {
  name_prefix = "${var.workload}-private-"
  vpc_id      = var.vpc_id
  description = "Private tier for ${var.workload}. Ingress via peer SG references only."

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Egress to the inspection path only. Described, per ZT-NET-016.
resource "aws_vpc_security_group_egress_rule" "inspection" {
  count = var.egress_prefix_list_id == null ? 0 : 1

  security_group_id = aws_security_group.this.id
  prefix_list_id    = var.egress_prefix_list_id
  ip_protocol       = "-1"
  description       = "Egress to centralized inspection path (ZT-NET-003)"
}
