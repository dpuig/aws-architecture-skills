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

# VIOLATION: only 2 AZs; tier-0 requires 3
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

resource "aws_launch_template" "lt" {
  name_prefix   = "claims-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
}

# VIOLATION: min_size 1 across 3 AZs — losing one AZ drops below minimum
resource "aws_autoscaling_group" "app" {
  min_size           = 1
  max_size           = 6
  desired_capacity   = 3
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  launch_template {
    id = aws_launch_template.lt.id
  }
}

# VIOLATION: no Multi-AZ on a tier-0 database
resource "aws_db_instance" "db" {
  identifier          = "claims"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "dbadmin"
  password            = "changeme123"
  skip_final_snapshot = true
  multi_az            = false
}

# VIOLATION: no deregistration_delay, no health check thresholds
resource "aws_lb_target_group" "tg" {
  name     = "claims-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id
}
