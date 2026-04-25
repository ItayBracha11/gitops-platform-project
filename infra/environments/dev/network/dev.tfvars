aws_region   = "us-east-1"
cluster_name = "eks-gitops-demo-dev"

cidr_block = "10.0.0.0/16"

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

private_subnet_cidrs = [
  "10.0.11.0/24",
  "10.0.12.0/24"
]

azs = [
  "us-east-1a",
  "us-east-1b"
]

enable_nat_gateway = true
nat_gateway_count  = 1

tags = {
  Project     = "gitops-platform"
  Environment = "dev"
}