# iam.tf - IAM roles for ECS tasks

# Task Role - permissions for the running containers
resource "aws_iam_role" "task_role" {
  name                 = "dreamwidth-ecsTaskRole"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = ""
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Execution Role - permissions for ECS to pull images, write logs, etc.
resource "aws_iam_role" "execution_role" {
  name                 = "dreamwidth-ecsTaskExecutionRole"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = ""
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# Note: IAM policies attached to these roles are managed separately
# (likely via AWS console or other IaC). To fully manage them here,
# add aws_iam_role_policy_attachment resources.
