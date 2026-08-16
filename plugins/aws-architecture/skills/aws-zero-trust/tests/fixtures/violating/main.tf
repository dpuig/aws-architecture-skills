# Deliberately violates one ZT control per resource. Every deny rule in
# policies/opa/ should fire exactly once against this plan.
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

# ZT-NET-003: internet gateway in a workload VPC, not tagged Tier=egress
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# ZT-NET-015: auto-assigns public IPs outside an edge tier
resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

# ZT-NET-014: open ingress; ZT-NET-016: no rule description
resource "aws_security_group" "app" {
  name   = "app"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ZT-IDN-005: long-term access key
resource "aws_iam_user" "svc" {
  name = "legacy-service"
}

resource "aws_iam_access_key" "svc" {
  user = aws_iam_user.svc.name
}

# ZT-IDN-006: wildcard action on wildcard resource
resource "aws_iam_policy" "broad" {
  name = "broad"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# ZT-WLD-001: static credentials in a Lambda environment
resource "aws_iam_role" "lambda" {
  name = "lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_lambda_function" "fn" {
  function_name = "processor"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  filename      = "placeholder.zip"

  environment {
    variables = {
      AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
    }
  }
}

# ZT-DAT-005: resource policy granting Principal "*" with no condition
resource "aws_s3_bucket" "data" {
  bucket = "zt-test-data-bucket"
}

resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::zt-test-data-bucket/*"
    }]
  })
}

# ZT-DAT-006: plaintext HTTP listener that serves rather than redirects
resource "aws_lb" "app" {
  name               = "app-lb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.app.id]
}

resource "aws_lb_target_group" "app" {
  name     = "app-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
