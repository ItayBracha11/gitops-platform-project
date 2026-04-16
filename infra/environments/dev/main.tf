module "vpc" {
  source = "../../modules/network/vpc"

  cidr_block = var.cidr_block

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs

  enable_nat_gateway = var.enable_nat_gateway
  nat_gateway_count  = var.nat_gateway_count

  tags = var.tags
}

module "eks" {
  source = "../../modules/compute/eks"

  cluster_name = var.cluster_name

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  desired_size = var.desired_size
  min_size     = var.min_size
  max_size     = var.max_size

  instance_types = var.instance_types

  public_access_cidrs = ["3.228.85.221/32"]

  tags = var.tags
}

data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

module "iam" {
  source = "../../modules/security/iam"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  cluster_name = module.eks.cluster_name

  tags = var.tags
}

resource "local_file" "alb_values_dev" {
  content = templatefile(
    "${path.module}/../../modules/security/iam/templates/alb-values.yaml.tpl",
    {
      role_arn     = module.iam.alb_controller_role_arn
      cluster_name = module.eks.cluster_name
      region       = var.aws_region
    }
  )

  filename = "${path.module}/../../../gitops/infrastructure/alb-controller/values-dev.yaml"
}

module "argocd" {
  source = "../../modules/platform/argocd"

  namespace       = "argocd"
  repo_url        = "https://github.com/ItayBracha11/gitops-platform-project.git"
  target_revision = "HEAD"
  app_path        = "gitops/applications/dev"
  enable_root_app = var.enable_root_app

  depends_on = [module.eks]
}