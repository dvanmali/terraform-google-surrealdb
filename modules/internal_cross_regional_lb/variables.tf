variable "dns_public" {
  type        = string
  description = "Name for the existing public DNS zone"
  default     = "surrealdb"
}

variable "dns_private" {
  type        = string
  description = "(Optional) Name for the private DNS zone to be created"
  nullable    = true
  default     = null
}

variable "vpc" {
  type        = string
  description = "VPC deployment network name"
}

variable "balancing_mode" {
  type        = string
  description = "Backend balancing mode used for all load balancer backends"
  default     = "UTILIZATION"
  validation {
    condition     = contains(["UTILIZATION", "RATE", "CONNECTION"], var.balancing_mode)
    error_message = "balancing_mode must be one of UTILIZATION, RATE, or CONNECTION."
  }
}

variable "max_utilization" {
  type        = number
  description = "Target utilization for each completed backend endpoint when balancing_mode is UTILIZATION"
  default     = 0.7
  validation {
    condition     = var.max_utilization > 0 && var.max_utilization <= 1
    error_message = "max_utilization must be greater than zero and less than or equal to 1."
  }
}

variable "max_rate_per_endpoint" {
  type        = number
  description = "Number of requests per second for each endpoint when balancing_mode is RATE"
  default     = 100
  validation {
    condition     = var.max_rate_per_endpoint > 0
    error_message = "max_rate_per_endpoint must be greater than zero."
  }
}

variable "gke_clusters" {
  type = map(object({
    region = string
    subnet = string
    neg    = any
  }))
  description = "Map of all clusters to deploy"
}

variable "health_checks" {
  type        = set(string)
  description = "The set of URLs to the HttpHealthCheck or HttpsHealthCheck resource for health checking this BackendService. Currently at most one health check can be specified."
}
