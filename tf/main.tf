locals {
  cluster_id = "up-${terraform.workspace}"
}

terraform {
  required_version = "= 0.11.10"

  // This backend uses Customer Supplied Encryption keys to encrypt state in GCS.
  // The GOOGLE_ENCRYPTION_KEY environment variable must be set to the same key
  // used to create a workspace in order to use it.
  backend "gcs" {
    bucket = "up-state"
    prefix = "gke"
  }
}

provider "google-beta" {
  project = "${var.gcp_project}"
  region  = "${var.gcp_region}"

  version = "1.19"
}

data "google_client_config" "current" {}

// TODO(negz): Use one service account per node pool?
resource "google_service_account" "account" {
  project      = "${var.gcp_project}"
  account_id   = "${local.cluster_id}"
  display_name = "${local.cluster_id}"
}

resource "google_project_iam_member" "allow_gcr_pull" {
  project = "${var.gcp_project}"
  member  = "serviceAccount:${google_service_account.account.email}"
  role    = "roles/storage.objectViewer"
}

resource "google_project_iam_member" "allow_log_write" {
  project = "${var.gcp_project}"
  member  = "serviceAccount:${google_service_account.account.email}"
  role    = "roles/logging.logWriter"
}

resource "google_project_iam_member" "allow_monitoring_write" {
  project = "${var.gcp_project}"
  member  = "serviceAccount:${google_service_account.account.email}"
  role    = "roles/monitoring.metricWriter"
}

resource "google_project_iam_member" "allow_compute_instances" {
  project = "${var.gcp_project}"
  member  = "serviceAccount:${google_service_account.account.email}"
  role    = "roles/compute.instanceAdmin.v1"
}

resource "google_project_iam_member" "allow_service_account" {
  project = "${var.gcp_project}"
  member  = "serviceAccount:${google_service_account.account.email}"
  role    = "roles/iam.serviceAccountUser"
}

data "google_container_engine_versions" "versions" {
  project  = "${var.gcp_project}"
  provider = "google-beta"
  region   = "${var.gcp_region}"
}

resource "google_container_cluster" "cluster" {
  name        = "${local.cluster_id}"
  description = "Up cluster ${local.cluster_id}"

  provider = "google-beta"
  region   = "${var.gcp_region}"
  network  = "projects/${var.gcp_project}/global/networks/default"

  master_auth {
    // Disable basic auth by setting a blank username and password.
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = true
    }
  }

  min_master_version = "${data.google_container_engine_versions.versions.latest_master_version}"

  addons_config {
    http_load_balancing {
      disabled = false
    }

    network_policy_config {
      disabled = false
    }

    // We don't really need HPA, but it's useful to have Heapster around.
    horizontal_pod_autoscaling {
      disabled = false
    }

    kubernetes_dashboard {
      disabled = true
    }
  }

  // TODO(negz): Calico provides some degree of security isolation, but we need
  // to chain with the bandwidth CNI plugin for network I/O isolation.
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  // Enable IP Alias ranges to avoid routing table limits
  // https://cloud.google.com/kubernetes-engine/docs/how-to/alias-ips
  ip_allocation_policy {
    create_subnetwork = true
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  // We want to manage node pools using google_container_node_pool clauses.
  // Managing pools inline causes Terraform to recreate the entire GKE cluster
  // any time a node pool is changed.
  lifecycle {
    ignore_changes = ["node_pool"]
  }

  node_pool = {
    name = "default-pool"
  }

  remove_default_node_pool = true
}

// The base set of GKE infrastructure pods need somewhere to run. Giving them
// their own node pool isolates them somewhat from the effects of the control
// planes we're running.
resource "google_container_node_pool" "infra" {
  name = "${local.cluster_id}-infra"

  provider = "google-beta"
  region   = "${var.gcp_region}"
  cluster  = "${google_container_cluster.cluster.name}"

  node_count = 1 // One node per zone.

  node_config {
    machine_type = "${var.node_pool_infra_machine_type}"
    image_type   = "${var.node_pool_infra_image_type}"
    disk_size_gb = "${var.node_pool_infra_disk_size_gb}"
    disk_type    = "${var.node_pool_infra_disk_type}"
    preemptible  = "${var.node_pool_infra_preemptible}"

    metadata = {
      managed_by = "up"
      cluster_id = "${local.cluster_id}"
    }

    labels = {
      cluster_id = "${local.cluster_id}"
      node_pool  = "infra"
    }

    tags = ["${local.cluster_id}", "infra"]

    service_account = "${google_service_account.account.email}"
  }
}

// This node pool is intended to run 'light' control planes, i.e. control planes
// that are not allocated dedicated nodes. We assume many control planes will
// see relatively light use over their lifetime, so they start in this node pool
// until we observe heavy enough use to promote them to dedicated nodes.
resource "google_container_node_pool" "light" {
  name = "${local.cluster_id}-light"

  provider = "google-beta"
  region   = "${var.gcp_region}"
  cluster  = "${google_container_cluster.cluster.name}"

  autoscaling = {
    min_node_count = "${var.node_pool_light_min_node_count}"
    max_node_count = "${var.node_pool_light_max_node_count}"
  }

  node_config {
    machine_type = "${var.node_pool_light_machine_type}"
    image_type   = "${var.node_pool_light_image_type}"
    disk_size_gb = "${var.node_pool_light_disk_size_gb}"
    disk_type    = "${var.node_pool_light_disk_type}"
    preemptible  = "${var.node_pool_light_preemptible}"

    metadata = {
      managed_by = "up"
      cluster_id = "${local.cluster_id}"
    }

    taint = {
      key    = "up.rk0n.org/pool_type"
      value  = "light"
      effect = "NO_SCHEDULE"
    }

    labels = {
      cluster_id              = "${local.cluster_id}"
      "up.rk0n.org/pool_type" = "light"
    }

    tags = ["${local.cluster_id}", "light"]

    service_account = "${google_service_account.account.email}"
  }
}

// This node pool is intended to run 'dedicated' control planes. It would
// typically be sized appropriately such that each node would run one etcd pod,
// one API server pod, and one controller manager pod.
resource "google_container_node_pool" "dedicated" {
  name = "${local.cluster_id}-dedicated"

  provider = "google-beta"
  region   = "${var.gcp_region}"
  cluster  = "${google_container_cluster.cluster.name}"

  autoscaling = {
    min_node_count = "${var.node_pool_dedicated_min_node_count}"
    max_node_count = "${var.node_pool_dedicated_max_node_count}"
  }

  node_config {
    machine_type = "${var.node_pool_dedicated_machine_type}"
    image_type   = "${var.node_pool_dedicated_image_type}"
    disk_size_gb = "${var.node_pool_dedicated_disk_size_gb}"
    disk_type    = "${var.node_pool_dedicated_disk_type}"
    preemptible  = "${var.node_pool_dedicated_preemptible}"

    metadata = {
      managed_by = "up"
      cluster_id = "${local.cluster_id}"
    }

    taint = {
      key    = "up.rk0n.org/pool_type"
      value  = "dedicated"
      effect = "NO_SCHEDULE"
    }

    labels = {
      cluster_id              = "${local.cluster_id}"
      "up.rk0n.org/pool_type" = "dedicated"
    }

    tags = ["${local.cluster_id}", "dedicated"]

    service_account = "${google_service_account.account.email}"
  }
}
