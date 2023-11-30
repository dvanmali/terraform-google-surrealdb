# Jump Host Service Account and Permissions
resource "google_service_account" "jump_host" {
  account_id  = "gce-surrealdb-jump-host"
  description = "SurrealDB Jump Host Service Account attached to Compute Engine Instance"
}

# resource "google_project_iam_member" "jump_host" {
#   project = var.project_id
#   role = "roles/container.developer"
#   member = "serviceAccount:${google_service_account.jump_host.email}"
# }

resource "google_compute_firewall" "iap_jump_host_rules" {
  name    = "iap-surrealdb-jump-host-allow-ingress"
  network = data.google_compute_network.vpc.name

  # Enables IAP Access to the SSH port for VMs using the jump host service account
  allow {
    protocol = "tcp"
    ports    = [ "22" ]
  }
  target_service_accounts = [ google_service_account.jump_host.email ]
  source_ranges = [ "35.235.240.0/20" ]
}

resource "google_iap_tunnel_iam_binding" "jump_host_tunnel" {
  for_each = var.jump_host_iap
  role    = "roles/iap.tunnelResourceAccessor"
  members = each.value.members != null ? each.value.members : [
    "projectOwner:${var.project_id}"
  ]

  dynamic "condition" {
    for_each = each.value.condition != null ? [each.value.condition] : []
    content {
      title       = condition.value.title
      description = condition.value.description
      expression  = condition.value.expression
    }
  }
}