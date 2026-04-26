aws_region   = "eu-west-1"
cluster_name = "eks-gitops-demo-prod"

desired_size = 2
min_size     = 2
max_size     = 5

instance_types = ["t3.large"]

tags = {
  Project     = "gitops-platform"
  Environment = "prod"
}