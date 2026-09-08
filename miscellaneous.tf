locals {
  # Only used to narrow firewall targets; clusters without an explicit SA fall back to the project default and can't be targeted here.
  cluster_service_accounts = distinct([
    for cluster in values(var.gke_clusters) : cluster.cluster_service_account_email
    if cluster.cluster_service_account_email != null
  ])
}

resource "google_compute_firewall" "fw_healthcheck" {
  name                    = "fw-allow-healthcheck"
  direction               = "INGRESS"
  network                 = data.google_compute_network.vpc.id
  source_ranges           = ["130.211.0.0/22", "35.191.0.0/16"]
  target_service_accounts = length(local.cluster_service_accounts) > 0 ? local.cluster_service_accounts : null
  allow {
    protocol = "tcp"
    ports    = ["8080", "443"]
  }
}

resource "google_compute_firewall" "fw_backends" {
  name      = "surrealdb-fw-allow-backends"
  direction = "INGRESS"
  network   = data.google_compute_network.vpc.id
  source_ranges = distinct([
    for cluster in values(var.gke_clusters) : cluster.proxy_subnet_ip_cidr
  ])
  target_service_accounts = length(local.cluster_service_accounts) > 0 ? local.cluster_service_accounts : null
  allow {
    protocol = "tcp"
    ports    = ["8080", "443"]
  }
}

# resource "google_compute_health_check" "https-health-check" {
#   name = "surrealdb-https-health-check"

#   timeout_sec         = 1
#   check_interval_sec  = 1
#   healthy_threshold   = 1
#   unhealthy_threshold = 2

#   https_health_check {
#     port = "443"
#   }
# }

resource "google_compute_health_check" "http-health-check" {
  name = "surrealdb-http-health-check"

  timeout_sec         = 1
  check_interval_sec  = 1
  healthy_threshold   = 1
  unhealthy_threshold = 2

  http_health_check {
    request_path = "/health"
    port         = "8080"
  }
}
