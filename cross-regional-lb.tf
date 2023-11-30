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

### BACKEND

# Need 1 that points to all its NEGs
resource "google_compute_backend_service" "default" {
  for_each = module.gke_clusters

  name                  = "surrealdb-backend-service"
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [
    google_compute_health_check.http-health-check.id
  ]

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
resource "google_compute_url_map" "default" {
  name            = "surrealdb-url-map"
  default_service = "surrealdb-backend-service"
  depends_on = [
    google_compute_backend_service.default
  ]
}

### HTTPS FRONTEND

# Public DNS zone used for issuing SSL Certificates
data "google_dns_managed_zone" "public" {
  name        = var.dns_public
}

# Private DNS zone stores internal IP addresses
resource "google_dns_managed_zone" "private" {
  name        = var.dns_private == null ? "${data.google_dns_managed_zone.public.name}-private" : var.dns_private
  dns_name    = data.google_dns_managed_zone.public.dns_name
  description = "Private DNS zone for ${data.google_dns_managed_zone.public.dns_name} to route internal endpoints."
  visibility = "private"
  private_visibility_config {
    networks {
      network_url = data.google_compute_network.vpc.id
    }
  }
}

resource "google_certificate_manager_dns_authorization" "default" {
  name        = "surrealdb-dns-authorization"
  description = "DNS authorization for surrealdb"
  domain      = trimsuffix(data.google_dns_managed_zone.public.dns_name, ".")
}

# We can delete the CNAME record when the certificate is active
resource "google_dns_record_set" "cname" {
  name         = google_certificate_manager_dns_authorization.default.dns_resource_record.0.name
  managed_zone = data.google_dns_managed_zone.public.name
  type         = google_certificate_manager_dns_authorization.default.dns_resource_record.0.type
  ttl          = 30
  rrdatas      = [google_certificate_manager_dns_authorization.default.dns_resource_record.0.data]
}

resource "google_certificate_manager_certificate" "db_cert" {
  name        = "surrealdb-gilb-cert"
  description = "SurrealDB managed cert"
  scope       = "ALL_REGIONS"

  managed {
    domains = [
      trimsuffix(data.google_dns_managed_zone.public.dns_name, ".")
    ]
    dns_authorizations = [
      google_certificate_manager_dns_authorization.default.id
    ]
  }
}

resource "google_compute_target_https_proxy" "default" {
  name         = "surrealdb-global-https-proxy"
  url_map      = google_compute_url_map.default.id
  certificate_manager_certificates = [
    google_certificate_manager_certificate.db_cert.id
  ]
}

### Regional Cluster Static IPs

resource "google_compute_address" "regional-frontend" {
  for_each     = module.gke_clusters

  name         = "surrealdb-${each.key}-ip"
  address_type = "INTERNAL"
  region       = each.value.region
  subnetwork   = each.value.subnet
  description  = "Static Frontend IP address for the SurrealDB cluster ${each.key} located in ${each.value.region}"
}

resource "google_compute_global_forwarding_rule" "gil7_forwarding_rule" {
  for_each     = google_compute_address.regional-frontend

  name        = format("surrealdb-gil7-to-%s", trimprefix(each.value.name, "surrealdb-"))
  load_balancing_scheme = "INTERNAL_MANAGED"
  network     = data.google_compute_network.vpc.id
  subnetwork  = each.value.subnetwork
  target      = google_compute_target_https_proxy.default.id
  ip_protocol = "TCP"
  ip_address  = each.value.address
  port_range  = 443
}

resource "google_dns_record_set" "geo_route" {
  for_each = google_compute_address.regional-frontend

  name         = data.google_dns_managed_zone.public.dns_name
  managed_zone = google_dns_managed_zone.private.name
  type         = "A"
  ttl          = 30

  routing_policy {
    geo {
      location = each.value.region
      rrdatas  = [ each.value.address ]
    }
  }
}