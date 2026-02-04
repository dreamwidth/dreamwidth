# cluster.tf - ECS Cluster

resource "aws_ecs_cluster" "dreamwidth" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
