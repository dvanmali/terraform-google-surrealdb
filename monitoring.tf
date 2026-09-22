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

resource "google_secret_manager_secret" "surrealdb_metrics_password" {
  count = local.monitoring_enabled ? 1 : 0

  project   = var.project_id
  secret_id = "surrealdb-metrics-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "surrealdb_metrics_password_accessor" {
  for_each = local.monitoring_enabled ? {
    for key, cluster in var.gke_clusters : key => cluster
    if cluster.surrealdb_service_account_email != null
  } : {}

  project   = var.project_id
  secret_id = google_secret_manager_secret.surrealdb_metrics_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.surrealdb_service_account_email}"
}