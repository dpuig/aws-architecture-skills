# Identical to tier0-compliant except that no Region was ever specified.
#
# The point of the fixture is that everything else still passes: the zero-
# downtime invariants are satisfied, the plan is clean, and the ONLY thing
# holding the gate shut is that nobody said where this runs. That isolates the
# Region check — a fixture that also broke an invariant could not tell the two
# failures apart.
#
# Note the placeholder lives in the variable *description*, not the value. A
# fake Region string passes `terraform validate` and then fails `terraform plan`
# with "invalid AWS Region", which would take down Stage 1 and produce no
# deliverable at all. The placeholder has to be a real, plannable Region that is
# loudly labelled as unchosen.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "Deployment Region. REGION-PLACEHOLDER: not specified in the brief; planning value only."
  type        = string
  default     = "us-east-1"
}

provider "aws" {
  region                      = var.aws_region
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
  availability_zone = "${var.aws_region}a"
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
}

resource "aws_subnet" "c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}c"
}

resource "aws_launch_template" "lt" {
  name_prefix   = "claims-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
}

resource "aws_autoscaling_group" "app" {
  min_size         = 3
  max_size         = 9
  desired_capacity = 3
  availability_zones = [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c",
  ]

  launch_template {
    id = aws_launch_template.lt.id
  }
}

resource "aws_db_instance" "db" {
  identifier          = "claims"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "dbadmin"
  password            = "changeme123"
  skip_final_snapshot = true
  multi_az            = true
}

resource "aws_lb_target_group" "tg" {
  name                 = "claims-tg"
  port                 = 443
  protocol             = "HTTPS"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "HTTPS"
  }
}

resource "aws_ecs_cluster" "main" {
  name = "claims"
}

resource "aws_ecs_task_definition" "app" {
  family                = "claims"
  container_definitions = jsonencode([{ name = "app", image = "nginx", memory = 256 }])
}

resource "aws_ecs_service" "app" {
  name            = "claims"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 3

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
