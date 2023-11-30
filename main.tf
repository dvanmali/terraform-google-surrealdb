data "google_compute_network" "vpc" {
  name = var.vpc
}

module "gke_clusters" {
  for_each = var.gke_clusters
  source = "./modules/gke_autopilot_cluster"

  key = each.key
  vpc = data.google_compute_network.vpc.id
  vpc_subnet = "surrealdb"
  vpc_subnet_ip = each.value.vpc_subnet_ip # 256 IP addresses (Reserves 10.1.0.0-10.1.0.255)
  region = each.value.region
  node_zones = each.value.node_zones
  master_ipv4_cidr_block = each.value.master_ipv4_cidr_block
  deletion_protection = each.value.deletion_protection

  jump_host_ip = each.value.jump_host_ip
  jump_host_zone = each.value.jump_host_zone
  jump_host_machine = var.jump_host_machine
  jump_host_os = var.jump_host_os
  jump_host_service_account_email = google_service_account.jump_host.email

  providers = {
    google = google
  }
}
