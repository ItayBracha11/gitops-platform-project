aws_region   = "eu-west-1"
cluster_name = "eks-gitops-demo-prod"

cidr_block = "10.1.0.0/16"

public_subnet_cidrs = [
  "10.1.1.0/24",
  "10.1.2.0/24"
]

private_subnet_cidrs = [
  "10.1.11.0/24",
  "10.1.12.0/24"
]

azs = [
  "eu-west-1a",
  "eu-west-1b"
]

enable_nat_gateway = true
nat_gateway_count  = 1

tags = {
  Project     = "gitops-platform"
  Environment = "prod"
}