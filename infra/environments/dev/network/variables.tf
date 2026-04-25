variable "aws_region" {
  description = "AWS region for the dev network"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for Kubernetes subnet discovery tags"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "azs" {
  description = "Availability zones for subnet placement"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateway routing for private subnets"
  type        = bool
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways to create"
  type        = number
}

variable "tags" {
  description = "Common tags for network resources"
  type        = map(string)
}