# Deliberately violates one ZD control per resource. Every deny rule in
# policies/opa/ should fire against this plan.
#
# Do not "fix" anything here — the violations are the test.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

# ZD-DAT-003: automated backups disabled
resource "aws_db_instance" "db" {
  identifier              = "orders"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "dbadmin"
  password                = "changeme123"
  skip_final_snapshot     = true
  backup_retention_period = 0
}

# ZD-DAT-003: no point-in-time recovery
resource "aws_dynamodb_table" "sessions" {
  name         = "sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# ZD-DAT-004: unencrypted vault, and no vault lock anywhere in the plan
resource "aws_backup_vault" "main" {
  name = "orders-vault"
}

# ZD-DEP-003: launch configuration cannot be versioned
resource "aws_launch_configuration" "legacy" {
  name_prefix   = "legacy-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
}

# ZD-DEP-003: $Latest re-resolves on scale-out
# ZD-TOP-011: attached to a target group but not using ELB health checks
resource "aws_autoscaling_group" "app" {
  min_size           = 3
  max_size           = 9
  desired_capacity   = 3
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  target_group_arns  = [aws_lb_target_group.app.arn]
  health_check_type  = "EC2"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}

# ZD-DEP-003: mutable :latest image tag
resource "aws_ecs_task_definition" "app" {
  family = "orders"
  container_definitions = jsonencode([{
    name   = "app"
    image  = "myrepo/orders:latest"
    memory = 256
  }])
}

# ZD-DEG-009: no target group health thresholds
# ZD-TOP-011: cross-zone load balancing disabled
resource "aws_lb_target_group" "app" {
  name                              = "orders-tg"
  port                              = 443
  protocol                          = "HTTPS"
  vpc_id                            = aws_vpc.main.id
  deregistration_delay              = 30
  load_balancing_cross_zone_enabled = "false"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "HTTPS"
  }
}

# ZD-TOP-011: failover routing policy with no health check
resource "aws_route53_zone" "main" {
  name = "example.internal"
}

resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.id
  name    = "api.example.internal"
  type    = "A"
  ttl     = 60
  records = ["10.0.1.10"]

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }
}
