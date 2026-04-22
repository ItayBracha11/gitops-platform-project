data "terraform_remote_state" "cluster" {
  backend = "s3"

  config = {
    bucket         = "itay-project-terraform-state"
    key            = "dev/cluster.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket         = "itay-project-terraform-state"
    key            = "dev/platform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}

data "aws_eks_cluster" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.cluster.outputs.cluster_name
}

resource "kubernetes_manifest" "root_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-app"
      namespace = var.argocd_namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        targetRevision = var.target_revision
        path           = var.app_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.argocd_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}