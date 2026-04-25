aws_region   = "us-east-1"
cluster_name = "eks-gitops-demo-dev"

desired_size = 1
min_size     = 1
max_size     = 2

instance_types = ["t3.small"]

tags = {
  Project     = "gitops-platform"
  Environment = "dev"
}