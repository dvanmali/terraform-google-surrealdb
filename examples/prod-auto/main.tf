locals {
  project_id = "<PROJECT_ID>"
  vpc        = "<VPC_NAME>"

  enable_external_global_lb         = true
  enable_internal_cross_regional_lb = false

  # NOTE: All CIDR ranges can be changed, they are only provided as Quickstart
  gke_clusters = {
    "<REGION>-1" = {
      region                    = "<REGION>"
      vpc_subnet_ip             = "10.1.0.0/24"
      proxy_subnet_ip_cidr      = "10.100.0.0/23"
      node_zones                = ["<REGION>-a", "<REGION>-b", "<REGION>-c"] # Use 'gcloud compute zones list'
      master_ipv4_cidr_block    = "10.0.0.0/28"                              # CIDR block for the cluster control plane
      deletion_protection       = true                                       # (Optional) default is true
      enable_autopilot          = true
      enable_managed_prometheus = true
      encryption_at_rest = {
        enabled = true
      }

      ## Important production variables
      cluster_service_account_email = "gke-surreal-cluster@<PROJECT_ID>.iam.gserviceaccount.com" # Fill out before cluster creation (see [README](../../README.md#iam)) (can be same for all clusters)
      enable_vertical_scaling       = true                                                       # Enable vertical pod autoscaling
      enable_backup                 = true                                                       # Backup plan added separately
      daily_maintenance_start_time  = "00:00"
      monitoring = {
        enabled = true
      }
    }
  }

  jump_host_iap = {
    "me" = {
      members = ["user:<email>"]
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
  source  = "dvanmali/surrealdb/google"
  version = "2.0.0-beta.2"

  project_id    = local.project_id
  vpc           = local.vpc
  gke_clusters  = local.gke_clusters
  jump_host_iap = local.jump_host_iap

  enable_external_global_lb         = local.enable_external_global_lb
  enable_internal_cross_regional_lb = local.enable_internal_cross_regional_lb

  providers = {
    google = google
  }
}

output "encryption_at_rest_key_ids" {
  value       = module.gke-surrealdb.encryption_at_rest_key_ids
  description = "Google Cloud KMS key resource IDs keyed by GKE cluster name"
}

output "encryption_at_rest_service_account_emails" {
  value       = module.gke-surrealdb.encryption_at_rest_service_account_emails
  description = "Google service account emails used for PD and TiKV encryption at rest, keyed by GKE cluster name"
}

output "monitoring_service_account_email" {
  value       = module.gke-surrealdb.monitoring_service_account_email
  description = "Shared Google service account email used for Prometheus monitoring across all clusters"
}