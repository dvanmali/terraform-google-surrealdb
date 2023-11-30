output "surrealdb_jump_host" {
  value       = google_compute_instance.jump_host.name
  description = "Jump host to perform kubectl and helm commands"
}

output "subnet" {
  value       = google_compute_subnetwork.subnet.id
  description = "Subnet created"
}

output "region" {
  value       = var.region
  description = "Name of the subnet created"
}

output "neg" {
  value = google_compute_network_endpoint_group.neg
  description = "Zone locations where the cluster exists"
}
