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
  # NOTE: target_groups uses "tg_ref" to reference resources defined in load-balancing.tf
  # The actual ARNs are resolved in web.tf using the target_group_refs local
  web_services = {
    "stable" = {
      cpu           = 1024
      memory        = 6144
      target_groups = [
        { tg_ref = "web_stable", port = 6081 },
        { tg_ref = "web_stable_2", port = 6081 },  # TODO: change to 8080 when upgraded to web22
      ]
    }
    "canary" = {
      cpu           = 1024
      memory        = 6144
      target_groups = [
        { tg_ref = "web_canary", port = 6081 },
        { tg_ref = "web_canary_2", port = 8080 },
      ]
    }
    "shop" = {
      cpu           = 1024
      memory        = 6144
      target_groups = [
        { tg_ref = "web_shop", port = 6081 },
        { tg_ref = "web_shop_2", port = 8080 },
      ]
    }
    "unauthenticated" = {
      cpu           = 1024
      memory        = 6144
      target_groups = [
        { tg_ref = "web_unauthenticated", port = 6081 },
        { tg_ref = "web_unauthenticated_2", port = 8080 },
      ]
    }
  }
}
