data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket         = "itay-project-terraform-state"
    key            = "dev/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}

module "eks" {
  source = "../../../modules/compute/eks"

  cluster_name = var.cluster_name

  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  desired_size = var.desired_size
  min_size     = var.min_size
  max_size     = var.max_size

  instance_types = var.instance_types

  public_access_cidrs = var.public_access_cidrs

  tags = var.tags
}

module "iam" {
  source = "../../../modules/security/iam"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  cluster_name      = module.eks.cluster_name

  tags = var.tags
}

resource "local_file" "alb_values_dev" {
  content = templatefile(
    "${path.module}/../../../modules/security/iam/templates/alb-values.yaml.tpl",
    {
      role_arn     = module.iam.alb_controller_role_arn
      cluster_name = module.eks.cluster_name
      region       = var.aws_region
      vpc_id       = data.terraform_remote_state.network.outputs.vpc_id
    }
  )

  filename = "${path.module}/../../../../gitops/infrastructure/alb-controller/values-dev.yaml"
}