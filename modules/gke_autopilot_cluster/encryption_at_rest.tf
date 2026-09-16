locals {
  encryption_key_ring_name = "${var.encryption_at_rest.key_ring_name}-${var.key}"
  encryption_key_name      = "${var.encryption_at_rest.key_name}-${var.key}"
  pd_service_account_id    = coalesce(var.encryption_at_rest.pd_service_account, "gke-pd-surreal-${var.key}")
  tikv_service_account_id  = coalesce(var.encryption_at_rest.tikv_service_account, "gke-tikv-surreal-${var.key}")
}

resource "google_service_account" "pd" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  account_id   = local.pd_service_account_id
  display_name = "SurrealDB PD Workload Identity service account (${var.key})"
}

resource "google_service_account" "tikv" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  account_id   = local.tikv_service_account_id
  display_name = "SurrealDB TiKV  Workload Identity service account (${var.key})"
}

resource "google_kms_key_ring" "encryption" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  name     = "${var.encryption_at_rest.key_ring_name}-${var.key}"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "encryption" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  name                       = "${var.encryption_at_rest.key_name}-${var.key}"
  key_ring                   = google_kms_key_ring.encryption[0].id
  rotation_period            = var.encryption_at_rest.kms_rotation_period
  destroy_scheduled_duration = var.encryption_at_rest.destroy_scheduled_duration
}

resource "google_kms_crypto_key_iam_member" "pd" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  crypto_key_id = google_kms_crypto_key.encryption[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.pd[0].email}"
}

resource "google_kms_crypto_key_iam_member" "tikv" {
  count = var.encryption_at_rest.enabled ? 1 : 0

  crypto_key_id = google_kms_crypto_key.encryption[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.tikv[0].email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.encryption_at_rest.enabled ? {
    pd   = google_service_account.pd[0].name
    tikv = google_service_account.tikv[0].name
  } : {}

  service_account_id = each.value
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.encryption_at_rest.kubernetes_namespace}/${coalesce(each.key == "pd" ? var.encryption_at_rest.pd_service_account : var.encryption_at_rest.tikv_service_account, each.key == "pd" ? "gke-pd-${var.key}" : "gke-tikv-${var.key}")}]"
}

output "encryption_at_rest_key_id" {
  value       = var.encryption_at_rest.enabled ? google_kms_crypto_key.encryption[0].id : null
  description = "Google Cloud KMS key resource ID for this cluster"
}

output "encryption_at_rest_service_account_emails" {
  value = var.encryption_at_rest.enabled ? {
    pd   = google_service_account.pd[0].email
    tikv = google_service_account.tikv[0].email
  } : null
  description = "Google service account emails used by this cluster through Workload Identity, keyed by workload type"
}

output "encryption_at_rest_pd_service_account_email" {
  value       = var.encryption_at_rest.enabled ? google_service_account.pd[0].email : null
  description = "Google service account email used for the PD workload identity"
}

output "encryption_at_rest_tikv_service_account_email" {
  value       = var.encryption_at_rest.enabled ? google_service_account.tikv[0].email : null
  description = "Google service account email used for the TiKV workload identity"
}