resource "google_service_account" "encryption" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  account_id   = "${var.encryption_at_rest.service_account_id}-${var.key}"
  display_name = "SurrealDB TiDB encryption at rest (${var.key})"
}

resource "google_kms_key_ring" "encryption" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  name     = "${var.encryption_at_rest.key_ring_name}-${var.key}"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "encryption" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  name            = "${var.encryption_at_rest.key_name}-${var.key}"
  key_ring        = google_kms_key_ring.encryption[0].id
  rotation_period = var.encryption_at_rest.kms_rotation_period
}

resource "google_kms_crypto_key_iam_member" "encryption" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  crypto_key_id = google_kms_crypto_key.encryption[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.encryption[0].email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.encryption_at_rest.enabled ? {
    pd   = coalesce(var.encryption_at_rest.pd_service_account, "gke-pd-${var.key}")
    tikv = coalesce(var.encryption_at_rest.tikv_service_account, "gke-tikv-${var.key}")
  } : {}

  service_account_id = google_service_account.encryption[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.encryption_at_rest.kubernetes_namespace}/${each.value}]"
}

output "encryption_at_rest_key_id" {
  value       = var.encryption_at_rest.enabled ? google_kms_crypto_key.encryption[0].id : null
  description = "Google Cloud KMS key resource ID for this cluster"
}

output "encryption_at_rest_service_account_email" {
  value       = var.encryption_at_rest.enabled ? google_service_account.encryption[0].email : null
  description = "Google service account used by this cluster through Workload Identity"
}