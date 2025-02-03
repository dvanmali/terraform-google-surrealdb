variable "project_id" {
  type = string
  description = "Project where resources are constructed"
}

variable "vpc" {
  type = string
  description = "VPC deployment network name"
}

variable "enable_external_global_lb" {
  type = bool
  description = "Enable an externally accessible global load balancer"
  default = false
}

variable "enable_internal_cross_regional_lb" {
  type = bool
  description = "Enable a cross-regional internal load balancer"
  default = true
}

variable "vpc_auto_create_subnetworks" {
  type = bool
  description = "VPC deployment network name"
  default = true # An auto-VPC network can be converted into custom networks but not vice-versa
}

variable "dns_public" {
  type = string
  description = "Name for the existing public DNS zone"
  default = "surrealdb"
}

variable "dns_private" {
  type = string
  description = "(Optional) Name for the private DNS zone to be created"
  nullable = true
  default = null
}

variable "max_rate_per_endpoint" {
  type = number
  description = "Number of requests per second for each endpoint connected to the loadbalancer"
  default = 1000000000 # A single Surrealdb can handle millions of connections because each connection is concurrent
}

variable "jump_host_iap" {
  type = map(object({
    members = optional(set(string))
    condition = optional(object({
      title = string
      description = optional(string)
      expression = string
    }))
  }))
  description = "Map of members allowed to use the IAP Tunnel. Key is unused but must be unique. (default: project owner). See https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/iap_tunnel_iam#member/members for potential values."
  default = {
    "projectOwner": {}
  }
}

variable "gke_clusters" {
  type = map(object({
    region = string
    vpc_subnet_ip = string # 256 IP addresses (Reserves 10.1.0.0-10.1.0.255)
    proxy_subnet_ip_cidr = string # /23 CIDR Recommended
    jump_host_zone = optional(string, "a")
    node_zones = set(string)
    master_ipv4_cidr_block = string
    jump_host_ip = optional(string)
    deletion_protection = optional(bool)
    enable_autopilot = optional(bool)
    enable_backup = optional(bool) # Recommended in prod
    daily_maintenance_policy = optional(string) # defaults midnight
    cluster_service_account_email = optional(string)
  }))
  description = "Map of all clusters to deploy"
}

variable "jump_host_machine" {
  type = string
  description = "Jump Host Machine"
  default = "e2-micro"
}

variable "jump_host_os" {
  type = string
  description = "Jump Host Machine Operating system imaged"
  default = "debian-cloud/debian-12-bookworm-v20250113"
}