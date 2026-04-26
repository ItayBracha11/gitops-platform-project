module "vpc" {
  source = "../../../modules/network/vpc"

  cidr_block   = var.cidr_block
  cluster_name = var.cluster_name

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs

  enable_nat_gateway = var.enable_nat_gateway
  nat_gateway_count  = var.nat_gateway_count

  tags = var.tags
}