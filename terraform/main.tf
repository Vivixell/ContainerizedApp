provider "aws" {
  region = "us-west-1"
}

variable "vpc_cidr_blocks" {}
variable "subnet_cidr_blocks" {}
variable "avail_zone" {}
variable "instance_type" {}
variable "public_key" {}

# User Data Script for EC2
locals {
  user_data = <<EOF
#!/bin/bash
# Install Docker
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker

# Install CloudWatch Agent
sudo wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:AmazonCloudWatch-DreamAppConfig
EOF
}

resource "aws_vpc" "dream-vpc" {
  cidr_block = var.vpc_cidr_blocks
  tags = {
    Name = "dream-vpc"
  }
}

resource "aws_subnet" "dream-subnet" {
  vpc_id            = aws_subnet_cidr_blocks
  cidr_block        = var.subnet_cidr_blocks
  availability_zone = var.avail_zone
  tags = {
    Name = "dream-subnet"
  }
}

resource "aws_internet_gateway" "dream-igw" {
  vpc_id = aws_vpc.dream-vpc.id
  tags = {
    Name = "dream-igw"
  }
}

resource "aws_route_table" "dream-rt" {
  vpc_id = aws_vpc.dream-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dream-igw.id
  }
  tags = {
    Name = "dream-rt"
  }
}

resource "aws_route_table_association" "dream-rt-public-subnet" {
  subnet_id      = aws_subnet.dream-subnet.id
  route_table_id = aws_route_table.dream-rt.id
}

resource "aws_security_group" "dream-sg" {
  name   = "dream-app-sg"
  vpc_id = aws_vpc.dream-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Dream-App-sg"
  }
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "Dream-app-key"
  public_key = var.public_key
}

data "aws_ami" "latest-Ubuntu-Serve-image" {
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

resource "aws_instance" "dream-app_server" {
  ami                         = data.aws_ami.latest-Ubuntu-Serve-image.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.dream-subnet.id
  vpc_security_group_ids      = [aws_security_group.dream-sg.id]
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name
  user_data                   = local.user_data

  tags = {
    Name = "Dream App Server"
  }
}

resource "aws_ssm_parameter" "cloudwatch_config" {
  name  = "AmazonCloudWatch-DreamAppConfig"
  type  = "String"
  value = <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "DreamApp/EC2",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_active"
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF
}

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
    InstanceId = aws_instance.dream-app_server.id
  }
}

output "ec2_public_ip" {
  value = aws_instance.dream-app_server.public_ip
}