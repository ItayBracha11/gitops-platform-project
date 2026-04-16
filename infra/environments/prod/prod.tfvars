### Providers ###

region = "eu-west-1"

### Network VPC Module ###
cidr_block = "10.1.0.0/16"

public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

enable_nat_gateway = true
nat_gateway_count  = 2
environment        = "prod"

tags = {
  Environment = "prod"
  Project     = "gitops-platform"
}

### Compute EKS Module ###

cluster_name = "eks-gitops-demo-prod"

desired_size = 2
min_size     = 2
max_size     = 5

instance_types = ["t3.large"]