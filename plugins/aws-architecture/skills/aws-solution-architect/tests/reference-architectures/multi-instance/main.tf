# Fixture for the diagram renderer's placement logic. Not a control fixture —
# it exists to pin the cases where a diagram can lie about failure domains.
#
# Terraform lists every form of a reference together: a single
# `aws_subnet.private["a"].id` is emitted as that, plus `...["a"]`, plus the
# bare `aws_subnet.private`. Taking the union places a one-subnet resource in
# every subnet of the collection; taking only the collection places a
# many-subnet resource in one. Both render a wrong number of failure domains,
# which is precisely what the ZD-TOP controls are about.
#
# So this fixture holds, deliberately:
#   - `count` subnets (addresses carry [0], [1]) that are also public
#   - `for_each` subnets (addresses carry ["a"], ["b"])
#   - an instance pinned to ONE for_each subnet   -> must render in one AZ
#   - an ASG spanning the whole collection        -> must render spanning two
#
# If those two ever render the same way, the renderer has stopped distinguishing
# specific references from collection references.

terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}
provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }

# count -> addresses carry [0], [1]
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = "eu-west-1${count.index == 0 ? "a" : "b"}"
  map_public_ip_on_launch = true
}

# for_each
resource "aws_subnet" "private" {
  for_each          = toset(["a", "b"])
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.key == "a" ? "10.0.10.0/24" : "10.0.11.0/24"
  availability_zone = "eu-west-1${each.key}"
}

resource "aws_security_group" "app" {
  name   = "app"
  vpc_id = aws_vpc.main.id
}

# placed INTO a subnet via subnet_id -> exercises in_subnet bucket
resource "aws_instance" "app" {
  ami                    = "ami-12345678"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private["a"].id
  vpc_security_group_ids = [aws_security_group.app.id]
}

# vpc_zone_identifier -> ASG placed via subnets
resource "aws_launch_template" "lt" {
  name_prefix   = "edge-"
  image_id      = "ami-12345678"
  instance_type = "t3.micro"
}
resource "aws_autoscaling_group" "asg" {
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]
  launch_template { id = aws_launch_template.lt.id }
}
