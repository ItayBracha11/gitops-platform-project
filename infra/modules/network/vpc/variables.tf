variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "nat_gateway_count" {
  type    = number
  default = 1
}