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

variable "vpc" {
  type = string
  description = "VPC deployment network name"
}

variable "max_rate_per_endpoint" {
  type = number
  description = "Number of requests per second for each endpoint connected to the loadbalancer"
  default = 1000000000 # A single Surrealdb can handle millions of connections because each connection is concurrent
}

variable "gke_clusters" {
  type = map(object({
    region = string
    subnet = string
    neg = any
  }))
  description = "Map of all clusters to deploy"
}

variable "health_checks" {
  type = set(string)
  description = "The set of URLs to the HttpHealthCheck or HttpsHealthCheck resource for health checking this BackendService. Currently at most one health check can be specified."
}
