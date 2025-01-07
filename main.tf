data "google_compute_network" "vpc" {
  name = var.vpc
}

data "google_dns_managed_zone" "public" {
  name = var.dns_public
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
  enable_autopilot = each.value.enable_autopilot
  enable_backup = each.value.enable_backup
  cluster_service_account_email = each.value.cluster_service_account_email

  jump_host_ip = each.value.jump_host_ip
  jump_host_zone = each.value.jump_host_zone
  jump_host_machine = var.jump_host_machine
  jump_host_os = var.jump_host_os
  jump_host_service_account_email = google_service_account.jump_host.email

  providers = {
    google = google
  }
}

module "external_global_lb" {
  count = var.enable_external_global_lb ? 1 : 0
  source = "./modules/external_global_lb"

  gke_clusters = module.gke_clusters
  health_checks = [ google_compute_health_check.http-health-check.id ]
  dns_public = var.dns_public

  providers = {
    google = google
  }
}

module "internal_cross_regional_lb" {
  count = var.enable_internal_cross_regional_lb ? 1 : 0
  source = "./modules/internal_cross_regional_lb"

  gke_clusters = module.gke_clusters
  health_checks = [ google_compute_health_check.http-health-check.id ]
  vpc = data.google_compute_network.vpc.name

  dns_public = var.dns_public
  dns_private = var.dns_private == null ? "${data.google_dns_managed_zone.public.name}-private" : var.dns_private

  providers = {
    google = google
  }
}