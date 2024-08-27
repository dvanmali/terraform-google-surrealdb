locals {
  project_id="<PROJECT_ID>"
  vpc="<VPC_NAME>"

  enable_external_global_lb = false
  enable_internal_cross_regional_lb = true

  # NOTE: All CIDR ranges can be changed, they are only provided as Quickstart
  gke_clusters = {
    "<REGION>-1" = {
      region = "<REGION>"
      vpc_subnet_ip = "10.1.0.0/24"
      proxy_subnet_ip_cidr = "10.100.0.0/23"
      node_zones = ["<REGION>-a", "<REGION>-b", "<REGION>-c" ] # Use 'gcloud compute zones list'
      master_ipv4_cidr_block = "10.0.0.0/28" # CIDR block for the cluster control plane
      deletion_protection = true # (Optional) default is true
      enable_autopilot = true
      # cluster_service_account_email = "" (Recommended) this value should be filled out before cluster creation
    }
  }

  jump_host_iap = {
    "me" = {
      members=["user:<email>"]
      # condition={
      #   title="Day access"
      #   expression="request.time < timestamp('2023-11-20T00:00:00.000Z')"
      # }
    }
  }
}

provider "google" {
  project = local.project_id
}

module "gke-surrealdb" {
  source = "dvanmali/surrealdb/google"
  version = "1.2.0"

  project_id = local.project_id
  vpc = local.vpc
  gke_clusters = local.gke_clusters
  jump_host_iap = local.jump_host_iap

  enable_external_global_lb = local.enable_external_global_lb
  enable_internal_cross_regional_lb = local.enable_internal_cross_regional_lb

  providers = {
    google = google
  }
}