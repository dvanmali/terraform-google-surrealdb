variable "dns_public" {
  type        = string
  description = "Name for the existing public DNS zone"
  default     = "surrealdb"
}

variable "balancing_mode" {
  type        = string
  description = "Backend balancing mode used for all load balancer backends. NEGs support RATE or CONNECTION; UTILIZATION is not supported."
  default     = "RATE"
  validation {
    condition     = contains(["RATE", "CONNECTION"], var.balancing_mode)
    error_message = "balancing_mode must be one of RATE or CONNECTION for NEG-based backends."
  }
}

variable "max_utilization" {
  type        = number
  description = "Target utilization for each completed backend endpoint when balancing_mode is UTILIZATION"
  default     = 0.8
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