resource "google_compute_firewall" "fw_healthcheck" {
  name          = "fw-allow-healthcheck"
  direction     = "INGRESS"
  network       = data.google_compute_network.vpc.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  # target_tags = ["load-balanced-backend"]
  allow {
    protocol = "tcp"
    ports    = ["8080", "443"]
  }
}

resource "google_compute_firewall" "fw_backends" {
  name          = "surrealdb-fw-allow-backends"
  direction     = "INGRESS"
  network       = data.google_compute_network.vpc.id
  source_ranges = ["10.100.0.0/23"]
  # target_tags = ["load-balanced-backend"]
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
    port = "8080"
  }
}
