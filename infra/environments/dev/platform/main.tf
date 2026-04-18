data "terraform_remote_state" "cluster" {
  backend = "s3"

  config = {
    bucket         = "itay-project-terraform-state"
    key            = "dev/cluster.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

module "argocd" {
  source = "../../../modules/platform/argocd"

  namespace       = var.argocd_namespace
  chart_version   = var.argocd_chart_version
  create_namespace = true
}