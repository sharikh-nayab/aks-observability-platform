variable "project" {
  description = "Short name used as a prefix for every resource."
  type        = string
  default     = "obsplat"
}

variable "environment" {
  description = "dev / stage / prod. Drives naming and a couple of sizing defaults."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of dev, stage, prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "tags" {
  description = "Tags applied to everything. cost-center is what finance actually looks at."
  type        = map(string)
  default = {
    owner       = "sharikh"
    cost-center = "platform"
    managed-by  = "terraform"
  }
}

# ---- network ----------------------------------------------------------------

variable "vnet_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "Node subnet. With Azure CNI overlay pods get their own range, so /22 is plenty."
  type        = string
  default     = "10.40.0.0/22"
}

variable "pod_cidr" {
  description = "Overlay pod range. Must not overlap vnet or service cidr."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "10.0.0.10"
}

# ---- cluster ----------------------------------------------------------------

variable "kubernetes_version" {
  description = "Leave null to take the region default; pin it for anything that isn't a lab."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "Free has no uptime SLA. Standard for anything someone will page about."
  type        = string
  default     = "Free"
}

variable "system_node_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "user_node_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "user_node_min" {
  type    = number
  default = 1
}

variable "user_node_max" {
  type    = number
  default = 5
}

variable "availability_zones" {
  description = "Set to [] in regions without zones (or when you want cheaper lab nodes)."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs that get cluster-admin via Azure RBAC."
  type        = list(string)
  default     = []
}

variable "authorized_ip_ranges" {
  description = "CIDRs allowed to hit the API server. Empty = open, which is fine only for a lab."
  type        = list(string)
  default     = []
}

# ---- observability ----------------------------------------------------------

variable "log_retention_days" {
  type    = number
  default = 30
}
