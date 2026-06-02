terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_dynamodb_table" "tasks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "task_id"

  attribute {
    name = "task_id"
    type = "S"
  }

  tags = {
    Name        = var.table_name
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Allow HTTP and SSH for ${var.project_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_cidr]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role" "ec2" {
  count = var.create_instance_profile ? 1 : 0
  name  = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "dynamodb" {
  count = var.create_instance_profile ? 1 : 0
  name  = "${var.project_name}-dynamodb-policy"
  role  = aws_iam_role.ec2[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.tasks.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  count = var.create_instance_profile ? 1 : 0
  name  = "${var.project_name}-instance-profile"
  role  = aws_iam_role.ec2[0].name
}

locals {
  instance_profile_name = var.create_instance_profile ? aws_iam_instance_profile.app[0].name : var.existing_instance_profile_name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  iam_instance_profile        = local.instance_profile_name != "" ? local.instance_profile_name : null

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    app_name     = var.project_name
    aws_region   = var.aws_region
    table_name   = aws_dynamodb_table.tasks.name
    git_repo_url = var.git_repo_url
    git_branch   = var.git_branch
  })

  tags = {
    Name        = var.project_name
    Project     = var.project_name
    Environment = var.environment
  }
}
