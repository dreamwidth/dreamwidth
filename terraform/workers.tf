# workers.tf - Worker task definitions and services
#
# All workers are created from the local.workers map using for_each.
# To add a new worker, add it to locals.tf and run terraform apply.

# Legacy shared log group - keep until all services are migrated to per-worker logs
resource "aws_cloudwatch_log_group" "worker_legacy" {
  name              = "/dreamwidth/worker"
  retention_in_days = 30
}

# CloudWatch Log Groups - one per worker for easier debugging
resource "aws_cloudwatch_log_group" "worker" {
  for_each = local.workers

  name              = "/dreamwidth/worker/${each.key}"
  retention_in_days = 30
}

# Task Definitions
resource "aws_ecs_task_definition" "worker" {
  for_each = local.workers

  family                   = "worker-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${local.worker_image}:latest"
    essential = true
    command   = ["bash", "/opt/startup-prod.sh", "bin/worker/${each.key}", "-v"]

    linuxParameters = {
      initProcessEnabled = true
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-create-group"  = "true"
        "awslogs-group"         = "/dreamwidth/worker/${each.key}"
        "awslogs-region"        = local.aws_region
        "awslogs-stream-prefix" = each.key
      }
    }

    mountPoints = [{
      sourceVolume  = "dw-config"
      containerPath = "/dw/etc"
      readOnly      = true
    }]

    portMappings   = []
    environment    = []
    systemControls = []
    volumesFrom    = []
  }])

  volume {
    name = "dw-config"
    efs_volume_configuration {
      file_system_id     = local.efs_file_system_id
      root_directory     = "/etc-workers"
      transit_encryption = "DISABLED"
    }
  }
}

# ECS Services
resource "aws_ecs_service" "worker" {
  for_each = local.workers

  name            = "worker-${each.key}-service"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.worker[each.key].arn

  # Let scaling manage desired_count
  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  desired_count                 = 1
  availability_zone_rebalancing = "ENABLED"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50
  enable_execute_command             = true
  platform_version                   = "LATEST"
  scheduling_strategy                = "REPLICA"
  propagate_tags                     = "NONE"

  # TODO: After migration, change critical workers to FARGATE (non-spot)
  # For now, keep all on FARGATE_SPOT to avoid service replacement
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = local.subnets
    security_groups  = [aws_security_group.workers.id]
    assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }
}
