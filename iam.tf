// Generate a custom role for getting random bytes applied at the project iam level
locals {
  crypto_get_random_bytes_service_accounts = merge([
    for cluster_name, cluster in module.gke_clusters : {
      "${cluster_name}-pd"   = cluster.encryption_at_rest_pd_service_account_email
      "${cluster_name}-tikv" = cluster.encryption_at_rest_tikv_service_account_email
    }
  ]...)
}

resource "google_project_iam_custom_role" "crypto_get_random_bytes" {
  project     = var.project_id
  role_id     = var.kms_crypto_get_random_bytes_role.id
  title       = var.kms_crypto_get_random_bytes_role.name
  description = var.kms_crypto_get_random_bytes_role.description
  stage       = var.kms_crypto_get_random_bytes_role.stage

  permissions = [
    "cloudkms.locations.generateRandomBytes",
  ]
}

resource "google_project_iam_member" "crypto_get_random_bytes" {
  for_each = {
    for key, email in local.crypto_get_random_bytes_service_accounts : key => email
    if email != null
  }

  project = var.project_id
  role    = google_project_iam_custom_role.crypto_get_random_bytes.id
  member  = "serviceAccount:${each.value}"
}
