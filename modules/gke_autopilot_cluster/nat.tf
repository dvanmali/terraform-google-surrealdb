# NAT router that enables the private cluster to talk to resources on the Internet (such as Docker)
resource "google_compute_router" "nat_router" {
  name    = "${google_container_cluster.surreal.name}-nat-router"
  region  = google_compute_subnetwork.subnet.region
  network = var.vpc
}

resource "google_compute_router_nat" "nat" {
  name = "${google_container_cluster.surreal.name}-nat"
  router = google_compute_router.nat_router.name
  region = google_compute_router.nat_router.region
  nat_ip_allocate_option = "AUTO_ONLY"

  # Accepts only IPs in the provided subnet name
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS" 
  subnetwork {
    name                    = google_compute_subnetwork.subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
