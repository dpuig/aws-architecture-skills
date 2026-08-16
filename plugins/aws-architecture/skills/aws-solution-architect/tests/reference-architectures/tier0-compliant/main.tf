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

# 3 AZs — satisfies tier-0 spread
resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_subnet" "c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1c"
}

resource "aws_launch_template" "lt" {
  name_prefix   = "claims-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
}

# min_size 3 across 3 AZs — static stability at N-1
resource "aws_autoscaling_group" "app" {
  min_size           = 3
  max_size           = 9
  desired_capacity   = 3
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

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
