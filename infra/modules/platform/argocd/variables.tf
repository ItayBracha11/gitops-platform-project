variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  type    = string
  default = "7.7.16"
}

variable "create_namespace" {
  type    = bool
  default = true
}