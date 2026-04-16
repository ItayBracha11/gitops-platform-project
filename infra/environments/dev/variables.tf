variable "region" {
  description = "AWS region where resources will be deployed"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
}

variable "azs" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to enable NAT Gateway for private subnet internet access"
  type        = bool
}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways to create (typically 1 for dev, 1 per AZ for prod)"
  type        = number
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}

variable "public_access_cidrs" {
  description = "Allowed CIDR blocks for EKS API access"
  type        = list(string)
}

variable "enable_root_app" {
  type    = bool
  default = false
}