terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --------------------------------------------------
# APIs GCP à activer
# --------------------------------------------------
resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
}

resource "google_project_service" "container" {
  project = var.project_id
  service = "container.googleapis.com"
}

resource "google_project_service" "artifactregistry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"
}

# --------------------------------------------------
# VPC custom
# --------------------------------------------------
resource "google_compute_network" "lms_vpc" {
  name                    = "lms-vpc"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.compute
  ]
}

# --------------------------------------------------
# Sous-réseau GKE
# --------------------------------------------------
resource "google_compute_subnetwork" "subnet_gke" {
  name          = "subnet-gke"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.region
  network       = google_compute_network.lms_vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# --------------------------------------------------
# Sous-réseau STAGING
# --------------------------------------------------
resource "google_compute_subnetwork" "subnet_staging" {
  name          = "subnet-staging"
  ip_cidr_range = "10.1.1.0/24"
  region        = var.region
  network       = google_compute_network.lms_vpc.id
}

# --------------------------------------------------
# Sous-réseau PROD
# --------------------------------------------------
resource "google_compute_subnetwork" "subnet_prod" {
  name          = "subnet-prod"
  ip_cidr_range = "10.1.2.0/24"
  region        = var.region
  network       = google_compute_network.lms_vpc.id
}

# --------------------------------------------------
# Cloud Router
# --------------------------------------------------
resource "google_compute_router" "router" {
  name    = "lms-router"
  region  = var.region
  network = google_compute_network.lms_vpc.id
}

# --------------------------------------------------
# Cloud NAT pour le cluster GKE
# --------------------------------------------------
resource "google_compute_router_nat" "nat" {
  name                               = "lms-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet_gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# --------------------------------------------------
# Firewall SSH
# --------------------------------------------------
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.lms_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["app-server"]
}

# --------------------------------------------------
# Firewall WEB
# --------------------------------------------------
resource "google_compute_firewall" "allow_web" {
  name    = "allow-web"
  network = google_compute_network.lms_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["app-server"]
}

# --------------------------------------------------
# Firewall interne
# --------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.lms_vpc.name

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.0.0/8"]
}

# --------------------------------------------------
# Artifact Registry
# --------------------------------------------------
resource "google_artifact_registry_repository" "lms_docker_repo" {
  location      = var.region
  repository_id = "lms-docker"
  description   = "Docker repository for LMS project"
  format        = "DOCKER"

  depends_on = [
    google_project_service.artifactregistry
  ]
}

# --------------------------------------------------
# Cluster GKE
# --------------------------------------------------
resource "google_container_cluster" "lms_cluster" {
  name     = "lms-cluster"
  location = var.zone

  network    = google_compute_network.lms_vpc.id
  subnetwork = google_compute_subnetwork.subnet_gke.id

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  depends_on = [
    google_project_service.container
  ]
}

# --------------------------------------------------
# Node pool GKE
# --------------------------------------------------
resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.lms_cluster.name
  node_count = 2

  node_config {
    machine_type = "e2-standard-2"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    tags = ["gke-node"]
  }
}

# --------------------------------------------------
# VM STAGING
# --------------------------------------------------
resource "google_compute_instance" "lms_staging" {
  name         = "lms-staging"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["app-server"]

  boot_disk {
    initialize_params {
      image = "rocky-linux-cloud/rocky-linux-9-optimized-gcp"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_staging.id

    access_config {
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    dnf update -y
    dnf install -y java-21-openjdk java-21-openjdk-devel httpd mod_ssl wget unzip
  EOT
}

# --------------------------------------------------
# VM PROD
# --------------------------------------------------
resource "google_compute_instance" "lms_prod" {
  name         = "lms-prod"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["app-server"]

  boot_disk {
    initialize_params {
      image = "rocky-linux-cloud/rocky-linux-9-optimized-gcp"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_prod.id

    access_config {
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    dnf update -y
    dnf install -y java-21-openjdk java-21-openjdk-devel httpd mod_ssl wget unzip
  EOT
}