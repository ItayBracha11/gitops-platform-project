variable "aws_region" {
  description = "AWS region for the dev environment"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateway(s)"
  type        = bool
}

variable "nat_gateway_count" {
  description = "Number of NAT gateways to create"
  type        = number
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "desired_size" {
  description = "Desired node group size"
  type        = number
}

variable "min_size" {
  description = "Minimum node group size"
  type        = number
}

variable "max_size" {
  description = "Maximum node group size"
  type        = number
}

variable "instance_types" {
  description = "EC2 instance types for the node group"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint"
  type        = list(string)
}

variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}