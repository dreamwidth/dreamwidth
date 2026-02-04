# security-groups.tf - Security groups for ECS tasks and ALBs

locals {
  vpc_id = "vpc-dd5972b9"
}

# Security group for worker tasks (no inbound, outbound only)
resource "aws_security_group" "workers" {
  name        = "dreamwidth-sg-ecs-task-workers"
  description = "Managed by Terraform"
  vpc_id      = local.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Security group for web tasks
resource "aws_security_group" "webs" {
  name        = "dreamwidth-sg-ecs-task-webs"
  description = "Managed by Terraform"
  vpc_id      = local.vpc_id

  # Varnish/Apache port from ALBs
  ingress {
    from_port       = 6081
    to_port         = 6081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id, "sg-e558ee9d"]
    description     = "HTTP (Varnish/Apache) from prod + LBs"
  }

  # Starman port from ALBs
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id, "sg-e558ee9d"]
    description     = "HTTP (Starman) from prod + LBs"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Security group for proxy tasks
resource "aws_security_group" "proxies" {
  name        = "dreamwidth-sg-ecs-task-proxies"
  description = "Managed by Terraform"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 6250
    to_port         = 6250
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id, "sg-e558ee9d"]
    description     = "HTTP from prod + LBs"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Security group for ALB (public internet access)
# Note: This SG pre-exists with a different name in AWS
resource "aws_security_group" "alb" {
  name        = "dw-public"
  description = "public internet all"
  vpc_id      = local.vpc_id

  lifecycle {
    ignore_changes = [name, description]
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

  tags = {
    Name = "dw-elb"
  }
}
