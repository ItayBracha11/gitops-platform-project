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

variable "repo_url" {
  type = string
}

variable "target_revision" {
  type    = string
  default = "HEAD"
}

variable "app_path" {
  type = string
}

variable "enable_root_app" {
  type    = bool
  default = false
}