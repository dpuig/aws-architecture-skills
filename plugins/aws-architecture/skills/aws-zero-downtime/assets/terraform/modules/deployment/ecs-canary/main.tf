# ECS service with canary rollout and automatic rollback.
# Satisfies ZD-DEP-002, ZD-DEP-003, ZD-DEG-001, ZD-TOP-011.
#
# Composed by the generator; not written per-architecture.
#
# The rollback path is the reason this module exists. Rollback must be a
# configured mechanism rather than an intention, because the moment it is needed
# is the moment nobody has time to invent one.

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
  common_tags = merge(var.tags, {
    Workload = var.workload
  })

  # ZD-TOP-003: at criticality 0 the service must absorb the loss of one AZ
  # without launching anything, so capacity is provisioned for N-1 rather than N.
  az_count      = length(var.subnet_ids)
  desired_count = var.criticality == 0 ? ceil(var.baseline_count * local.az_count / max(local.az_count - 1, 1)) : var.baseline_count
}

resource "aws_ecs_service" "this" {
  name            = var.workload
  cluster         = var.cluster_arn
  task_definition = var.task_definition_arn
  desired_count   = local.desired_count
  launch_type     = "FARGATE"

  # ZD-DEP-002: rollback is automatic on health signal, not gated on a human.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Canary shape: allow one extra task, never drop below full capacity.
  # ZD-DEP-007 — the bake happens because minimum_healthy stays at 100.
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = 100

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # Long enough for real warm-up; a short grace period causes the deployment to
  # roll itself back on a cold start rather than on a genuine fault.
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  tags = local.common_tags

  lifecycle {
    # desired_count is owned by autoscaling after creation; leaving it managed
    # here makes every plan want to undo a scaling event.
    ignore_changes = [desired_count]
  }
}

resource "aws_lb_target_group" "this" {
  name        = substr("${var.workload}-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # ZD-DEG-001: sized to p99 request duration, not left at the 300s default.
  deregistration_delay = var.deregistration_delay

  # ZD-TOP-011: a zone that loses targets must not keep its share of traffic.
  load_balancing_cross_zone_enabled = "true"

  # ZD-DEG-010: only set where warm-up is real; 0 disables it.
  slow_start = var.slow_start_seconds

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    timeout             = 5
    matcher             = "200"
  }

  # ZD-DEG-009: default behaviour treats a zone as healthy down to one target,
  # which is one instance absorbing a whole zone's load. Only meaningful at
  # criticality 0, where ZD-TOP-003 guarantees somewhere for the traffic to go.
  dynamic "target_group_health" {
    for_each = var.criticality == 0 ? [1] : []
    content {
      dns_failover {
        minimum_healthy_targets_count      = "1"
        minimum_healthy_targets_percentage = tostring(var.minimum_healthy_percentage)
      }
      unhealthy_state_routing {
        minimum_healthy_targets_count      = 1
        minimum_healthy_targets_percentage = tostring(var.minimum_healthy_percentage)
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}
