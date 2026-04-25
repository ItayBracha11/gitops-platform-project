variable "aws_region" {
  description = "AWS region for the dev cluster"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
}

variable "min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
}

variable "instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint"
  type        = list(string)
}

variable "tags" {
  description = "Common tags for cluster resources"
  type        = map(string)
}