variable "gcp_project" {
  description = "The name of the GCP Project where all resources will be launched."
}

variable "gcp_region" {
  description = "The region in which all GCP resources will be launched."
}

variable "node_pool_infra_machine_type" {
  description = "Machine type to use for the infra node pool."
  default     = "n1-standard-1"
}

variable node_pool_infra_preemptible {
  description = "Whether the infra pool should use preemptible instances."
  default     = false
}

variable node_pool_infra_min_node_count {
  description = "Minium node count per zone for the infra node pool."
  default     = 0
}

variable node_pool_infra_max_node_count {
  description = "Maximum node count per zone for the infra node pool."
  default     = 1
}

variable node_pool_infra_image_type {
  description = "Machine image for the infra node pool."
  default     = "COS"
}

variable node_pool_infra_disk_size_gb {
  description = "Boot disk disk, in GB, for the infra node pool."
  default     = 32
}

variable node_pool_infra_disk_type {
  description = "Boot disk type for the infra node pool."
  default     = "pd-ssd"
}

variable "node_pool_light_machine_type" {
  description = "Machine type to use for the light node pool."
  default     = "n1-standard-1"
}

variable node_pool_light_preemptible {
  description = "Whether the light pool should use preemptible instances."
  default     = true
}

variable node_pool_light_min_node_count {
  description = "Minium node count per zone for the light node pool."
  default     = 0
}

variable node_pool_light_max_node_count {
  description = "Maximum node count per zone for the light node pool."
  default     = 1
}

variable node_pool_light_image_type {
  description = "Machine image for the light node pool."
  default     = "COS"
}

variable node_pool_light_disk_size_gb {
  description = "Boot disk disk, in GB, for the light node pool."
  default     = 32
}

variable node_pool_light_disk_type {
  description = "Boot disk type for the light node pool."
  default     = "pd-ssd"
}

variable "node_pool_dedicated_machine_type" {
  description = "Machine type to use for the dedicated node pool."
  default     = "n1-standard-1"
}

variable node_pool_dedicated_preemptible {
  description = "Whether the dedicated pool should use preemptible instances."
  default     = true
}

variable node_pool_dedicated_min_node_count {
  description = "Minium node count per zone for the dedicated node pool."
  default     = 0
}

variable node_pool_dedicated_max_node_count {
  description = "Maximum node count per zone for the dedicated node pool."
  default     = 1
}

variable node_pool_dedicated_image_type {
  description = "Machine image for the dedicated node pool."
  default     = "COS"
}

variable node_pool_dedicated_disk_size_gb {
  description = "Boot disk disk, in GB, for the dedicated node pool."
  default     = 32
}

variable node_pool_dedicated_disk_type {
  description = "Boot disk type for the dedicated node pool."
  default     = "pd-ssd"
}
