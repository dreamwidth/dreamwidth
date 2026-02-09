# web.tf - Web server task definitions and services

# Map target group references to actual resources
locals {
  target_group_arns = {
    web_stable            = aws_lb_target_group.web_stable.arn
    web_stable_2          = aws_lb_target_group.web_stable_2.arn
    web_canary            = aws_lb_target_group.web_canary.arn
    web_canary_2          = aws_lb_target_group.web_canary_2.arn
    web_shop              = aws_lb_target_group.web_shop.arn
    web_shop_2            = aws_lb_target_group.web_shop_2.arn
    web_unauthenticated   = aws_lb_target_group.web_unauthenticated.arn
    web_unauthenticated_2 = aws_lb_target_group.web_unauthenticated_2.arn
  }
}

# Legacy shared log group - keep until all services have cycled to per-service logs
resource "aws_cloudwatch_log_group" "web_legacy" {
  name              = "/dreamwidth/web"
  retention_in_days = 30
}

# CloudWatch Log Groups - one per web service for easier debugging
resource "aws_cloudwatch_log_group" "web" {
  for_each = local.web_services

  name              = "/dreamwidth/web/${each.key}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "cwagent" {
  name              = "/ecs/ecs-cwagent"
  retention_in_days = 30
}

# Task Definitions for web services
resource "aws_ecs_task_definition" "web" {
  for_each = local.web_services

  family                   = "web-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([
    # CloudWatch Agent sidecar
    {
      name      = "cloudwatch-agent"
      image     = "public.ecr.aws/cloudwatch-agent/cloudwatch-agent:latest"
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/ecs/ecs-cwagent"
          "awslogs-region"        = local.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      mountPoints = [{
        sourceVolume  = "log-share"
        containerPath = "/var/log/apache2"
        readOnly      = true
      }]

      secrets = [{
        name      = "CW_CONFIG_CONTENT"
        valueFrom = "ecs-cwagent"
      }]

      portMappings   = []
      environment    = []
      systemControls = []
      volumesFrom    = []
    },
    # Main web container
    {
      name      = "web"
      image     = "${local.web_image}:latest"
      essential = true
      command   = ["bash", "/opt/startup-prod.sh"]

      linuxParameters = {
        initProcessEnabled = true
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/dreamwidth/web/${each.key}"
          "awslogs-region"        = local.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }

      portMappings = [{
        containerPort = 6081
        hostPort      = 6081
        protocol      = "tcp"
      }]

      mountPoints = [
        {
          sourceVolume  = "dw-config"
          containerPath = "/dw/etc"
          readOnly      = true
        },
        {
          sourceVolume  = "log-share"
          containerPath = "/var/log/apache2"
          readOnly      = false
        }
      ]

      environment    = []
      systemControls = []
      volumesFrom    = []
    }
  ])

  volume {
    name = "dw-config"
    efs_volume_configuration {
      file_system_id     = local.efs_file_system_id
      root_directory     = "/etc"
      transit_encryption = "DISABLED"
    }
  }

  volume {
    name = "log-share"
    # Ephemeral volume for sharing logs between containers
  }
}

# ECS Services for web
resource "aws_ecs_service" "web" {
  for_each = local.web_services

  name            = "web-${each.key}-service"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.web[each.key].arn

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  desired_count                      = 1
  availability_zone_rebalancing      = "ENABLED"
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
    security_groups  = [aws_security_group.webs.id]
    assign_public_ip = true
  }

  # Load balancers - each web service has target groups
  dynamic "load_balancer" {
    for_each = each.value.target_groups
    content {
      target_group_arn = local.target_group_arns[load_balancer.value.tg_ref]
      container_name   = "web"
      container_port   = load_balancer.value.port
    }
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }
}
