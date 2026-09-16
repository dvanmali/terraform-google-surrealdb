output "encryption_at_rest_key_ids" {
  value       = { for key, cluster in module.gke_clusters : key => cluster.encryption_at_rest_key_id }
  description = "Google Cloud KMS key resource IDs keyed by GKE cluster name"
}

output "encryption_at_rest_service_account_emails" {
  value = {
    for key, cluster in module.gke_clusters : key => {
      pd   = cluster.encryption_at_rest_pd_service_account_email
      tikv = cluster.encryption_at_rest_tikv_service_account_email
    }
  }
  description = "Google service account emails used for PD and TiKV encryption at rest, keyed by GKE cluster name"
}

output "encryption_at_rest_service_account_email" {
  value       = { for key, cluster in module.gke_clusters : key => cluster.encryption_at_rest_pd_service_account_email }
  description = "Backward-compatible alias for the PD service account used for encryption at rest"
}
