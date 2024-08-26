##########################################
# Shared ECS Cluster for Services
##########################################

resource "aws_ecs_cluster" "perforce_cluster" {
  name = "perforce-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "providers" {
  cluster_name = aws_ecs_cluster.perforce_cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

##########################################
# Perforce Helix Core
##########################################

module "perforce_helix_core" {
  source             = "../../helix-core"
  vpc_id             = aws_vpc.perforce_vpc.id
  server_type        = "p4d_commit"
  instance_subnet_id = aws_subnet.private_subnets[0].id
  instance_type      = "c6in.large"

  storage_type         = "EBS"
  depot_volume_size    = 64
  metadata_volume_size = 32
  logs_volume_size     = 32

  FQDN = "core.${aws_route53_zone.helix.name}"

  helix_authentication_service_url = "https://${aws_route53_record.helix_authentication_service.name}"
}

##########################################
# Perforce Helix Authentication Service
##########################################

module "perforce_helix_authentication_service" {
  source                                   = "../../helix-authentication-service"
  vpc_id                                   = aws_vpc.perforce_vpc.id
  cluster_name                             = aws_ecs_cluster.perforce_cluster.name
  helix_authentication_service_alb_subnets = aws_subnet.public_subnets[*].id
  helix_authentication_service_subnets     = aws_subnet.private_subnets[*].id
  certificate_arn                          = aws_acm_certificate.helix.arn

  internal = false

  enable_web_based_administration = true
  fqdn                            = "https://auth.${aws_route53_zone.helix.name}"

  depends_on = [aws_ecs_cluster.perforce_cluster, aws_acm_certificate_validation.helix]
}

##########################################
# Perforce Helix Swarm
##########################################

module "perforce_helix_swarm" {
  source                      = "../../helix-swarm"
  vpc_id                      = aws_vpc.perforce_vpc.id
  cluster_name                = aws_ecs_cluster.perforce_cluster.name
  helix_swarm_alb_subnets     = aws_subnet.public_subnets[*].id
  helix_swarm_service_subnets = aws_subnet.private_subnets[*].id
  certificate_arn             = aws_acm_certificate.helix.arn

  internal = false

  p4d_port                    = "ssl:${aws_route53_record.perforce_helix_core.name}:1666"
  enable_elastic_filesystem   = false
  p4d_super_user_arn          = module.perforce_helix_core.helix_core_super_user_username_secret_arn
  p4d_super_user_password_arn = module.perforce_helix_core.helix_core_super_user_password_secret_arn
  p4d_swarm_user_arn          = module.perforce_helix_core.helix_core_super_user_username_secret_arn
  p4d_swarm_password_arn      = module.perforce_helix_core.helix_core_super_user_password_secret_arn

  fqdn = "swarm.${aws_route53_zone.helix.name}"

  depends_on = [aws_ecs_cluster.perforce_cluster]
}
