# Jump Host used to access the private GKE control plane
resource "google_compute_address" "gke_control_plane_jump_host" {
  name         = "${google_container_cluster.surreal.name}-jump-host-ip"
  address_type = "INTERNAL"
  region       = google_compute_subnetwork.subnet.region
  subnetwork   = google_compute_subnetwork.subnet.name
  address      = var.jump_host_ip
  description  = "Internal IP address for the SurrealDB control plane jump host for cluster ${google_container_cluster.surreal.name} located in ${google_compute_subnetwork.subnet.region}"
}

resource "google_compute_instance" "jump_host" {
  name = "${google_container_cluster.surreal.name}-jump-host"
  machine_type = var.jump_host_machine
  zone = "${google_compute_subnetwork.subnet.region}-${var.jump_host_zone}"
  service_account {
    email = var.jump_host_service_account_email
    scopes = [ "cloud-platform" ]
  }
  scheduling {
    provisioning_model = "SPOT"
    preemptible = true # Required if spot
    automatic_restart = false # Required if spot
    instance_termination_action = "DELETE"
  }
  network_interface {
    network = var.vpc
    subnetwork = google_compute_subnetwork.subnet.name
    network_ip = google_compute_address.gke_control_plane_jump_host.address
  }
  boot_disk {
    initialize_params {
      image = var.jump_host_os
    }
  }
}
