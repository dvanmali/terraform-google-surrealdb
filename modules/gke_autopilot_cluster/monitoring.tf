resource "google_service_account_iam_member" "monitoring_workload_identity" {
  count = var.monitoring.enabled ? 1 : 0

  service_account_id = var.monitoring.service_account_name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.monitoring.kubernetes_namespace}/${var.monitoring.kubernetes_service_account}]"
}

output "monitoring_service_account_email" {
  value       = var.monitoring.enabled ? var.monitoring.service_account_email : null
  description = "Google service account email used for Prometheus monitoring through Workload Identity"
}