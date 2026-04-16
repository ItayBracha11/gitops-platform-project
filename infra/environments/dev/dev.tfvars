### Providers ###

region = "us-east-1"

### Network VPC Module ###
cidr_block = "10.0.0.0/16"

public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

enable_nat_gateway = true
nat_gateway_count  = 1
environment        = "dev"

tags = {
  Environment = "dev"
  Project     = "gitops-platform"
}

### Compute EKS Module ###

cluster_name = "eks-gitops-demo-dev"

desired_size = 1
min_size     = 1
max_size     = 2

instance_types = ["t3.medium"]

## add public access cidr var