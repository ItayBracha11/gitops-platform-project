aws_region = "us-east-1"

cidr_block = "10.0.0.0/16"

public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

azs = ["us-east-1a", "us-east-1b"]

enable_nat_gateway = true
nat_gateway_count  = 1

cluster_name = "eks-gitops-demo-dev"

desired_size = 1
min_size     = 1
max_size     = 2

instance_types = ["t3.medium"]

tags = {
  Environment = "dev"
  Project     = "gitops-platform"
}