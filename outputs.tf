output "vpc_name" {
  value = google_compute_network.lms_vpc.name
}

output "gke_cluster_name" {
  value = google_container_cluster.lms_cluster.name
}

output "artifact_registry_repo" {
  value = google_artifact_registry_repository.lms_docker_repo.name
}

output "staging_vm_name" {
  value = google_compute_instance.lms_staging.name
}

output "prod_vm_name" {
  value = google_compute_instance.lms_prod.name
}

output "staging_vm_public_ip" {
  value = google_compute_instance.lms_staging.network_interface[0].access_config[0].nat_ip
}

output "prod_vm_public_ip" {
  value = google_compute_instance.lms_prod.network_interface[0].access_config[0].nat_ip
}