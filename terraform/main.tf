########################################
# versions + provider
########################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-1"
}

########################################
# variables
########################################
variable "vpc_cidr_blocks"   { type = string }
variable "subnet_cidr_blocks"{ type = string }
variable "avail_zone"        { type = string }
variable "instance_type"     { type = string }
variable "public_key"        { type = string }

########################################
# networking
########################################
resource "aws_vpc" "dream_vpc" {
  cidr_block           = var.vpc_cidr_blocks
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "dream-vpc" }
}

resource "aws_subnet" "dream_subnet" {
  vpc_id                  = aws_vpc.dream_vpc.id
  cidr_block              = var.subnet_cidr_blocks
  availability_zone       = var.avail_zone
  map_public_ip_on_launch = true
  tags = { Name = "dream-subnet" }
}

resource "aws_internet_gateway" "dream_igw" {
  vpc_id = aws_vpc.dream_vpc.id
  tags   = { Name = "dream-igw" }
}

resource "aws_route_table" "dream_rt" {
  vpc_id = aws_vpc.dream_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dream_igw.id
  }
  tags = { Name = "dream-rt" }
}

resource "aws_route_table_association" "dream_rt_assoc" {
  subnet_id      = aws_subnet.dream_subnet.id
  route_table_id = aws_route_table.dream_rt.id
}

########################################
# security group
########################################
resource "aws_security_group" "dream_sg" {
  name   = "dream-app-sg"
  vpc_id = aws_vpc.dream_vpc.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPs
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Dream-App-sg" }
}

########################################
# key pair
########################################
resource "aws_key_pair" "ssh_key" {
  key_name   = "Dream-app-key"
  public_key = var.public_key
}

########################################
# AMI (latest Ubuntu 24.04 LTS)
########################################
data "aws_ami" "ubuntu_lts" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

########################################
# IAM for SSM + CloudWatch Agent
########################################
resource "aws_iam_role" "ec2_role" {
  name = "dream-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action   = "sts:AssumeRole"
    }]
  })
}

# Allow SSM + CloudWatch agent
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "dream-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

########################################
# CloudWatch agent config in SSM Parameter
########################################
resource "aws_ssm_parameter" "cloudwatch_config" {
  name = "AmazonCloudWatch-DreamAppConfig"
  type = "String"
  overwrite   = true 
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "cwagent"
    }
    metrics = {
      namespace          = "DreamApp/EC2"
      append_dimensions  = { InstanceId = "$${aws:InstanceId}" }
      metrics_collected  = {
        cpu = {
          measurement                 = ["cpu_usage_active"]
          metrics_collection_interval = 60
        }
      }
    }
  })
}

########################################
# EC2 + user data
########################################
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Docker + Compose v2
    apt-get update -y
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker ubuntu || true
    systemctl enable docker
    systemctl start docker

    # CloudWatch Agent
    cd /tmp
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i -E ./amazon-cloudwatch-agent.deb
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:AmazonCloudWatch-DreamAppConfig
  EOF
}

resource "aws_instance" "dream_app" {
  ami                         = data.aws_ami.ubuntu_lts.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.dream_subnet.id
  vpc_security_group_ids      = [aws_security_group.dream_sg.id]
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  user_data                   = local.user_data

  tags = { Name = "Dream App Server" }
}

########################################
# CloudWatch alarm
########################################
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "DreamApp-CPU-Utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cpu_usage_active"
  namespace           = "DreamApp/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Alarm when CPU exceeds 70% for 2 minutes"
  dimensions = {
    InstanceId = aws_instance.dream_app.id
  }
}

########################################
# outputs
########################################
output "ec2_public_ip" {
  value = aws_instance.dream_app.public_ip
}
