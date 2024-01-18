terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}

### BACKEND

# Need 1 that points to all its NEGs
resource "google_compute_backend_service" "external" {
  for_each = var.gke_clusters

  name                  = "surrealdb-external-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = var.health_checks

  dynamic backend {
    for_each = each.value.neg
    content {
      group = backend.value.id
      balancing_mode = "RATE"
      max_rate_per_endpoint = var.max_rate_per_endpoint # Target average HTTP request rate for a single endpoint
    }
  }
}

# Need 1 that points to the backend service
resource "google_compute_url_map" "external" {
  name            = "surrealdb-external-url-map"
  default_service = "surrealdb-external-backend-service"
  depends_on = [
    google_compute_backend_service.external
  ]
}

### HTTPS FRONTEND

# Public DNS zone used for issuing SSL Certificates
data "google_dns_managed_zone" "public" {
  name        = var.dns_public
}

# Public DNS zone used for issuing SSL Certificates
resource "google_compute_global_address" "external" {
  name     = "surrealdb-external-ip"
  address_type = "EXTERNAL"
}

# Managed SSL Certificate
resource "google_compute_managed_ssl_certificate" "external" {
  name = "surrealdb-cert"

  managed {
    domains = [trimsuffix(data.google_dns_managed_zone.public.dns_name, ".")]
  }
}

# Maps the certificate on the proxy
resource "google_compute_target_https_proxy" "external" {
  name         = "surrealdb-global-external-https-proxy"
  url_map      = google_compute_url_map.external.id
  ssl_certificates = [
    google_compute_managed_ssl_certificate.external.id
  ]
}

### DNS and Global Forwarding

resource "google_compute_global_forwarding_rule" "external" {
  name        = "surrealdb-external"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target      = google_compute_target_https_proxy.external.id
  ip_protocol = "TCP"
  ip_address  = google_compute_global_address.external.address
  port_range  = 443
}

resource "google_dns_record_set" "external" {
  name         = data.google_dns_managed_zone.public.dns_name
  managed_zone = data.google_dns_managed_zone.public.name
  type         = "A"
  ttl          = 600
  rrdatas      = [google_compute_global_address.external.address]
}
