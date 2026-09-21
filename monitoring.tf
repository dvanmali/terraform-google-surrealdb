locals {
  monitoring_enabled = anytrue([
    for cluster in values(var.gke_clusters) : cluster.monitoring.enabled
  ])
}

resource "google_service_account" "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  account_id   = var.monitoring_service_account_id
  display_name = "SurrealDB Prometheus monitoring service account"
}

resource "google_project_iam_member" "monitoring_metric_writer" {
  count = local.monitoring_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.monitoring[0].email}"
}