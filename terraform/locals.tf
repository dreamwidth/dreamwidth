# locals.tf - Service definitions
#
# Worker definitions are loaded from config/workers.json (single source of truth)
# To add/modify workers, edit that file and run terraform apply.

locals {
  # Load worker definitions from JSON
  workers_config = jsondecode(file("${path.module}/../config/workers.json"))
  workers        = local.workers_config.workers

  # Common configuration
  aws_region     = "us-east-1"
  cluster_name   = "dreamwidth"
  cluster_arn    = "arn:aws:ecs:${local.aws_region}:${local.account_id}:cluster/${local.cluster_name}"
  account_id     = "194396987458"

  # Networking
  subnets = [
    "subnet-52f9530a",
    "subnet-978112e1",
    "subnet-a8d07082",
    "subnet-d4a3d7e9",
  ]

  # EFS configuration
  efs_file_system_id = "fs-f9f3e04d"

  # IAM roles
  execution_role_arn = "arn:aws:iam::${local.account_id}:role/dreamwidth-ecsTaskExecutionRole"
  task_role_arn      = "arn:aws:iam::${local.account_id}:role/dreamwidth-ecsTaskRole"

  # Container images
  worker_image = "ghcr.io/dreamwidth/worker"
  web_image    = "ghcr.io/dreamwidth/web"
  proxy_image  = "194396987458.dkr.ecr.us-east-1.amazonaws.com/dreamwidth/proxy"

  # Security groups
  sg_workers = "sg-051da131f4bd2f503"
  sg_webs    = "sg-04d6101ec5cf7281b"
  sg_proxies = "sg-0783b94b3e412943e"
  sg_alb     = "sg-0609957b"

  # Web service definitions
  web_services = {
    "stable" = {
      cpu               = 1024
      memory            = 6144
      target_group_arns = [
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-stable-tg/e7d3d77ceb1ee71b",
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-stable-2-tg/4aebdaca897e1021",
      ]
    }
    "canary" = {
      cpu               = 1024
      memory            = 6144
      target_group_arns = [
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-canary-tg/55962470111f6226",
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-canary-2-tg/58bba4ac63aa2ac1",
      ]
    }
    "shop" = {
      cpu               = 1024
      memory            = 6144
      target_group_arns = [
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-shop-tg/5d9416d1dc3cb8ef",
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-shop-2-tg/0573939999de3a97",
      ]
    }
    "unauthenticated" = {
      cpu               = 1024
      memory            = 6144
      target_group_arns = [
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-unauthenticated-tg/75c59cc4fa81999e",
        "arn:aws:elasticloadbalancing:us-east-1:194396987458:targetgroup/web-unauthenticated-2-tg/5797063f5a87cffd",
      ]
    }
  }
}
