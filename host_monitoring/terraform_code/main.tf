provider "aws" {
  region     = "us-west-2"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_session_token
}

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_session_token" {}

variable "observe_token" {}
variable "observe_url" {}
variable "key_pair_name" {
  default = "observe-key-pair"
}
variable "key_pair_public_key_path" {
  default = "/Users/jay.dave/code/field_sandbox/host_monitoring/terraform/observe_key_pair.pub"
}
variable "key_pair_private_key_path" {
  default = "/Users/jay.dave/code/field_sandbox/host_monitoring/terraform/observe_key_pair"
}

resource "aws_key_pair" "observe_key_pair" {
  key_name   = var.key_pair_name
  public_key = file(var.key_pair_public_key_path)
}

resource "aws_instance" "observe_agent" {
  ami           = "ami-0acb9a8339ab465bd" # Updated AMI ID for Amazon Linux 2 in us-west-2
  instance_type = "t2.micro"
  key_name      = aws_key_pair.observe_key_pair.key_name

  user_data = <<-EOF
              #!/bin/bash
              echo '[fury]
              name=Gemfury Private Repo
              baseurl=https://yum.fury.io/observeinc/
              enabled=1
              gpgcheck=0' | sudo tee /etc/yum.repos.d/fury.repo

              sudo yum install -y observe-agent

              sudo observe-agent init-config \
              --token ${var.observe_token} \
              --observe_url ${var.observe_url} \
              --host_monitoring.enabled=true \
              --host_monitoring.logs.enabled=true \
              --host_monitoring.metrics.enabled=true

              sudo systemctl enable --now observe-agent
              EOF

  tags = {
    Name = "ObserveAgentInstance"
  }
}

resource "aws_security_group" "observe_sg" {
  name        = "observe-sg"
  description = "Security group for Observe agent"
  
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

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "observe_role" {
  name = "observe-role"

  assume_role_policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
    EOF
}

resource "aws_iam_instance_profile" "observe_instance_profile" {
  name = "observe-instance-profile"
  role = aws_iam_role.observe_role.name
}

resource "aws_iam_role_policy" "observe_policy" {
  name = "observe-policy"
  role = aws_iam_role.observe_role.id

  policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "cloudwatch:PutMetricData",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource": "*"
        }
      ]
    }
    EOF
}

output "instance_public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.observe_agent.public_ip
}

output "key_pair_private_key_path" {
  description = "The private key path to connect to the EC2 instance"
  value       = var.key_pair_private_key_path
}
