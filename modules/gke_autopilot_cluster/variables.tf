variable "key" {
  type = string
  description = "Key value used when naming the GKE cluster and its associated resources"
}

variable "vpc" {
  type = string
  description = "VPC deployment network name"
}

variable "vpc_subnet" {
  type = string
  description = "Subnet Name"
  default = "surrealdb"
}

variable "vpc_subnet_ip" {
  type = string
  description = "/24 Private CIDR Range for deployment"
}

variable "region" {
  type = string
  description = "Region of the GKE deployment"
}

variable "deletion_protection" {
  type = bool
  description = "Protection this cluster from deletion"
  default = true
}

variable "jump_host_zone" {
  type = string
  description = "Zone Letter to place VMs. Defaults zone a."
  validation {
    condition = length(var.jump_host_zone) == 1
    error_message = "Zone is a single letter such as 'a', 'b', or 'c'"
  }
  default = "a"
}

variable "proxy_subnet_ip_cidr" {
  type = string
  description = "/23 CIDR Proxy Only Subnet"
  default = "10.100.0.0/23" # 512 IP Addresses (Reserves 10.100.0.0-10.100.1.256)
}

variable "master_ipv4_cidr_block" {
  type = string
  description = "Permanent /28 CIDR Block Subnet IP Range"
  default = "10.0.0.0/28" # 16 IP Addresses (Reserves 10.0.0.0-10.0.0.15)
}

variable "jump_host_ip" {
  type = string
  nullable = true
  description = "Jump Host IP (default: auto assigned within subnet)"
  default = null
}

variable "jump_host_machine" {
  type = string
  description = "Jump Host Machine"
  default = "e2-micro"
}

variable "jump_host_os" {
  type = string
  description = "Jump Host Machine Operating system imaged"
  default = "debian-cloud/debian-12-bookworm-v20240701"
}

variable "jump_host_service_account_email" {
  type = string
  description = "Jump Host Service account"
}

variable "node_zones" {
  type = set(string)
  description = "Zones where nodes can exist for the cluster. Run 'gcloud compute zones list' to obtain valid values. We recommend at least 3 zones."
}