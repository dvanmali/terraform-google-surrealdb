terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}

# Subnet where cluster is configured
resource "google_compute_subnetwork" "subnet" {
  name          = var.vpc_subnet
  network       = var.vpc
  ip_cidr_range = var.vpc_subnet_ip
  region        = var.region
}

# A proxy only subnet needed in each region a cluster is deployed
resource "google_compute_subnetwork" "proxy_subnet" {
  name          = "surrealdb-${var.key}-proxy-only-subnet"
  ip_cidr_range = var.proxy_subnet_ip_cidr
  network       = var.vpc
  region        = google_compute_subnetwork.subnet.region
  purpose       = "GLOBAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# SurrealDB Private Regional Cluster
resource "google_container_cluster" "surreal" {
  name     = "surrealdb-${var.key}"
  location = google_compute_subnetwork.subnet.region
  deletion_protection = var.deletion_protection

  network    = var.vpc
  subnetwork = google_compute_subnetwork.subnet.name

  node_locations = var.node_zones

  enable_autopilot = var.enable_autopilot

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = var.cluster_service_account_email
    }
  }

  addons_config {
    gke_backup_agent_config {
      enabled = var.enable_backup
    }
  }

  master_authorized_networks_config {}


  maintenance_policy {
    daily_maintenance_window {
      start_time = var.daily_maintenance_start_time
    }
  }
}

# Multiple NEGs for each zone in the cluster
resource "google_compute_network_endpoint_group" "neg" {
  for_each = google_container_cluster.surreal.node_locations

  name         = "surrealdb-neg"
  description  = "SurrealDB Zonal NEG"
  network      = var.vpc
  default_port = 8080

  subnetwork   = google_compute_subnetwork.subnet.name
  zone         = each.value
}
