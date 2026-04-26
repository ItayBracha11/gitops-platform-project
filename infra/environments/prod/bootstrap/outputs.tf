output "root_application_name" {
  value = kubernetes_manifest.root_application.object.metadata.name
}