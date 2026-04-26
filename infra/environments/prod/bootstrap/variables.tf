variable "aws_region" {
  description = "AWS region for the prod environment"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "repo_url" {
  description = "Git repo URL for the ArgoCD root app"
  type        = string
}

variable "target_revision" {
  description = "Git revision for the ArgoCD root app"
  type        = string
  default     = "HEAD"
}

variable "app_path" {
  description = "Path to ArgoCD applications directory"
  type        = string
}