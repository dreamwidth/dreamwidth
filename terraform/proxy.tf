# proxy.tf - Proxy service task definition and service

# CloudWatch Log Group for proxy
resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/dreamwidth/proxy"
  retention_in_days = 30
}

# Proxy Task Definition
resource "aws_ecs_task_definition" "proxy" {
  family                   = "proxy-stable"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([{
    name      = "proxy"
    image     = "${local.proxy_image}:latest"
    essential = true
    command   = ["bash", "/opt/startup-prod.sh"]

    linuxParameters = {
      initProcessEnabled = true
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-create-group"  = "true"
        "awslogs-group"         = "/dreamwidth/proxy"
        "awslogs-region"        = local.aws_region
        "awslogs-stream-prefix" = "proxy"
      }
    }

    portMappings = [{
      containerPort = 6250
      hostPort      = 6250
      protocol      = "tcp"
    }]

    mountPoints = [{
      sourceVolume  = "dw-config"
      containerPath = "/dw/etc"
      readOnly      = true
    }]

    environment    = []
    volumesFrom    = []
  }])

  volume {
    name = "dw-config"
    efs_volume_configuration {
      file_system_id     = local.efs_file_system_id
      root_directory     = "/etc"
      transit_encryption = "DISABLED"
    }
  }
}

# Proxy ECS Service
resource "aws_ecs_service" "proxy" {
  name            = "proxy-stable-service"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.proxy.arn

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  desired_count                      = 1
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50
  enable_execute_command             = true
  platform_version                   = "LATEST"
  scheduling_strategy                = "REPLICA"
  propagate_tags                     = "NONE"
  health_check_grace_period_seconds  = 0

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = local.subnets
    security_groups  = [aws_security_group.proxies.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = "proxy"
    container_port   = 6250
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }
}
